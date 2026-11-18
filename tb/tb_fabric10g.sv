// tb_fabric10g — 4-port 10G fabric: INLINE pairs, LOOP, BIST, DISABLE, inj_mac,
// bad-frame drop. Uses reduced FIFO/DLY sizes so it runs in seconds.
`timescale 1ns / 1ps
module tb_fabric10g;
    localparam NP = 4;
    parameter AESP = 1;     // override with -P tb_fabric10g.AESP=0 to run with the iterative AES core
    logic clk = 0, rst_n = 0;
    always #3.2 clk = ~clk;

    logic [1:0] mode;
    logic [NP-1:0] dp_en, aes_en, gen_en, inj_start;
    logic gen_to_dp, inj_mac;
    logic [15:0] gap;
    logic [511:0] pats;
    logic [NP*64-1:0] rx_d, tx_d;
    logic [NP*8-1:0]  rx_k, tx_k;
    logic [NP-1:0]    rx_v, rx_l, rx_u, tx_v, tx_r, tx_l, tx_u;
    logic [NP*2-1:0]  last_action;
    logic [NP-1:0] p_rxf_drop, p_rxf_ovf, p_rx, p_tx, p_fwd, p_drop, p_mir, p_dpi, p_csum, p_ovf, p_flow, aes_done, aes_fold;
    logic [NP*16-1:0] p_phit;
    logic [NP*128-1:0] aes_ct;

    netsec_fabric10g #(.NP(NP), .HASH_BITS(8), .ROM_PATTERNS(4), .AES_LANES(1), .AES_PIPE(AESP),
                       .FIFO_BYTES(4096), .DLY(20), .RXFIFO_BYTES(2048)) dut (
        .clk(clk), .rst_n(rst_n), .mode(mode), .dp_en(dp_en), .aes_en(aes_en), .gen_en(gen_en),
        .gen_to_dp(gen_to_dp), .inj_mac(inj_mac), .gap(gap), .inj_start(inj_start),
        .aes_key(128'd0), .pats(pats),
        .rx_tdata(rx_d), .rx_tkeep(rx_k), .rx_tvalid(rx_v), .rx_tlast(rx_l), .rx_tuser(rx_u),
        .tx_tdata(tx_d), .tx_tkeep(tx_k), .tx_tvalid(tx_v), .tx_tready(tx_r), .tx_tlast(tx_l), .tx_tuser(tx_u),
        .last_action(last_action), .p_rxf_drop(p_rxf_drop), .p_rxf_ovf(p_rxf_ovf),
        .p_dp_rx(p_rx), .p_dp_tx(p_tx), .p_dp_fwd(p_fwd), .p_dp_drop(p_drop), .p_dp_mir(p_mir),
        .p_dp_dpi(p_dpi), .p_dp_csum(p_csum), .p_dp_ovf(p_ovf), .p_dp_flow(p_flow),
        .p_phit(p_phit), .aes_ct(aes_ct), .aes_done(aes_done), .aes_fold(aes_fold));

    // ---- monitors ----
    int n_tx [0:NP-1], n_rxdp [0:NP-1], n_mir [0:NP-1], n_dpi [0:NP-1], n_fwd [0:NP-1], n_drop_rxf [0:NP-1];
    logic [63:0] first_w [0:NP-1];
    logic        at_first [0:NP-1];
    int beats_last [0:NP-1], beats_cur [0:NP-1];
    integer m;
    always @(posedge clk) begin
        for (m = 0; m < NP; m = m + 1) begin
            if (!rst_n) begin
                n_tx[m] <= 0; n_rxdp[m] <= 0; n_mir[m] <= 0; n_dpi[m] <= 0; n_fwd[m] <= 0; n_drop_rxf[m] <= 0;
                at_first[m] <= 1'b1; beats_cur[m] <= 0; beats_last[m] <= 0; first_w[m] <= '0;
            end else begin
                if (p_rx[m])       n_rxdp[m] <= n_rxdp[m] + 1;
                if (p_mir[m])      n_mir[m]  <= n_mir[m]  + 1;
                if (p_dpi[m])      n_dpi[m]  <= n_dpi[m]  + 1;
                if (p_fwd[m])      n_fwd[m]  <= n_fwd[m]  + 1;
                if (p_rxf_drop[m]) n_drop_rxf[m] <= n_drop_rxf[m] + 1;
                if (tx_v[m] && tx_r[m]) begin
                    if (at_first[m]) first_w[m] <= tx_d[m*64 +: 64];
                    at_first[m] <= tx_l[m];
                    beats_cur[m] <= tx_l[m] ? 0 : beats_cur[m] + 1;
                    if (tx_l[m]) begin n_tx[m] <= n_tx[m] + 1; beats_last[m] <= beats_cur[m] + 1; end
                end
            end
        end
    end

    // ---- stimulus helper: send an N-beat frame on port p, first word = tag ----
    task automatic send_frame(input int p, input int nbeats, input logic [63:0] tag, input bit bad);
        int b;
        begin
            for (b = 0; b < nbeats; b = b + 1) begin
                rx_v[p] <= 1'b1;
                rx_d[p*64 +: 64] <= (b == 0) ? tag : {tag[63:8], b[7:0]};
                rx_k[p*8 +: 8] <= 8'hFF;
                rx_l[p] <= (b == nbeats-1);
                rx_u[p] <= (b == nbeats-1) && bad;
                @(posedge clk);
            end
            rx_v[p] <= 1'b0; rx_l[p] <= 1'b0; rx_u[p] <= 1'b0;
        end
    endtask

    task automatic pulse_inj(input int p);
        begin @(posedge clk); inj_start[p] <= 1'b1; @(posedge clk); inj_start[p] <= 1'b0; end
    endtask

    task automatic wait_cycles(input int n); repeat (n) @(posedge clk); endtask

    int errors = 0;
    task automatic check(input bit cond, input string msg);
        begin
            if (cond) $display("PASS: %s", msg);
            else begin $display("FAIL: %s", msg); errors = errors + 1; end
        end
    endtask

    int s0, s1, s2, s3;
    initial begin
        mode = 0; dp_en = 4'hF; aes_en = 0; gen_en = 0; inj_start = 0; gen_to_dp = 0; inj_mac = 0; gap = 16'd8;
        pats = '0; pats[31:0] = 32'h47455420;   // "GET "
        rx_v = 0; rx_d = 0; rx_k = 0; rx_l = 0; rx_u = 0; tx_r = {NP{1'b1}};
        wait_cycles(8); rst_n = 1; wait_cycles(60);

        // --- DISABLE: nothing leaves, nothing inspected
        send_frame(0, 8, 64'h1111_0000_0000_0001, 0);
        wait_cycles(300);
        check(n_tx[0]==0 && n_tx[1]==0 && n_rxdp[0]==0, "DISABLE: rx sunk, no tx, no inspection");

        // --- INLINE: port0->tx1, port1->tx0, port2->tx3, port3->tx2
        mode = 1; wait_cycles(4);
        send_frame(0, 8, 64'hAAAA_0000_0000_0100, 0);
        send_frame(1, 9, 64'hBBBB_0000_0000_0200, 0);
        send_frame(2, 10, 64'hCCCC_0000_0000_0300, 0);
        send_frame(3, 11, 64'hDDDD_0000_0000_0400, 0);
        wait_cycles(1200);
        check(n_tx[1]==1 && first_w[1]==64'hAAAA_0000_0000_0100 && beats_last[1]==8,  "INLINE: rx0 -> tx1 intact");
        check(n_tx[0]==1 && first_w[0]==64'hBBBB_0000_0000_0200 && beats_last[0]==9,  "INLINE: rx1 -> tx0 intact");
        check(n_tx[3]==1 && first_w[3]==64'hCCCC_0000_0000_0300 && beats_last[3]==10, "INLINE: rx2 -> tx3 intact");
        check(n_tx[2]==1 && first_w[2]==64'hDDDD_0000_0000_0400 && beats_last[2]==11, "INLINE: rx3 -> tx2 intact");
        check(n_rxdp[0]==1 && n_rxdp[1]==1 && n_rxdp[2]==1 && n_rxdp[3]==1, "INLINE: each port inspected exactly one frame");

        // --- INLINE with injected canned frames (dp path): frame0 forwards, frame1 ("GET ") is mirrored/dropped
        s0 = n_tx[1]; s1 = n_rxdp[0];
        gen_to_dp = 0;
        pulse_inj(0);
        wait_cycles(1500);
        check(n_rxdp[0] - s1 == 2 && n_dpi[0] >= 1 && n_mir[0] >= 1 && n_fwd[0] >= 1 && n_tx[1] - s0 == 1,
              "INLINE inj: 2 inspected, GET frame mirrored(dropped), other forwarded to tx1");
        s2 = n_tx[3]; s3 = n_rxdp[2];
        pulse_inj(2);
        wait_cycles(1500);
        check(n_rxdp[2] - s3 == 2 && n_tx[3] - s2 == 1, "INLINE inj on port 2 -> tx3 (same behaviour per port)");

        // --- bad frame dropped at rx FIFO
        s0 = n_tx[1]; s1 = n_drop_rxf[0];
        send_frame(0, 8, 64'hEEEE_0000_0000_0500, 1);
        wait_cycles(400);
        check(n_tx[1]==s0 && n_drop_rxf[0]==s1+1, "bad (tuser) frame dropped before inspection");

        // --- LOOP: every port returns its own traffic
        mode = 2; wait_cycles(4);
        s0 = n_tx[0]; s1 = n_tx[1]; s2 = n_tx[2]; s3 = n_tx[3];
        send_frame(0, 8, 64'h0A0A_0000_0000_0001, 0);
        send_frame(1, 8, 64'h0B0B_0000_0000_0002, 0);
        send_frame(2, 8, 64'h0C0C_0000_0000_0003, 0);
        send_frame(3, 8, 64'h0D0D_0000_0000_0004, 0);
        wait_cycles(1200);
        check(n_tx[0]==s0+1 && n_tx[1]==s1+1 && n_tx[2]==s2+1 && n_tx[3]==s3+1 &&
              first_w[0]==64'h0A0A_0000_0000_0001 && first_w[3]==64'h0D0D_0000_0000_0004, "LOOP: each port returns its own frame");

        // --- dp bypass on port 1 only (dp_en[1]=0)
        dp_en = 4'b1101; s1 = n_rxdp[1]; s0 = n_tx[1];
        send_frame(1, 8, 64'h0F0F_0000_0000_0009, 0);
        wait_cycles(300);
        check(n_tx[1]==s0+1 && n_rxdp[1]==s1, "dp_en=0: frame bypasses inspection");
        dp_en = 4'hF;

        // --- BIST: generator drives the wire, rx is counted and sunk
        mode = 3; gen_en = 4'b0110; wait_cycles(4);
        s1 = n_tx[1]; s2 = n_tx[2]; s0 = n_tx[0]; s3 = n_tx[3];
        wait_cycles(1500);
        check(n_tx[1] > s1+3 && n_tx[2] > s2+3 && n_tx[0]==s0 && n_tx[3]==s3, "BIST: generators on ports 1,2 only");
        gen_en = 0; wait_cycles(100);

        // --- inj_mac: canned frames go straight to the MAC tx of that port (any mode)
        mode = 0; inj_mac = 1; s3 = n_tx[3]; s2 = n_rxdp[3];
        pulse_inj(3);
        wait_cycles(400);
        check(n_tx[3]==s3+2 && n_rxdp[3]==s2, "inj_mac: 2 canned frames on tx3, not inspected");
        inj_mac = 0;

        // --- gen_to_dp: generator frames inspected without any rx traffic, result returned (LOOP)
        mode = 2; gen_en = 4'b0001; gen_to_dp = 1; s0 = n_rxdp[0]; s1 = n_tx[0];
        wait_cycles(1500);
        gen_en = 0; gen_to_dp = 0; wait_cycles(200);
        check(n_rxdp[0] > s0+2 && n_tx[0] > s1+2, "gen_to_dp: generator frames inspected and returned on tx0");

        if (errors == 0) $display("PASS: tb_fabric10g");
        else $display("FAIL: tb_fabric10g errors=%0d", errors);
        $finish;
    end
    initial begin #20_000_000; $display("FAIL: tb_fabric10g timeout"); $finish; end
endmodule
