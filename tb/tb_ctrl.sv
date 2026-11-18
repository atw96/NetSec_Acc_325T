// tb_ctrl — UART -> AXI4-Lite bridge -> register file, stat banks, MMIO engines,
// plus phy_mgmt against a behavioural RTL8211F MDIO model.
`timescale 1ns / 1ps
module tb_ctrl;
    localparam integer CLK_HZ = 11_059_200, BAUD = 115200;
    localparam real    TCLK = 1.0e9 / CLK_HZ;
    logic clk = 0, rst_n = 0;
    always #(TCLK/2) clk = ~clk;
    int errors = 0;

    // ---------------- UART host side ----------------
    logic uart_rx_to_dut = 1'b1;
    wire  uart_tx_from_dut;
    task automatic ubyte(input [7:0] b);
        integer i;
        begin
            uart_rx_to_dut = 1'b0; #(1.0e9/BAUD);
            for (i = 0; i < 8; i = i + 1) begin uart_rx_to_dut = b[i]; #(1.0e9/BAUD); end
            uart_rx_to_dut = 1'b1; #(1.0e9/BAUD);
        end
    endtask
    logic [7:0] rxq [0:15]; integer rxn = 0;
    always begin : uart_mon
        logic [7:0] sh; integer i;
        @(negedge uart_tx_from_dut);
        #(0.5e9/BAUD);
        for (i = 0; i < 8; i = i + 1) begin #(1.0e9/BAUD); sh[i] = uart_tx_from_dut; end
        #(1.0e9/BAUD);
        rxq[rxn % 16] = sh; rxn = rxn + 1;
    end
    task automatic uwrite(input [31:0] a, input [31:0] d);
        begin
            rxn = 0; ubyte(8'h57);
            ubyte(a[31:24]); ubyte(a[23:16]); ubyte(a[15:8]); ubyte(a[7:0]);
            ubyte(d[31:24]); ubyte(d[23:16]); ubyte(d[15:8]); ubyte(d[7:0]);
            wait (rxn >= 1); #1000;
            if (rxq[0] !== 8'h4B) begin $display("FAIL: write ack %h", rxq[0]); errors++; end
        end
    endtask
    task automatic uread(input [31:0] a, output [31:0] d);
        begin
            rxn = 0; ubyte(8'h52);
            ubyte(a[31:24]); ubyte(a[23:16]); ubyte(a[15:8]); ubyte(a[7:0]);
            wait (rxn >= 4); #1000;
            d = {rxq[0], rxq[1], rxq[2], rxq[3]};
        end
    endtask

    task automatic check(input bit c, input string m);
        begin if (c) $display("PASS: %s", m); else begin $display("FAIL: %s", m); errors++; end end
    endtask

    // ---------------- DUT ----------------
    wire [31:0] awaddr, wdata, araddr, rdata;
    wire awvalid, awready, wvalid, wready, bvalid, bready, arvalid, arready, rvalid, rready;
    wire [3:0] wstrb; wire [1:0] bresp, rresp;
    uart_axil_bridge #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_br (
        .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx_to_dut), .uart_tx(uart_tx_from_dut),
        .m_awaddr(awaddr), .m_awvalid(awvalid), .m_awready(awready), .m_wdata(wdata), .m_wstrb(wstrb),
        .m_wvalid(wvalid), .m_wready(wready), .m_bresp(bresp), .m_bvalid(bvalid), .m_bready(bready),
        .m_araddr(araddr), .m_arvalid(arvalid), .m_arready(arready), .m_rdata(rdata), .m_rresp(rresp),
        .m_rvalid(rvalid), .m_rready(rready));

    logic ctrl_enable, soft_reset;
    logic [1:0] g10_mode; logic [3:0] g10_dp_en, g10_aes_en, g10_gen_en; logic [15:0] g10_gap;
    logic g10_gen_to_dp, g10_inj_mac; logic [3:0] g10_inj_start, g10_tx_dis; logic [7:0] g10_rs; logic g10_gt_reset;
    logic [127:0] aes_key; logic [511:0] pats;
    logic [1:0] cu_mode, cu_aes_en; logic cu_gen_start;
    logic mdio_go, mdio_we, mdio_port; logic [4:0] mdio_reg, mdio_phy; logic [15:0] mdio_wdata;
    logic [4:0] dly_tap_a, dly_tap_b; logic dly_load_a, dly_load_b, phy_rst_force, phy_auto_en;
    logic [7:0] s10_idx, s1g_idx; logic s10_snap, s10_clr, s1g_snap, s1g_clr;
    wire [31:0] s10_val, s1g_val; wire s10_done, s1g_done;
    logic [127:0] zero128 = '0;

    // phy A
    wire [15:0] a_rdata; wire a_busy, a_done, a_init, a_link; wire [15:0] a_id;
    wire mdc, mdio_o, mdio_t; wire mdio_line;
    wire mdio_i = mdio_line;

    netsec_regs_k7 #(.N10(8), .N1G(8)) u_regs (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(awaddr[11:0]), .s_awvalid(awvalid), .s_awready(awready),
        .s_wdata(wdata), .s_wstrb(wstrb), .s_wvalid(wvalid), .s_wready(wready),
        .s_bresp(bresp), .s_bvalid(bvalid), .s_bready(bready),
        .s_araddr(araddr[11:0]), .s_arvalid(arvalid), .s_arready(arready),
        .s_rdata(rdata), .s_rresp(rresp), .s_rvalid(rvalid), .s_rready(rready),
        .ctrl_enable(ctrl_enable), .soft_reset(soft_reset), .status_in(16'hA5A5), .uptime_s(32'd7),
        .g10_mode(g10_mode), .g10_dp_en(g10_dp_en), .g10_aes_en(g10_aes_en), .g10_gen_en(g10_gen_en),
        .g10_gap(g10_gap), .g10_gen_to_dp(g10_gen_to_dp), .g10_inj_mac(g10_inj_mac),
        .g10_inj_start(g10_inj_start), .g10_tx_dis(g10_tx_dis), .g10_rs(g10_rs), .g10_gt_reset(g10_gt_reset),
        .aes_key(aes_key), .pats(pats), .g10_status_in(16'h0F0F), .g10_last_in(8'h1B), .g10_aes_done_in(4'b0100),
        .g10_aes_ct_in({128'h3333_3333_3333_3333_3333_3333_3333_3333, 128'h2222_2222_2222_2222_2222_2222_2222_2222,
                        128'h1111_1111_1111_1111_1111_1111_1111_1111, 128'h0001_0203_0405_0607_0809_0a0b_0c0d_0e0f}),
        .cu_mode(cu_mode), .cu_aes_en(cu_aes_en), .cu_gen_start(cu_gen_start), .cu_status_in(16'h0003),
        .cu_last_in(4'h5), .cu_aes_ct_in({128'hBBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB, 128'hAAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA}),
        .cu_aes_done_in(2'b00),
        .mdio_go(mdio_go), .mdio_we(mdio_we), .mdio_port(mdio_port), .mdio_reg(mdio_reg), .mdio_phy(mdio_phy),
        .mdio_wdata(mdio_wdata), .mdio_rdata_in(a_rdata), .mdio_busy_in(a_busy), .mdio_done_in(a_done),
        .dly_tap_a(dly_tap_a), .dly_tap_b(dly_tap_b), .dly_load_a(dly_load_a), .dly_load_b(dly_load_b),
        .phy_rst_force(phy_rst_force), .phy_auto_en(phy_auto_en),
        .phy_status_in({14'd0, a_link, a_init}), .phy_id_a_in(a_id), .phy_id_b_in(16'h0000),
        .s10_idx(s10_idx), .s10_snap(s10_snap), .s10_clr(s10_clr), .s10_val(s10_val), .s10_done(s10_done),
        .s1g_idx(s1g_idx), .s1g_snap(s1g_snap), .s1g_clr(s1g_clr), .s1g_val(s1g_val), .s1g_done(s1g_done));

    // stat bank on a *different* clock to exercise the CDC handshake
    logic clk_b = 0; always #3.2 clk_b = ~clk_b;
    logic [7:0] pulses = 0;
    stat_bank #(.N(8)) u_s10 (.src_clk(clk_b), .src_rst_n(rst_n), .pulse(pulses), .ctl_clk(clk), .ctl_rst_n(rst_n),
        .idx(s10_idx), .snap_req(s10_snap), .clr_req(s10_clr), .val(s10_val), .done(s10_done));
    stat_bank #(.N(8)) u_s1g (.src_clk(clk), .src_rst_n(rst_n), .pulse(8'd0), .ctl_clk(clk), .ctl_rst_n(rst_n),
        .idx(s1g_idx), .snap_req(s1g_snap), .clr_req(s1g_clr), .val(s1g_val), .done(s1g_done));

    // ---------------- phy_mgmt + MDIO PHY model ----------------
    logic phy_rel = 0;
    // MDC_HALF=4 at 11.0592 MHz gives a 724 ns MDC period, so the 150 ns PHY
    // output delay below is still sampled by the 2-flop synchronizer.
    phy_mgmt #(.PHY_ADDR(5'd2), .CLK_HZ(CLK_HZ), .SETTLE_MS(1), .POLL_MS(1), .MDC_HALF(4)) u_phy (
        .clk(clk), .rst_n(rst_n), .phy_rst_released(phy_rel), .auto_en(phy_auto_en),
        .h_go(mdio_go && !mdio_port), .h_we(mdio_we), .h_phy(mdio_phy), .h_reg(mdio_reg), .h_wdata(mdio_wdata),
        .h_rdata(a_rdata), .h_busy(a_busy), .h_done(a_done), .init_done(a_init), .phy_id1(a_id), .link_up(a_link),
        .mdc(mdc), .mdio_o(mdio_o), .mdio_t(mdio_t), .mdio_i(mdio_i));

    // Open-drain MDIO bus with a behavioural PHY at address 2.
    logic phy_drive_en, phy_drive_val;
    assign mdio_line = (!mdio_t ? mdio_o : 1'bz);
    assign mdio_line = phy_drive_en ? phy_drive_val : 1'bz;
    pullup (mdio_line);
    logic [15:0] preg [0:31];          // page-0 registers
    logic [15:0] p_d08_11, p_d08_15;   // page 0xD08 regs
    logic [15:0] page;
    initial begin
        integer q; for (q = 0; q < 32; q = q + 1) preg[q] = 16'h0000;
        preg[2] = 16'h001C; preg[3] = 16'hC916; preg[1] = 16'h7969; page = 16'h0000;
        p_d08_11 = 16'h0000; p_d08_15 = 16'h0000; phy_drive_en = 0; phy_drive_val = 0;
    end
    // Capture on the rising edge (what a real PHY does). Drive the reply 150 ns
    // later — RTL8211F's read-data delay is up to 300 ns, which used to exceed
    // the old master's half-cycle sample point.
    logic [63:0] sh; integer bitn; logic active;
    logic [15:0] rd_shift; logic is_read; logic [4:0] f_phy, f_reg;
    initial begin bitn = 0; active = 0; is_read = 0; sh = 64'd0; end
    always @(posedge mdc) begin : mdio_model
        logic en; logic val;
        sh = {sh[62:0], mdio_line};
        if (!active) begin
            if (sh[33:0] === {32'hFFFF_FFFF, 2'b01}) begin active = 1; bitn = 0; sh = 64'd0; end
        end else begin
            bitn = bitn + 1;
            if (bitn == 12) begin is_read = (sh[11:10] == 2'b10); f_phy = sh[9:5]; f_reg = sh[4:0]; end
            if (bitn == 30) begin
                if (!is_read && f_phy == 5'd2) begin
                    if (f_reg == 5'd31) page = sh[15:0];
                    else if (page == 16'h0D08 && f_reg == 5'd17) p_d08_11 = sh[15:0];
                    else if (page == 16'h0D08 && f_reg == 5'd21) p_d08_15 = sh[15:0];
                    else preg[f_reg] = sh[15:0];
                end
                active = 0;
            end
        end
        en = 1'b0; val = 1'b0;
        if (active && is_read && f_phy == 5'd2) begin
            if (bitn == 13) begin
                en = 1'b1; val = 1'b0;                                    // TA bit 2
                if (page == 16'h0D08 && f_reg == 5'd17)      rd_shift = p_d08_11;
                else if (page == 16'h0D08 && f_reg == 5'd21) rd_shift = p_d08_15;
                else                                         rd_shift = preg[f_reg];
            end else if (bitn >= 14 && bitn < 30) begin
                en = 1'b1; val = rd_shift[15 - (bitn - 14)];
            end
        end
        fork
            begin
                #150;
                phy_drive_en = en;
                phy_drive_val = val;
            end
        join_none
    end

    // ---------------- stimulus ----------------
    logic [31:0] v;
    initial begin
        repeat (20) @(posedge clk); rst_n = 1; repeat (20) @(posedge clk);
        uread(32'h000, v);   check(v == 32'h4B37_3235, "UART read ID = 'K725'");
        uwrite(32'h00C, 32'hDEADBEEF); uread(32'h00C, v); check(v == 32'hDEADBEEF, "scratch write/read via UART");
        uread(32'h010, v);   check(v == 32'h0000_A5A5, "STATUS passthrough");
        uwrite(32'h100, 32'd2); uread(32'h100, v); check(v == 2 && g10_mode == 2'd2, "G10_MODE = LOOP");
        uwrite(32'h104, 32'h5); check(g10_dp_en == 4'h5, "G10_DP_EN");
        uwrite(32'h130, 32'h0001_0203); uwrite(32'h134, 32'h0405_0607); uwrite(32'h138, 32'h0809_0A0B); uwrite(32'h13C, 32'h0C0D_0E0F);
        check(aes_key == 128'h000102030405060708090A0B0C0D0E0F, "AES key words (W0 = MSW)");
        uwrite(32'h148, 32'hCAFEF00D); check(pats[95:64] == 32'hCAFEF00D, "DPI pattern 2 (0x148)");
        uwrite(32'h17C, 32'h11223344); check(pats[511:480] == 32'h11223344, "DPI pattern 15 (0x17C)");
        uread(32'h140, v);   check(v == 32'h47455420, "default pattern0 = 'GET '");
        uread(32'h120, v);   check(v == 32'h0000_0F0F, "G10 status passthrough");
        uread(32'h190, v);   check(v == 32'h1111_1111, "10G AES ct port1 word0 (0x190)");
        uread(32'h180, v);   check(v == 32'h0001_0203, "10G AES ct port0 word0 (0x180, MSW first)");
        uread(32'h128, v);   check(v[3:0] == 4'b0100, "G10_AES_DONE sticky");
        uwrite(32'h128, 32'h4); uread(32'h128, v); check(v[3:0] == 4'b0100, "sticky re-set by the still-asserted input (expected)");
        uread(32'h250, v);   check(v == 32'hBBBB_BBBB, "copper AES ct port B word0 (0x250)");

        // MMIO AES: FIPS-197 appendix C.1 (key 000102..0f, pt 00112233..ff)
        uwrite(32'h310, 32'h0011_2233); uwrite(32'h314, 32'h4455_6677); uwrite(32'h318, 32'h8899_AABB); uwrite(32'h31C, 32'hCCDD_EEFF);
        uwrite(32'h300, 32'h1);
        repeat (3000) @(posedge clk);
        uread(32'h300, v);   check(v[0] == 1'b1, "AES done flag");
        uread(32'h320, v);   check(v == 32'h69C4_E0D8, "AES ct word0 = 69c4e0d8");
        uread(32'h32C, v);   check(v == 32'h70B4_C55A, "AES ct word3 = 70b4c55a (FIPS-197 C.1: 69c4e0d86a7b0430d8cdb78070b4c55a)");

        // checksum: words 0x4500 0x0073 0x0000 0x4000 0x4011 0xB861 0xC0A8 0x0001 0xC0A8 0x00C7 -> 0x0000 (valid hdr incl csum)
        uwrite(32'h300, 32'h2);
        uwrite(32'h330, 32'h4500); uwrite(32'h330, 32'h0073); uwrite(32'h330, 32'h0000); uwrite(32'h330, 32'h4000);
        uwrite(32'h330, 32'h4011); uwrite(32'h330, 32'h0000); uwrite(32'h330, 32'hC0A8); uwrite(32'h330, 32'h0001);
        uwrite(32'h330, 32'hC0A8); uwrite(32'h330, 32'h1_00C7);
        repeat (50) @(posedge clk);
        uread(32'h334, v);   check(v[15:0] == 16'hB861, "RFC1071 checksum of the textbook IPv4 header = B861");

        // modexp 7^13 mod 101 = 75
        uwrite(32'h340, 32'd7); uwrite(32'h344, 32'd13); uwrite(32'h348, 32'd101); uwrite(32'h300, 32'h4);
        repeat (4000) @(posedge clk);
        uread(32'h34C, v); check(v == 32'd75, "modexp 7^13 mod 101 = 75");

        // stat bank (cross-clock): 5 pulses on counter 3, 2 on counter 0
        repeat (3) begin @(posedge clk_b); pulses[3] <= 1; @(posedge clk_b); pulses[3] <= 0; end
        repeat (2) begin @(posedge clk_b); pulses[3] <= 1; @(posedge clk_b); pulses[3] <= 0; end
        repeat (2) begin @(posedge clk_b); pulses[0] <= 1; @(posedge clk_b); pulses[0] <= 0; end
        repeat (4) @(posedge clk_b);
        uwrite(32'h400, 32'd3); repeat (400) @(posedge clk); uread(32'h404, v); check(v == 5, "stat bank idx3 = 5");
        uwrite(32'h400, 32'd0); repeat (400) @(posedge clk); uread(32'h404, v); check(v == 2, "stat bank idx0 = 2");
        uread(32'h40C, v);   check(v == 8, "stat bank N");
        uwrite(32'h408, 32'd1); repeat (400) @(posedge clk);
        uwrite(32'h400, 32'd3); repeat (400) @(posedge clk); uread(32'h404, v); check(v == 0, "stat bank cleared");

        // ping
        rxn = 0; ubyte(8'h50); wait (rxn >= 1); #1000; check(rxq[0] == 8'h70, "UART ping");

        // PHY auto init: release the PHY reset, wait settle + init
        phy_rel = 1;
        wait (a_init);
        repeat (2000) @(posedge clk);
        check(a_id == 16'h001C, "phy_mgmt read PHYID1 = 0x001C");
        check(p_d08_11[8] == 1'b1, "phy_mgmt set TXDLY (page D08 reg 0x11 b8)");
        check(p_d08_15[3] == 1'b1, "phy_mgmt set RXDLY (page D08 reg 0x15 b3)");
        check(page == 16'h0000, "phy_mgmt restored page 0");
        preg[1] = 16'h796D;   // link up
        repeat (40000) @(posedge clk);
        check(a_link == 1'b1, "phy_mgmt link poll sees BMSR link bit");
        // host MDIO read of PHYID2 through the register file
        uwrite(32'h214, 32'h0000_0203);                 // phy ovr value 2, reg 3
        uwrite(32'h210, 32'h0000_0009);                 // go, we=0, phy override
        repeat (3000) @(posedge clk);
        uread(32'h21C, v);   check(v[15:0] == 16'hC916, "host MDIO read PHYID2 via regs = 0xC916");

        if (errors == 0) $display("PASS: tb_ctrl"); else $display("FAIL: tb_ctrl errors=%0d", errors);
        $finish;
    end
    initial begin #800_000_000; $display("FAIL: tb_ctrl timeout"); $finish; end
endmodule
