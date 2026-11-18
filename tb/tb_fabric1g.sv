`timescale 1ns / 1ps
module tb_fabric1g;
    logic clk = 0, rst_n = 0; always #4 clk = ~clk;
    logic enable = 1; logic [1:0] mode = 3, aes_en = 0; logic gen_start = 0;
    logic [15:0] rx_d = 0; logic [1:0] rx_v = 0, rx_l = 0, rx_r, tx_v, tx_l, tx_r = 2'b11;
    logic [15:0] tx_d; logic [1:0] p_rx, p_tx, p_fwd, p_drop, p_mir, p_dpi; logic [3:0] la; logic [255:0] act; logic [1:0] adone;
    logic [127:0] pats4 = {32'h0, 32'h0, 32'h0, 32'h47455420};
    netsec_fabric1g #(.FRAME_DEPTH(512)) dut (.clk(clk), .rst_n(rst_n), .enable(enable), .mode(mode), .aes_en(aes_en),
        .aes_key(128'h000102030405060708090a0b0c0d0e0f), .pats4(pats4), .gen_start(gen_start),
        .rx_tdata(rx_d), .rx_tvalid(rx_v), .rx_tlast(rx_l), .rx_tready(rx_r),
        .tx_tdata(tx_d), .tx_tvalid(tx_v), .tx_tlast(tx_l), .tx_tready(tx_r),
        .p_rx(p_rx), .p_tx(p_tx), .p_fwd(p_fwd), .p_drop(p_drop), .p_mir(p_mir), .p_dpi(p_dpi),
        .last_action(la), .aes_ct(act), .aes_done(adone));

    // capture frames per tx port
    byte unsigned cap [0:1][0:127]; int caplen [0:1]; int nfr [0:1]; int idx [0:1];
    always @(posedge clk) for (int j = 0; j < 2; j++) if (tx_v[j] && tx_r[j]) begin
        if (idx[j] < 128) cap[j][idx[j]] = tx_d[j*8 +: 8];
        idx[j] = idx[j] + 1;
        if (tx_l[j]) begin caplen[j] = idx[j]; nfr[j] = nfr[j] + 1; idx[j] = 0; end
    end
    int n_rx0, n_dpi0, n_mir0; always @(posedge clk) begin if (p_rx[0]) n_rx0++; if (p_dpi[0]) n_dpi0++; if (p_mir[0]) n_mir0++; end

    byte unsigned frm [0:63];
    task automatic send(input int p, input bit get);
        begin
            for (int i = 0; i < 64; i++) frm[i] = 8'h00;
            // DA 02:aa:bb:cc:dd:01  SA 02:11:22:33:44:02  IPv4/TCP
            frm[0]=8'h02; frm[1]=8'hAA; frm[2]=8'hBB; frm[3]=8'hCC; frm[4]=8'hDD; frm[5]=8'h01;
            frm[6]=8'h02; frm[7]=8'h11; frm[8]=8'h22; frm[9]=8'h33; frm[10]=8'h44; frm[11]=8'h02;
            frm[12]=8'h08; frm[13]=8'h00; frm[14]=8'h45; frm[17]=get ? 8'h2C : 8'h28; frm[20]=8'h40; frm[22]=8'h40; frm[23]=8'h06;
            frm[26]=8'hC0; frm[27]=8'hA8; frm[28]=8'h01; frm[29]=8'h02; frm[30]=8'hC0; frm[31]=8'hA8; frm[32]=8'h01; frm[33]=8'h64;
            frm[34]=8'h04; frm[35]=8'hD2; frm[36]=8'h00; frm[37]=8'h50; frm[46]=8'h50; frm[47]=8'h02; frm[48]=8'h20;
            if (get) begin frm[54]=8'h47; frm[55]=8'h45; frm[56]=8'h54; frm[57]=8'h20; end
            for (int i = 0; i < 64; i++) begin
                rx_d[p*8 +: 8] = frm[i]; rx_v[p] = 1; rx_l[p] = (i == 63);
                @(posedge clk); while (!rx_r[p]) @(posedge clk);
            end
            rx_v[p] = 0; rx_l[p] = 0;
        end
    endtask
    int errors = 0;
    task automatic check(input bit c, input string m); begin if (c) $display("PASS: %s", m); else begin $display("FAIL: %s", m); errors++; end end endtask

    initial begin
        nfr[0]=0; nfr[1]=0; idx[0]=0; idx[1]=0; caplen[0]=0; caplen[1]=0;
        repeat (6) @(posedge clk); rst_n = 1;
        repeat (8000) @(posedge clk);          // u_dpi_matcher expands its 17x256 transition table after reset (~4.5k cycles)
        // DISABLE
        send(0, 0); repeat (200) @(posedge clk);
        check(nfr[0]==0 && nfr[1]==0 && n_rx0==0, "DISABLE: sunk, nothing out");
        // BOUNCE: MAC swap on same port
        mode = 0; repeat (4) @(posedge clk);
        send(0, 0); repeat (400) @(posedge clk);
        check(nfr[0]==1 && nfr[1]==0 && caplen[0]==64, "BOUNCE: frame returns on the same port, 64 bytes");
        check(cap[0][0]==8'h02 && cap[0][1]==8'h11 && cap[0][5]==8'h02 && cap[0][6]==8'h02 && cap[0][7]==8'hAA && cap[0][11]==8'h01,
              "BOUNCE: DA/SA swapped");
        // BRIDGE: port0 -> port1, headers unchanged
        mode = 1; repeat (4) @(posedge clk);
        send(0, 0); repeat (400) @(posedge clk);
        check(nfr[1]==1 && nfr[0]==1 && cap[1][0]==8'h02 && cap[1][1]==8'hAA && cap[1][6]==8'h02 && cap[1][7]==8'h11, "BRIDGE: rx0 -> tx1, MACs untouched");
        send(1, 0); repeat (400) @(posedge clk);
        check(nfr[0]==2, "BRIDGE: rx1 -> tx0");
        // DPI: GET payload mirrored (dropped) on port 0
        n_dpi0 = 0; n_mir0 = 0;
        send(0, 1); repeat (400) @(posedge clk);
        check(nfr[1]==1 && n_dpi0==1 && n_mir0==1, "DPI hit on 'GET ' -> mirrored/dropped, not forwarded");
        // L0 internal generator: inspected, nothing on the wire
        mode = 2; repeat (4) @(posedge clk);
        n_rx0 = 0; gen_start = 1; @(posedge clk); gen_start = 0; repeat (1500) @(posedge clk);
        check(n_rx0 == 2 && nfr[0]==2 && nfr[1]==1, "L0: generator frames inspected, wire silent");
        if (errors == 0) $display("PASS: tb_fabric1g"); else $display("FAIL: tb_fabric1g errors=%0d", errors);
        $finish;
    end
    initial begin #5_000_000; $display("FAIL: tb_fabric1g timeout"); $finish; end
endmodule
