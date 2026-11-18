// netsec_fabric1g.sv — two 1G copper ports (RGMII MACs) through the byte-wide
// store-and-forward inspection datapath (netsec_datapath, one instance per port).
//
//   mode 0 BOUNCE : rxN -> inspect -> txN with MAC addresses swapped (reflector)
//   mode 1 BRIDGE : rx0 -> inspect -> tx1, rx1 -> inspect -> tx0 (addresses untouched)
//   mode 2 L0     : on-chip pkt_gen_bram frames are inspected, nothing reaches the wire
//   mode 3 DISABLE: rx sunk, tx idle
// gen_start launches the two canned frames of pkt_gen_bram on both ports in any mode
// except DISABLE (in BOUNCE/BRIDGE the surviving frames also leave on the wire).
`timescale 1ns / 1ps
module netsec_fabric1g #(
    parameter FRAME_DEPTH = 2048
) (
    input  logic          clk,
    input  logic          rst_n,
    input  logic          enable,
    input  logic [1:0]    mode,
    input  logic [1:0]    aes_en,
    input  logic [127:0]  aes_key,
    input  logic [127:0]  pats4,          // DPI patterns 0..3
    input  logic          gen_start,

    input  logic [15:0]   rx_tdata,       // {port1, port0}
    input  logic [1:0]    rx_tvalid,
    input  logic [1:0]    rx_tlast,
    output logic [1:0]    rx_tready,

    output logic [15:0]   tx_tdata,
    output logic [1:0]    tx_tvalid,
    output logic [1:0]    tx_tlast,
    input  logic [1:0]    tx_tready,

    output logic [1:0]    p_rx, p_tx, p_fwd, p_drop, p_mir, p_dpi,
    output logic [3:0]    last_action,
    output logic [255:0]  aes_ct,
    output logic [1:0]    aes_done
);
    localparam [1:0] M_BOUNCE = 2'd0, M_BRIDGE = 2'd1, M_L0 = 2'd2, M_DIS = 2'd3;
    wire dp_on = enable && (mode != M_DIS);

    logic [7:0] m_d [0:1];
    logic [1:0] m_v, m_l, m_r;

    // router: ready for dp output i
    always_comb begin
        for (int i = 0; i < 2; i++) begin
            unique case (mode)
                M_BOUNCE: m_r[i] = tx_tready[i];
                M_BRIDGE: m_r[i] = tx_tready[i ^ 1];
                default:  m_r[i] = 1'b1;           // L0 / DISABLE: sink
            endcase
        end
        for (int j = 0; j < 2; j++) begin
            int s;
            s = (mode == M_BRIDGE) ? (j ^ 1) : j;
            tx_tdata [j*8 +: 8] = m_d[s];
            tx_tvalid[j] = ((mode == M_BOUNCE) || (mode == M_BRIDGE)) ? m_v[s] : 1'b0;
            tx_tlast [j] = ((mode == M_BOUNCE) || (mode == M_BRIDGE)) ? m_l[s] : 1'b0;
        end
    end

    genvar gi;
    generate
        for (gi = 0; gi < 2; gi = gi + 1) begin : g_c
            logic [7:0] g_d; logic g_v, g_l, g_r, g_busy;
            pkt_gen_bram u_gen (.clk(clk), .rst_n(rst_n), .start(gen_start && (mode != M_DIS)),
                                .m_tdata(g_d), .m_tvalid(g_v), .m_tready(g_r), .m_tlast(g_l), .busy(g_busy));

            logic [7:0] s_d; logic s_v, s_l, s_r;
            always_comb begin
                if (g_busy) begin s_d = g_d; s_v = g_v; s_l = g_l; end
                else        begin s_d = rx_tdata[gi*8 +: 8]; s_v = rx_tvalid[gi] && dp_on; s_l = rx_tlast[gi]; end
            end
            assign g_r          = g_busy ? s_r : 1'b0;
            assign rx_tready[gi] = g_busy ? 1'b0 : (dp_on ? s_r : 1'b1);

            netsec_datapath #(.FRAME_DEPTH(FRAME_DEPTH)) u_dp (
                .clk(clk), .rst_n(rst_n), .enable(dp_on),
                .s_tdata(s_d), .s_tvalid(s_v), .s_tready(s_r), .s_tlast(s_l),
                .m_tdata(m_d[gi]), .m_tvalid(m_v[gi]), .m_tready(m_r[gi]), .m_tlast(m_l[gi]),
                .mirror_pulse(), .last_action(last_action[gi*2 +: 2]),
                .stat_rx_frame(p_rx[gi]), .stat_tx_frame(p_tx[gi]), .stat_forward(p_fwd[gi]),
                .stat_drop(p_drop[gi]), .stat_mirror(p_mir[gi]), .stat_dpi_hit(p_dpi[gi]),
                .flow_update_valid(), .flow_update_state(),
                .dpi_pat0(pats4[31:0]), .dpi_pat1(pats4[63:32]), .dpi_pat2(pats4[95:64]), .dpi_pat3(pats4[127:96]),
                .aes_dp_en(aes_en[gi]), .aes_key(aes_key),
                .aes_dp_ct(aes_ct[gi*128 +: 128]), .aes_dp_done(aes_done[gi]),
                .mac_swap_en(mode == M_BOUNCE)
            );
        end
    endgenerate
endmodule
