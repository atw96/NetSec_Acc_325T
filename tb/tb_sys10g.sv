// tb_sys10g — fabric10g + four real eth_mac_10g MACs, XGMII cabled pairwise
// (port0<->port1, port2<->port3) — i.e. everything above the PCS/PMA.
`timescale 1ns / 1ps
module tb_sys10g;
    localparam NP = 4;
    logic clk = 0, rst_n = 0; always #3.2 clk = ~clk;
    wire rst = ~rst_n;

    logic [1:0] mode = 0; logic [NP-1:0] dp_en = 4'hF, aes_en = 0, gen_en = 0, inj_start = 0;
    logic gen_to_dp = 0, inj_mac = 0; logic [15:0] gap = 16'd4; logic [511:0] pats = 0;
    wire [NP*64-1:0] rx_d, tx_d; wire [NP*8-1:0] rx_k, tx_k; wire [NP-1:0] rx_v, rx_l, rx_u, tx_v, tx_r, tx_l, tx_u;
    wire [NP*64-1:0] xg_txd, xg_rxd; wire [NP*8-1:0] xg_txc, xg_rxc;
    wire [NP-1:0] uf, bfrm, bfcs;

    // "cables": tx of port i -> rx of port i^1
    genvar i;
    generate for (i = 0; i < NP; i = i + 1) begin : g
        assign xg_rxd[i*64 +: 64] = xg_txd[(i^1)*64 +: 64];
        assign xg_rxc[i*8  +: 8 ] = xg_txc[(i^1)*8  +: 8 ];
        mac10g_port u_mac (.clk(clk), .rst(rst),
            .tx_tdata(tx_d[i*64 +: 64]), .tx_tkeep(tx_k[i*8 +: 8]), .tx_tvalid(tx_v[i]), .tx_tready(tx_r[i]), .tx_tlast(tx_l[i]), .tx_tuser(tx_u[i]),
            .rx_tdata(rx_d[i*64 +: 64]), .rx_tkeep(rx_k[i*8 +: 8]), .rx_tvalid(rx_v[i]), .rx_tlast(rx_l[i]), .rx_tuser(rx_u[i]),
            .xgmii_rxd(xg_rxd[i*64 +: 64]), .xgmii_rxc(xg_rxc[i*8 +: 8]), .xgmii_txd(xg_txd[i*64 +: 64]), .xgmii_txc(xg_txc[i*8 +: 8]),
            .st_tx_underflow(uf[i]), .st_rx_bad_frame(bfrm[i]), .st_rx_bad_fcs(bfcs[i]));
    end endgenerate

    wire [NP-1:0] p_rxf_drop, p_rxf_ovf, p_rx, p_tx, p_fwd, p_drop, p_mir, p_dpi, p_csum, p_ovf, p_flow, aes_done, aes_fold;
    wire [NP*16-1:0] p_phit; wire [NP*128-1:0] aes_ct; wire [NP*2-1:0] la;
    netsec_fabric10g #(.NP(NP), .HASH_BITS(8), .ROM_PATTERNS(4), .FIFO_BYTES(4096), .DLY(20), .RXFIFO_BYTES(2048)) dut (
        .clk(clk), .rst_n(rst_n), .mode(mode), .dp_en(dp_en), .aes_en(aes_en), .gen_en(gen_en), .gen_to_dp(gen_to_dp),
        .inj_mac(inj_mac), .gap(gap), .inj_start(inj_start), .aes_key(128'd0), .pats(pats),
        .rx_tdata(rx_d), .rx_tkeep(rx_k), .rx_tvalid(rx_v), .rx_tlast(rx_l), .rx_tuser(rx_u),
        .tx_tdata(tx_d), .tx_tkeep(tx_k), .tx_tvalid(tx_v), .tx_tready(tx_r), .tx_tlast(tx_l), .tx_tuser(tx_u),
        .last_action(la), .p_rxf_drop(p_rxf_drop), .p_rxf_ovf(p_rxf_ovf), .p_dp_rx(p_rx), .p_dp_tx(p_tx), .p_dp_fwd(p_fwd),
        .p_dp_drop(p_drop), .p_dp_mir(p_mir), .p_dp_dpi(p_dpi), .p_dp_csum(p_csum), .p_dp_ovf(p_ovf), .p_dp_flow(p_flow),
        .p_phit(p_phit), .aes_ct(aes_ct), .aes_done(aes_done), .aes_fold(aes_fold));

    int mac_rx [0:NP-1], mac_tx [0:NP-1], n_bfcs [0:NP-1], n_bfrm [0:NP-1], n_uf [0:NP-1];
    int n_rx [0:NP-1], n_mir [0:NP-1], n_dpi [0:NP-1], n_drop_rxf [0:NP-1];
    always @(posedge clk) for (int m = 0; m < NP; m++) begin
        if (!rst_n) begin mac_rx[m]=0; mac_tx[m]=0; n_bfcs[m]=0; n_bfrm[m]=0; n_uf[m]=0; n_rx[m]=0; n_mir[m]=0; n_dpi[m]=0; n_drop_rxf[m]=0; end
        else begin
            if (rx_v[m] && rx_l[m]) mac_rx[m]++;
            if (tx_v[m] && tx_r[m] && tx_l[m]) mac_tx[m]++;
            if (bfcs[m]) n_bfcs[m]++; if (bfrm[m]) n_bfrm[m]++; if (uf[m]) n_uf[m]++;
            if (p_rx[m]) n_rx[m]++; if (p_mir[m]) n_mir[m]++; if (p_dpi[m]) n_dpi[m]++; if (p_rxf_drop[m]) n_drop_rxf[m]++;
        end
    end
    int errors = 0; int s0, s1;
    task automatic check(input bit c, input string m); begin if (c) $display("PASS: %s", m); else begin $display("FAIL: %s", m); errors++; end end endtask

    initial begin
        pats[31:0] = 32'h47455420;
        repeat (8) @(posedge clk); rst_n = 1; repeat (60) @(posedge clk);

        // 1) BIST: generator on port 0 -> MAC0 tx -> XGMII -> MAC1 rx
        mode = 3; gen_en = 4'b0001;
        repeat (3000) @(posedge clk);
        gen_en = 0; repeat (200) @(posedge clk);
        check(mac_tx[0] > 10 && mac_rx[1] == mac_tx[0], $sformatf("BIST: %0d frames sent by MAC0, all received by MAC1", mac_tx[0]));
        check(n_bfcs[1] == 0 && n_bfrm[1] == 0 && n_uf[0] == 0, "BIST: no FCS errors / bad frames / underflows through the 64-bit XGMII path");

        // 2) INLINE with MAC-level injection: the injected pair enters port 1 (cable tx0->rx1); dp1 forwards to tx0, which the
        //    cable returns to rx1, so the benign frame loops through dp1 while the GET frame is dropped on its first pass
        mode = 1; inj_mac = 1; s0 = mac_rx[1];
        @(posedge clk); inj_start[0] <= 1; @(posedge clk); inj_start[0] <= 0;
        repeat (4000) @(posedge clk);
        mode = 0; repeat (400) @(posedge clk);
        check(n_dpi[1] == 1 && n_mir[1] == 1, "INLINE e2e: 'GET ' frame detected and mirrored(dropped) by port 1 engine");
        check(n_rx[1] >= 20 && n_rx[0] == 0, $sformatf("INLINE e2e: benign frame keeps circulating MAC->FIFO->dp1->MAC (%0d passes; cabling returns tx0 to rx1)", n_rx[1]));
        check(n_bfcs[0] == 0 && n_bfcs[1] == 0 && n_drop_rxf[0] == 0 && n_drop_rxf[1] == 0, "INLINE e2e: no FCS errors, no rx FIFO drops");

        if (errors == 0) $display("PASS: tb_sys10g"); else $display("FAIL: tb_sys10g errors=%0d", errors);
        $finish;
    end
    initial begin #30_000_000; $display("FAIL: tb_sys10g timeout"); $finish; end
endmodule
