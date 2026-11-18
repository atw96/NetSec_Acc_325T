// netsec_fabric10g.sv — NP-port 10G inspection fabric (all ports on one clock).
//
//   MAC rx -> frame FIFO (drops bad/oversize frames; the MAC cannot be stalled)
//          -> [local generator / one-shot injector may replace the rx stream]
//          -> netsec_dp64 (parser + flow table + DPI + IPS [+AES window]) or bypass
//          -> router -> MAC tx of the destination port
//
//   mode 0 DISABLE : rx sunk, tx idle
//   mode 1 INLINE  : bump-in-the-wire pairs (0<->1, 2<->3): rx0->tx1, rx1->tx0, ...
//   mode 2 LOOP    : each port returns its own traffic: rxN -> txN
//   mode 3 BIST    : generator frames go to the wire; rx is counted and sunk
//   gen_to_dp      : generator/injector frames enter the inspection engine of the
//                    same port instead of coming from the MAC (no cable needed)
//   inj_mac        : one-shot injector frames go straight to the MAC tx
`timescale 1ns / 1ps

module netsec_fabric10g #(
    parameter NP           = 4,
    parameter HASH_BITS    = 10,
    parameter NUM_PAT      = 16,
    parameter ROM_PATTERNS = 160,
    parameter AES_PIPE     = 1,
    parameter AES_LANES    = 1,
    parameter FIFO_BYTES   = 65536,
    parameter DLY          = 480,
    parameter RXFIFO_BYTES = 8192
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic [1:0]              mode,
    input  logic [NP-1:0]           dp_en,
    input  logic [NP-1:0]           aes_en,
    input  logic [NP-1:0]           gen_en,
    input  logic                    gen_to_dp,
    input  logic                    inj_mac,
    input  logic [15:0]             gap,
    input  logic [NP-1:0]           inj_start,
    input  logic [127:0]            aes_key,
    input  logic [NUM_PAT*32-1:0]   pats,

    input  logic [NP*64-1:0]        rx_tdata,
    input  logic [NP*8-1:0]         rx_tkeep,
    input  logic [NP-1:0]           rx_tvalid,
    input  logic [NP-1:0]           rx_tlast,
    input  logic [NP-1:0]           rx_tuser,

    output logic [NP*64-1:0]        tx_tdata,
    output logic [NP*8-1:0]         tx_tkeep,
    output logic [NP-1:0]           tx_tvalid,
    input  logic [NP-1:0]           tx_tready,
    output logic [NP-1:0]           tx_tlast,
    output logic [NP-1:0]           tx_tuser,

    output logic [NP*2-1:0]         last_action,
    output logic [NP-1:0]           p_rxf_drop,
    output logic [NP-1:0]           p_rxf_ovf,
    output logic [NP-1:0]           p_dp_rx,
    output logic [NP-1:0]           p_dp_tx,
    output logic [NP-1:0]           p_dp_fwd,
    output logic [NP-1:0]           p_dp_drop,
    output logic [NP-1:0]           p_dp_mir,
    output logic [NP-1:0]           p_dp_dpi,
    output logic [NP-1:0]           p_dp_csum,
    output logic [NP-1:0]           p_dp_ovf,
    output logic [NP-1:0]           p_dp_flow,
    output logic [NP*NUM_PAT-1:0]   p_phit,
    output logic [NP*128-1:0]       aes_ct,
    output logic [NP-1:0]           aes_done,
    output logic [NP-1:0]           aes_fold
);
    localparam [1:0] M_DISABLE = 2'd0, M_INLINE = 2'd1, M_LOOP = 2'd2, M_BIST = 2'd3;
    wire inspect = (mode == M_INLINE) || (mode == M_LOOP);
    wire inline_m = (mode == M_INLINE);

    // Per-port stream bundles that the router needs to see.
    logic [63:0] o_d [0:NP-1];  logic [7:0] o_k [0:NP-1];
    logic        o_v [0:NP-1];  logic o_l [0:NP-1];  logic o_u [0:NP-1];
    logic        o_r [0:NP-1];

    logic [63:0] g_d [0:NP-1];  logic [7:0] g_k [0:NP-1];
    logic        g_v [0:NP-1];  logic g_l [0:NP-1];  logic g_u [0:NP-1];
    logic [NP-1:0] g_r_wire;                       // tx ready seen by the generator
    logic [63:0] j_d [0:NP-1];  logic [7:0] j_k [0:NP-1];
    logic        j_v [0:NP-1];  logic j_l [0:NP-1];  logic j_u [0:NP-1];
    logic [NP-1:0] j_r_wire;                       // tx ready seen by the injector
    logic [NP-1:0] inj_busy;

    // A generator/injector frame that is already being sent to the MAC keeps its TX path
    // until its last beat, even if gen_en / inj_mac / mode change underneath it
    // (otherwise the MAC would see tvalid drop mid-frame = TX underflow).
    logic [NP-1:0] gen_hold, inj_hold;
    integer hk;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gen_hold <= '0; inj_hold <= '0;
        end else begin
            for (hk = 0; hk < NP; hk = hk + 1) begin
                gen_hold[hk] <= g_v[hk] ? (gen_hold[hk] | ((mode == M_BIST) & gen_en[hk])) : 1'b0;
                inj_hold[hk] <= j_v[hk] ? (inj_hold[hk] | (inj_busy[hk] & inj_mac))       : 1'b0;
            end
        end
    end

    // ---------------- TX router ----------------
    logic [63:0] t_d [0:NP-1];  logic [7:0] t_k [0:NP-1];
    logic        t_v [0:NP-1];  logic t_l [0:NP-1];  logic t_u [0:NP-1];
    integer rj, rs;
    always_comb begin
        for (rj = 0; rj < NP; rj = rj + 1) begin
            t_d[rj] = '0; t_k[rj] = '0; t_v[rj] = 1'b0; t_l[rj] = 1'b0; t_u[rj] = 1'b0;
            o_r[rj] = 1'b0;
        end
        g_r_wire = '0;
        j_r_wire = '0;
        for (rj = 0; rj < NP; rj = rj + 1) begin
            rs = inline_m ? (rj ^ 1) : rj;
            if ((inj_busy[rj] && inj_mac) || (inj_hold[rj] && j_v[rj])) begin
                t_d[rj] = j_d[rj]; t_k[rj] = j_k[rj]; t_v[rj] = j_v[rj]; t_l[rj] = j_l[rj]; t_u[rj] = j_u[rj];
                j_r_wire[rj] = tx_tready[rj];
            end else if (((mode == M_BIST) && gen_en[rj]) || (gen_hold[rj] && g_v[rj])) begin
                t_d[rj] = g_d[rj]; t_k[rj] = g_k[rj]; t_v[rj] = g_v[rj]; t_l[rj] = g_l[rj]; t_u[rj] = g_u[rj];
                g_r_wire[rj] = tx_tready[rj];
            end else if (inspect) begin
                t_d[rj] = o_d[rs]; t_k[rj] = o_k[rs]; t_v[rj] = o_v[rs]; t_l[rj] = o_l[rs]; t_u[rj] = o_u[rs];
                o_r[rs] = tx_tready[rj];
            end
        end
    end

    genvar gi;
    generate
        for (gi = 0; gi < NP; gi = gi + 1) begin : g_p
            assign tx_tdata [gi*64 +: 64] = t_d[gi];
            assign tx_tkeep [gi*8  +: 8 ] = t_k[gi];
            assign tx_tvalid[gi]          = t_v[gi];
            assign tx_tlast [gi]          = t_l[gi];
            assign tx_tuser [gi]          = t_u[gi];

            // --- rx frame FIFO (same clock) ---
            logic [63:0] f_d; logic [7:0] f_k; logic f_v, f_l, f_u, f_r;
            logic        f_ovf, f_bad;
            axis_fifo #(
                .DEPTH(RXFIFO_BYTES), .DATA_WIDTH(64), .KEEP_ENABLE(1), .KEEP_WIDTH(8),
                .LAST_ENABLE(1), .ID_ENABLE(0), .DEST_ENABLE(0), .USER_ENABLE(1), .USER_WIDTH(1),
                .FRAME_FIFO(1), .USER_BAD_FRAME_VALUE(1'b1), .USER_BAD_FRAME_MASK(1'b1),
                .DROP_OVERSIZE_FRAME(1), .DROP_BAD_FRAME(1), .DROP_WHEN_FULL(1)
            ) u_rxf (
                .clk(clk), .rst(~rst_n),
                .s_axis_tdata(rx_tdata[gi*64 +: 64]), .s_axis_tkeep(rx_tkeep[gi*8 +: 8]),
                .s_axis_tvalid(rx_tvalid[gi]), .s_axis_tready(),
                .s_axis_tlast(rx_tlast[gi]), .s_axis_tid(8'd0), .s_axis_tdest(8'd0),
                .s_axis_tuser(rx_tuser[gi]),
                .m_axis_tdata(f_d), .m_axis_tkeep(f_k), .m_axis_tvalid(f_v), .m_axis_tready(f_r),
                .m_axis_tlast(f_l), .m_axis_tid(), .m_axis_tdest(), .m_axis_tuser(f_u),
                .pause_req(1'b0), .pause_ack(),
                .status_depth(), .status_depth_commit(),
                .status_overflow(f_ovf), .status_bad_frame(f_bad), .status_good_frame()
            );
            assign p_rxf_drop[gi] = f_bad;
            assign p_rxf_ovf[gi]  = f_ovf;

            // --- local generator + one-shot injector ---
            logic gen_ready, inj_ready;
            pkt_gen_10g #(.PORT_ID(8'h10 + gi)) u_gen (
                .clk(clk), .rst(~rst_n), .enable(gen_en[gi]), .gap_cycles(gap),
                .m_tdata(g_d[gi]), .m_tkeep(g_k[gi]), .m_tvalid(g_v[gi]), .m_tready(gen_ready),
                .m_tlast(g_l[gi]), .m_tuser(g_u[gi]), .pulse_tx()
            );
            pkt_gen_inj64 u_inj (
                .clk(clk), .rst_n(rst_n), .start(inj_start[gi]),
                .m_tdata(j_d[gi]), .m_tkeep(j_k[gi]), .m_tvalid(j_v[gi]), .m_tready(inj_ready),
                .m_tlast(j_l[gi]), .m_tuser(j_u[gi]), .busy(inj_busy[gi])
            );

            wire inj_to_dp = inj_busy[gi] && !inj_mac;
            wire gen_dp    = !inj_busy[gi] && gen_to_dp && gen_en[gi] && inspect;
            wire loc_to_dp = inj_to_dp || gen_dp;

            // dp input stream (a_*) : local source or rx FIFO
            logic [63:0] a_d; logic [7:0] a_k; logic a_v, a_l, a_u, a_r;
            always_comb begin
                if (inj_to_dp) begin
                    a_d = j_d[gi]; a_k = j_k[gi]; a_l = j_l[gi]; a_u = j_u[gi]; a_v = inspect && j_v[gi];
                end else if (gen_dp) begin
                    a_d = g_d[gi]; a_k = g_k[gi]; a_l = g_l[gi]; a_u = g_u[gi]; a_v = inspect && g_v[gi];
                end else begin
                    a_d = f_d; a_k = f_k; a_l = f_l; a_u = f_u; a_v = inspect && f_v;
                end
            end
            assign f_r       = loc_to_dp ? 1'b0 : (inspect ? a_r : 1'b1);
            assign inj_ready = inj_busy[gi] ? (inj_mac ? j_r_wire[gi] : (inspect ? a_r : 1'b1)) : 1'b0;
            assign gen_ready = inj_busy[gi] ? 1'b0 :
                               (gen_dp ? a_r : ((mode == M_BIST) ? g_r_wire[gi] : 1'b0));

            // --- inspection engine or bypass ---
            logic [63:0] m_d; logic [7:0] m_k; logic m_v, m_l, m_u, m_r, a_r_dp;
            logic [1:0]  la;
            netsec_dp64 #(
                .HASH_BITS(HASH_BITS), .NUM_PAT(NUM_PAT), .ROM_PATTERNS(ROM_PATTERNS),
                .AES_PIPE(AES_PIPE), .AES_LANES(AES_LANES), .FIFO_BYTES(FIFO_BYTES), .DLY(DLY)
            ) u_dp (
                .clk(clk), .rst_n(rst_n), .enable(inspect && dp_en[gi]),
                .s_tdata(a_d), .s_tkeep(a_k), .s_tvalid(dp_en[gi] ? a_v : 1'b0),
                .s_tready(a_r_dp), .s_tlast(a_l), .s_tuser(a_u),
                .m_tdata(m_d), .m_tkeep(m_k), .m_tvalid(m_v), .m_tready(m_r),
                .m_tlast(m_l), .m_tuser(m_u),
                .pats(pats), .aes_en(aes_en[gi]), .aes_key(aes_key),
                .aes_ct(aes_ct[gi*128 +: 128]), .aes_done(aes_done[gi]), .aes_fold_pulse(aes_fold[gi]),
                .last_action(la),
                .stat_rx(p_dp_rx[gi]), .stat_tx(p_dp_tx[gi]), .stat_fwd(p_dp_fwd[gi]),
                .stat_drop(p_dp_drop[gi]), .stat_mir(p_dp_mir[gi]), .stat_dpi(p_dp_dpi[gi]),
                .stat_csum(p_dp_csum[gi]), .stat_ovf(p_dp_ovf[gi]), .stat_flow(p_dp_flow[gi]),
                .stat_phit(p_phit[gi*NUM_PAT +: NUM_PAT])
            );
            assign last_action[gi*2 +: 2] = la;

            assign o_d[gi] = dp_en[gi] ? m_d : a_d;
            assign o_k[gi] = dp_en[gi] ? m_k : a_k;
            assign o_v[gi] = dp_en[gi] ? m_v : a_v;
            assign o_l[gi] = dp_en[gi] ? m_l : a_l;
            assign o_u[gi] = dp_en[gi] ? m_u : a_u;
            assign m_r     = o_r[gi];
            assign a_r     = dp_en[gi] ? a_r_dp : o_r[gi];
        end
    endgenerate
endmodule
