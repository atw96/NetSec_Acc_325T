// netsec_k7_top.sv — NetSec accelerator on the MiLianKe MK7325FB (XC7K325T-2FFG900I)
//   4 x SFP+ 10GBASE-R (GTX Quad 118)   -> netsec_fabric10g (inline / loop / BIST, dp64 inspection)
//   2 x RJ45 RTL8211FD RGMII             -> netsec_fabric1g  (bounce / bridge / L0, byte datapath)
//   control: JTAG-to-AXI (Vivado hw_axi) and CP2104 UART bridge -> netsec_regs_k7
// Clock domains: clk125 (control, RGMII logic, DCLK) | clk156 (10G, from PCS/PMA) | rgmii rxc (inside MAC FIFOs)
`timescale 1ns / 1ps
module netsec_k7_top #(
    parameter integer ENABLE_10G   = 1,
    parameter integer HASH_BITS    = 10,
    parameter integer AES_LANES    = 1,
    parameter integer AES_PIPE     = 1,         // 1: pipelined AES (~10k LUT/lane), 0: iterative core (~0.7k LUT, relieves timing/area)
    parameter integer ROM_PATTERNS = 160,
    parameter integer FIFO_BYTES   = 65536,
    parameter integer DLY          = 480,
    parameter integer RXFIFO_BYTES = 8192,
    parameter         USE_CLK90_A  = "FALSE",   // "FALSE": PHY inserts the 2 ns TXC delay (phy_mgmt enables it)
    parameter         USE_CLK90_B  = "FALSE",
    parameter integer PHY_AUTO_DLY = 1,         // phy_mgmt writes TXDLY/RXDLY into the PHYs after reset
    parameter integer LED_ACTIVE_HIGH = 1,
    parameter [4:0]   PHYADDR_A    = 5'd2,
    parameter [4:0]   PHYADDR_B    = 5'd1,
    parameter [4:0]   RX_DLY_A     = 5'd0,      // IDELAY tap baked in for flash boot (NETSEC_RX_DLY_A)
    parameter [4:0]   RX_DLY_B     = 5'd0
) (
    input  wire        sys_clk_100m,          // AD12
    input  wire        rst_btn_n,             // BUT2, active low

    input  wire        uart_rxd,              // FPGA receives (from CP2104)
    output wire        uart_txd,              // FPGA transmits (to CP2104)

    output wire [2:0]  led_base,
    output wire [2:0]  led_core,

    // 10G
    input  wire        mgt_refclk_p,          // MGTREFCLK1_118  (CDCM61002 @ 156.25 MHz)
    input  wire        mgt_refclk_n,
    output wire [3:0]  sfp_txp,
    output wire [3:0]  sfp_txn,
    input  wire [3:0]  sfp_rxp,
    input  wire [3:0]  sfp_rxn,
    output wire [3:0]  sfp_tx_dis,
    output wire [3:0]  sfp_rs0,
    output wire [3:0]  sfp_rs1,

    // RGMII A (ETHA, PHY addr 2)
    input  wire        eth_a_rxc,
    input  wire [3:0]  eth_a_rxd,
    input  wire        eth_a_rx_ctl,
    output wire        eth_a_txc,
    output wire [3:0]  eth_a_txd,
    output wire        eth_a_tx_ctl,
    output wire        eth_a_mdc,
    inout  wire        eth_a_mdio,
    // RGMII B (ETHB, PHY addr 1)
    input  wire        eth_b_rxc,
    input  wire [3:0]  eth_b_rxd,
    input  wire        eth_b_rx_ctl,
    output wire        eth_b_txc,
    output wire [3:0]  eth_b_txd,
    output wire        eth_b_tx_ctl,
    output wire        eth_b_mdc,
    inout  wire        eth_b_mdio,
    output wire        eth_rst_n              // shared PHY reset (active low)
);
    // =====================================================================
    // clocks: 100 MHz -> MMCM -> 125 / 125@90 / 200
    // =====================================================================
    wire sys_ibuf;
    IBUF u_sys_ibuf (.I(sys_clk_100m), .O(sys_ibuf));

    wire mmcm_fb, mmcm_locked, c125_u, c125_90_u, c200_u;
    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"), .CLKIN1_PERIOD(10.0), .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT_F(10.0),
        .CLKOUT0_DIVIDE_F(8.0), .CLKOUT0_PHASE(0.0),
        .CLKOUT1_DIVIDE(8),     .CLKOUT1_PHASE(90.0),
        .CLKOUT2_DIVIDE(5),     .CLKOUT2_PHASE(0.0)
    ) u_mmcm (
        .CLKIN1(sys_ibuf), .CLKFBIN(mmcm_fb), .CLKFBOUT(mmcm_fb), .CLKFBOUTB(),
        .CLKOUT0(c125_u), .CLKOUT0B(), .CLKOUT1(c125_90_u), .CLKOUT1B(),
        .CLKOUT2(c200_u), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .LOCKED(mmcm_locked), .PWRDWN(1'b0), .RST(1'b0)
    );
    wire clk125, clk125_90, clk200;
    BUFG u_bg0 (.I(c125_u),    .O(clk125));
    BUFG u_bg1 (.I(c125_90_u), .O(clk125_90));
    BUFG u_bg2 (.I(c200_u),    .O(clk200));

    // =====================================================================
    // reset
    // =====================================================================
    reg [1:0] btn_s;
    always @(posedge clk125) btn_s <= {btn_s[0], rst_btn_n};
    reg [19:0] por_cnt;
    always @(posedge clk125 or negedge mmcm_locked) begin
        if (!mmcm_locked) por_cnt <= 20'd0;
        else if (!(&por_cnt)) por_cnt <= por_cnt + 1'b1;
    end
    wire por_done = &por_cnt;

    wire soft_reset_pulse;
    reg [4:0] soft_stretch;
    always @(posedge clk125 or negedge mmcm_locked) begin
        if (!mmcm_locked) soft_stretch <= 5'd0;
        else if (soft_reset_pulse) soft_stretch <= 5'd31;
        else if (soft_stretch != 0) soft_stretch <= soft_stretch - 1'b1;
    end
    wire ctl_rst_n_raw = por_done & btn_s[1] & (soft_stretch == 0);
    wire ctl_rst_n;
    u_reset_sync u_rs_ctl (.clk(clk125), .async_rst_n(ctl_rst_n_raw), .sync_rst_n(ctl_rst_n));
    wire rst125 = ~ctl_rst_n;

    wire idc_rdy;
    (* IODELAY_GROUP = "k7_rgmii_dly" *)
    IDELAYCTRL u_idc (.REFCLK(clk200), .RST(~mmcm_locked), .RDY(idc_rdy));

    // seconds counter
    reg [26:0] sec_div; reg [31:0] uptime_s;
    always @(posedge clk125 or negedge ctl_rst_n) begin
        if (!ctl_rst_n) begin sec_div <= 27'd0; uptime_s <= 32'd0; end
        else if (sec_div == 27'd124_999_999) begin sec_div <= 27'd0; uptime_s <= uptime_s + 1'b1; end
        else sec_div <= sec_div + 1'b1;
    end

    // =====================================================================
    // control plane: JTAG-AXI + UART -> arbiter -> register file
    // =====================================================================
    wire [31:0] j_awaddr, j_wdata, j_araddr, j_rdata;
    wire [3:0]  j_wstrb; wire [1:0] j_bresp, j_rresp; wire [2:0] j_awprot, j_arprot;
    wire j_awvalid, j_awready, j_wvalid, j_wready, j_bvalid, j_bready, j_arvalid, j_arready, j_rvalid, j_rready;
    jtag_axi_0 u_jtag (
        .aclk(clk125), .aresetn(ctl_rst_n),
        .m_axi_awaddr(j_awaddr), .m_axi_awprot(j_awprot), .m_axi_awvalid(j_awvalid), .m_axi_awready(j_awready),
        .m_axi_wdata(j_wdata), .m_axi_wstrb(j_wstrb), .m_axi_wvalid(j_wvalid), .m_axi_wready(j_wready),
        .m_axi_bresp(j_bresp), .m_axi_bvalid(j_bvalid), .m_axi_bready(j_bready),
        .m_axi_araddr(j_araddr), .m_axi_arprot(j_arprot), .m_axi_arvalid(j_arvalid), .m_axi_arready(j_arready),
        .m_axi_rdata(j_rdata), .m_axi_rresp(j_rresp), .m_axi_rvalid(j_rvalid), .m_axi_rready(j_rready)
    );

    wire [31:0] u_awaddr, u_wdata, u_araddr, u_rdata; wire [3:0] u_wstrb; wire [1:0] u_bresp, u_rresp;
    wire u_awvalid, u_awready, u_wvalid, u_wready, u_bvalid, u_bready, u_arvalid, u_arready, u_rvalid, u_rready;
    uart_axil_bridge #(.CLK_HZ(125_000_000), .BAUD(115200)) u_uart (
        .clk(clk125), .rst_n(ctl_rst_n), .uart_rx(uart_rxd), .uart_tx(uart_txd),
        .m_awaddr(u_awaddr), .m_awvalid(u_awvalid), .m_awready(u_awready), .m_wdata(u_wdata), .m_wstrb(u_wstrb),
        .m_wvalid(u_wvalid), .m_wready(u_wready), .m_bresp(u_bresp), .m_bvalid(u_bvalid), .m_bready(u_bready),
        .m_araddr(u_araddr), .m_arvalid(u_arvalid), .m_arready(u_arready), .m_rdata(u_rdata), .m_rresp(u_rresp),
        .m_rvalid(u_rvalid), .m_rready(u_rready)
    );

    wire [31:0] a_awaddr, a_wdata, a_araddr, a_rdata; wire [3:0] a_wstrb; wire [1:0] a_bresp, a_rresp;
    wire a_awvalid, a_awready, a_wvalid, a_wready, a_bvalid, a_bready, a_arvalid, a_arready, a_rvalid, a_rready;
    axil_arb2 u_arb (
        .clk(clk125), .rst_n(ctl_rst_n),
        .m0_awaddr(j_awaddr), .m0_awvalid(j_awvalid), .m0_awready(j_awready), .m0_wdata(j_wdata), .m0_wstrb(j_wstrb),
        .m0_wvalid(j_wvalid), .m0_wready(j_wready), .m0_bresp(j_bresp), .m0_bvalid(j_bvalid), .m0_bready(j_bready),
        .m0_araddr(j_araddr), .m0_arvalid(j_arvalid), .m0_arready(j_arready), .m0_rdata(j_rdata), .m0_rresp(j_rresp),
        .m0_rvalid(j_rvalid), .m0_rready(j_rready),
        .m1_awaddr(u_awaddr), .m1_awvalid(u_awvalid), .m1_awready(u_awready), .m1_wdata(u_wdata), .m1_wstrb(u_wstrb),
        .m1_wvalid(u_wvalid), .m1_wready(u_wready), .m1_bresp(u_bresp), .m1_bvalid(u_bvalid), .m1_bready(u_bready),
        .m1_araddr(u_araddr), .m1_arvalid(u_arvalid), .m1_arready(u_arready), .m1_rdata(u_rdata), .m1_rresp(u_rresp),
        .m1_rvalid(u_rvalid), .m1_rready(u_rready),
        .s_awaddr(a_awaddr), .s_awvalid(a_awvalid), .s_awready(a_awready), .s_wdata(a_wdata), .s_wstrb(a_wstrb),
        .s_wvalid(a_wvalid), .s_wready(a_wready), .s_bresp(a_bresp), .s_bvalid(a_bvalid), .s_bready(a_bready),
        .s_araddr(a_araddr), .s_arvalid(a_arvalid), .s_arready(a_arready), .s_rdata(a_rdata), .s_rresp(a_rresp),
        .s_rvalid(a_rvalid), .s_rready(a_rready)
    );

    // ---- register file ----
    wire        ctrl_enable;
    wire [1:0]  g10_mode;        wire [3:0] g10_dp_en, g10_aes_en, g10_gen_en;
    wire [15:0] g10_gap;         wire g10_gen_to_dp, g10_inj_mac;
    wire [3:0]  g10_inj_start, g10_tx_dis;  wire [7:0] g10_rs;  wire g10_gt_reset;
    wire [127:0] aes_key;        wire [511:0] pats;
    wire [1:0]  cu_mode, cu_aes_en;  wire cu_gen_start;
    wire        mdio_go, mdio_we, mdio_port;  wire [4:0] mdio_reg, mdio_phy;  wire [15:0] mdio_wdata;
    wire [4:0]  dly_tap_a, dly_tap_b;  wire dly_load_a, dly_load_b, phy_rst_force, phy_auto_en;
    wire [7:0]  s10_idx, s1g_idx;  wire s10_snap, s10_clr, s1g_snap, s1g_clr;
    wire [31:0] s10_val, s1g_val;  wire s10_done, s1g_done;

    // status from other domains (declared here, driven below)
    wire [15:0] status_w, g10_status_w, cu_status_w, phy_status_w;
    wire [7:0]  g10_last_w;  wire [3:0] g10_aes_done_w;  wire [511:0] g10_aes_ct_w;
    wire [3:0]  cu_last_w;   wire [255:0] cu_aes_ct_w;   wire [1:0] cu_aes_done_w;
    wire [15:0] mdio_rdata_a, mdio_rdata_b, phy_id_a, phy_id_b;
    wire        mdio_busy_a, mdio_done_a, mdio_busy_b, mdio_done_b;

    netsec_regs_k7 #(
        .CONFIG_W({12'd0, AES_LANES[3:0], HASH_BITS[7:0], 4'd2, ENABLE_10G ? 4'd4 : 4'd0}),
        .N10(128), .N1G(32), .PHYADDR_A(PHYADDR_A), .PHYADDR_B(PHYADDR_B),
        .DLY_A_INIT(RX_DLY_A), .DLY_B_INIT(RX_DLY_B)
    ) u_regs (
        .clk(clk125), .rst_n(ctl_rst_n),
        .s_awaddr(a_awaddr[11:0]), .s_awvalid(a_awvalid), .s_awready(a_awready),
        .s_wdata(a_wdata), .s_wstrb(a_wstrb), .s_wvalid(a_wvalid), .s_wready(a_wready),
        .s_bresp(a_bresp), .s_bvalid(a_bvalid), .s_bready(a_bready),
        .s_araddr(a_araddr[11:0]), .s_arvalid(a_arvalid), .s_arready(a_arready),
        .s_rdata(a_rdata), .s_rresp(a_rresp), .s_rvalid(a_rvalid), .s_rready(a_rready),
        .ctrl_enable(ctrl_enable), .soft_reset(soft_reset_pulse), .status_in(status_w), .uptime_s(uptime_s),
        .g10_mode(g10_mode), .g10_dp_en(g10_dp_en), .g10_aes_en(g10_aes_en), .g10_gen_en(g10_gen_en),
        .g10_gap(g10_gap), .g10_gen_to_dp(g10_gen_to_dp), .g10_inj_mac(g10_inj_mac),
        .g10_inj_start(g10_inj_start), .g10_tx_dis(g10_tx_dis), .g10_rs(g10_rs), .g10_gt_reset(g10_gt_reset),
        .aes_key(aes_key), .pats(pats), .g10_status_in(g10_status_w), .g10_last_in(g10_last_w),
        .g10_aes_done_in(g10_aes_done_w), .g10_aes_ct_in(g10_aes_ct_w),
        .cu_mode(cu_mode), .cu_aes_en(cu_aes_en), .cu_gen_start(cu_gen_start), .cu_status_in(cu_status_w),
        .cu_last_in(cu_last_w), .cu_aes_ct_in(cu_aes_ct_w), .cu_aes_done_in(cu_aes_done_w),
        .mdio_go(mdio_go), .mdio_we(mdio_we), .mdio_port(mdio_port), .mdio_reg(mdio_reg), .mdio_phy(mdio_phy),
        .mdio_wdata(mdio_wdata),
        .mdio_rdata_in(mdio_port ? mdio_rdata_b : mdio_rdata_a),
        .mdio_busy_in(mdio_port ? mdio_busy_b : mdio_busy_a),
        .mdio_done_in(mdio_port ? mdio_done_b : mdio_done_a),
        .dly_tap_a(dly_tap_a), .dly_tap_b(dly_tap_b), .dly_load_a(dly_load_a), .dly_load_b(dly_load_b),
        .phy_rst_force(phy_rst_force), .phy_auto_en(phy_auto_en),
        .phy_status_in(phy_status_w), .phy_id_a_in(phy_id_a), .phy_id_b_in(phy_id_b),
        .s10_idx(s10_idx), .s10_snap(s10_snap), .s10_clr(s10_clr), .s10_val(s10_val), .s10_done(s10_done),
        .s1g_idx(s1g_idx), .s1g_snap(s1g_snap), .s1g_clr(s1g_clr), .s1g_val(s1g_val), .s1g_done(s1g_done)
    );

    // =====================================================================
    // PHY reset + MDIO management (2x)
    // =====================================================================
    reg [21:0] phy_rst_cnt;
    reg        phy_run;
    always @(posedge clk125 or negedge ctl_rst_n) begin
        if (!ctl_rst_n) begin phy_rst_cnt <= 22'd0; phy_run <= 1'b0; end
        else if (phy_rst_force) begin phy_rst_cnt <= 22'd0; phy_run <= 1'b0; end
        else if (!phy_run) begin
            phy_rst_cnt <= phy_rst_cnt + 1'b1;
            if (phy_rst_cnt == 22'd2_500_000) phy_run <= 1'b1;      // 20 ms low
        end
    end
    assign eth_rst_n = phy_run;

    (* mark_debug = "true" *) wire mdc_a, mdio_t_a, mdio_i_a;
    wire mdio_o_a, mdc_b, mdio_o_b, mdio_t_b, mdio_i_b;
    wire link_a, link_b, init_a, init_b;
    IOBUF u_iob_a (.I(mdio_o_a), .O(mdio_i_a), .T(mdio_t_a), .IO(eth_a_mdio));
    IOBUF u_iob_b (.I(mdio_o_b), .O(mdio_i_b), .T(mdio_t_b), .IO(eth_b_mdio));
    assign eth_a_mdc = mdc_a;
    assign eth_b_mdc = mdc_b;

    phy_mgmt #(.PHY_ADDR(PHYADDR_A), .TXDLY_EN(USE_CLK90_A == "FALSE"), .RXDLY_EN(1), .MDC_HALF(50)) u_phy_a (
        .clk(clk125), .rst_n(ctl_rst_n), .phy_rst_released(phy_run), .auto_en(phy_auto_en && PHY_AUTO_DLY != 0),
        .h_go(mdio_go && !mdio_port), .h_we(mdio_we), .h_phy(mdio_phy), .h_reg(mdio_reg), .h_wdata(mdio_wdata),
        .h_rdata(mdio_rdata_a), .h_busy(mdio_busy_a), .h_done(mdio_done_a),
        .init_done(init_a), .phy_id1(phy_id_a), .link_up(link_a),
        .mdc(mdc_a), .mdio_o(mdio_o_a), .mdio_t(mdio_t_a), .mdio_i(mdio_i_a));
    phy_mgmt #(.PHY_ADDR(PHYADDR_B), .TXDLY_EN(USE_CLK90_B == "FALSE"), .RXDLY_EN(1), .MDC_HALF(50)) u_phy_b (
        .clk(clk125), .rst_n(ctl_rst_n), .phy_rst_released(phy_run), .auto_en(phy_auto_en && PHY_AUTO_DLY != 0),
        .h_go(mdio_go && mdio_port), .h_we(mdio_we), .h_phy(mdio_phy), .h_reg(mdio_reg), .h_wdata(mdio_wdata),
        .h_rdata(mdio_rdata_b), .h_busy(mdio_busy_b), .h_done(mdio_done_b),
        .init_done(init_b), .phy_id1(phy_id_b), .link_up(link_b),
        .mdc(mdc_b), .mdio_o(mdio_o_b), .mdio_t(mdio_t_b), .mdio_i(mdio_i_b));

    // =====================================================================
    // 1G copper: RGMII MACs + inspection fabric (clk125)
    // =====================================================================
    wire [7:0] cm_rx_d [0:1]; wire [1:0] cm_rx_v, cm_rx_l, cm_rx_u, cm_rx_r;
    wire [7:0] cm_tx_d [0:1]; wire [1:0] cm_tx_v, cm_tx_l, cm_tx_r;
    wire [1:0] sp_a, sp_b;
    wire [11:0] cm_pulse_a, cm_pulse_b;   // see counter map

    rgmii_mac_k7 #(.USE_CLK90(USE_CLK90_A), .DLY_INIT(RX_DLY_A)) u_mac_a (
        .clk125(clk125), .clk125_90(clk125_90), .rst(rst125),
        .tx_tdata(cm_tx_d[0]), .tx_tvalid(cm_tx_v[0]), .tx_tready(cm_tx_r[0]), .tx_tlast(cm_tx_l[0]), .tx_tuser(1'b0),
        .rx_tdata(cm_rx_d[0]), .rx_tvalid(cm_rx_v[0]), .rx_tready(cm_rx_r[0]), .rx_tlast(cm_rx_l[0]), .rx_tuser(cm_rx_u[0]),
        .rgmii_rxc(eth_a_rxc), .rgmii_rd(eth_a_rxd), .rgmii_rx_ctl(eth_a_rx_ctl),
        .rgmii_txc(eth_a_txc), .rgmii_td(eth_a_txd), .rgmii_tx_ctl(eth_a_tx_ctl),
        .dly_tap(dly_tap_a), .dly_load(dly_load_a), .speed(sp_a),
        .p_rx_bad_frame(cm_pulse_a[1]), .p_rx_bad_fcs(cm_pulse_a[2]), .p_rx_good(cm_pulse_a[0]),
        .p_rx_ovf(cm_pulse_a[3]), .p_tx_good(cm_pulse_a[4]), .p_tx_underflow(cm_pulse_a[5]));
    rgmii_mac_k7 #(.USE_CLK90(USE_CLK90_B), .DLY_INIT(RX_DLY_B)) u_mac_b (
        .clk125(clk125), .clk125_90(clk125_90), .rst(rst125),
        .tx_tdata(cm_tx_d[1]), .tx_tvalid(cm_tx_v[1]), .tx_tready(cm_tx_r[1]), .tx_tlast(cm_tx_l[1]), .tx_tuser(1'b0),
        .rx_tdata(cm_rx_d[1]), .rx_tvalid(cm_rx_v[1]), .rx_tready(cm_rx_r[1]), .rx_tlast(cm_rx_l[1]), .rx_tuser(cm_rx_u[1]),
        .rgmii_rxc(eth_b_rxc), .rgmii_rd(eth_b_rxd), .rgmii_rx_ctl(eth_b_rx_ctl),
        .rgmii_txc(eth_b_txc), .rgmii_td(eth_b_txd), .rgmii_tx_ctl(eth_b_tx_ctl),
        .dly_tap(dly_tap_b), .dly_load(dly_load_b), .speed(sp_b),
        .p_rx_bad_frame(cm_pulse_b[1]), .p_rx_bad_fcs(cm_pulse_b[2]), .p_rx_good(cm_pulse_b[0]),
        .p_rx_ovf(cm_pulse_b[3]), .p_tx_good(cm_pulse_b[4]), .p_tx_underflow(cm_pulse_b[5]));

    wire [1:0] f1_rx, f1_tx, f1_fwd, f1_drop, f1_mir, f1_dpi;
    netsec_fabric1g #(.FRAME_DEPTH(2048)) u_fab1g (
        .clk(clk125), .rst_n(ctl_rst_n), .enable(ctrl_enable), .mode(cu_mode), .aes_en(cu_aes_en),
        .aes_key(aes_key), .pats4(pats[127:0]), .gen_start(cu_gen_start),
        .rx_tdata({cm_rx_d[1], cm_rx_d[0]}), .rx_tvalid(cm_rx_v), .rx_tlast(cm_rx_l), .rx_tready(cm_rx_r),
        .tx_tdata({cm_tx_d[1], cm_tx_d[0]}), .tx_tvalid(cm_tx_v), .tx_tlast(cm_tx_l), .tx_tready(cm_tx_r),
        .p_rx(f1_rx), .p_tx(f1_tx), .p_fwd(f1_fwd), .p_drop(f1_drop), .p_mir(f1_mir), .p_dpi(f1_dpi),
        .last_action(cu_last_w), .aes_ct(cu_aes_ct_w), .aes_done(cu_aes_done_w)
    );
    assign cm_pulse_a[11:6] = {f1_dpi[0], f1_mir[0], f1_drop[0], f1_fwd[0], f1_tx[0], f1_rx[0]};
    assign cm_pulse_b[11:6] = {f1_dpi[1], f1_mir[1], f1_drop[1], f1_fwd[1], f1_tx[1], f1_rx[1]};

    // copper counter bank (control clock domain): index = port*16 + k,
    // k: 0 mac_rx_good 1 bad_frame 2 bad_fcs 3 rx_ovf 4 mac_tx_good 5 tx_underflow
    //    6 dp_rx 7 dp_tx 8 dp_fwd 9 dp_drop 10 dp_mir 11 dp_dpi
    wire [31:0] cu_pulses = {4'd0, cm_pulse_b, 4'd0, cm_pulse_a};
    stat_bank #(.N(32)) u_stat1g (
        .src_clk(clk125), .src_rst_n(ctl_rst_n), .pulse(cu_pulses),
        .ctl_clk(clk125), .ctl_rst_n(ctl_rst_n), .idx(s1g_idx), .snap_req(s1g_snap), .clr_req(s1g_clr),
        .val(s1g_val), .done(s1g_done));

    assign cu_status_w  = {10'd0, sp_b, sp_a, link_b, link_a};
    assign phy_status_w = {12'd0, init_b, init_a, link_b, link_a};

    // =====================================================================
    // 10G: PCS/PMA x4, MACs, fabric (clk156)
    // =====================================================================
    wire        clk156, rst156_n, qplllock;
    wire [3:0]  block_lock, core_status0, gt_resetdone;
    wire        any_bl;

    generate if (ENABLE_10G != 0) begin : g_10g
        // ---- GT reset request: reset / button / host request (stretched) ----
        reg [4:0] gtr_stretch;
        always @(posedge clk125 or negedge ctl_rst_n) begin
            if (!ctl_rst_n) gtr_stretch <= 5'd31;
            else if (g10_gt_reset) gtr_stretch <= 5'd31;
            else if (gtr_stretch != 0) gtr_stretch <= gtr_stretch - 1'b1;
        end
        wire gt_reset_in = (gtr_stretch != 0);

        wire [255:0] x_txd, x_rxd; wire [31:0] x_txc, x_rxc;
        gt10g_quad u_gt (
            .dclk(clk125), .reset_in(gt_reset_in), .refclk_p(mgt_refclk_p), .refclk_n(mgt_refclk_n),
            .txp(sfp_txp), .txn(sfp_txn), .rxp(sfp_rxp), .rxn(sfp_rxn),
            .clk156(clk156), .rst156_n(rst156_n),
            .xgmii_txd(x_txd), .xgmii_txc(x_txc), .xgmii_rxd(x_rxd), .xgmii_rxc(x_rxc),
            .qplllock(qplllock), .block_lock(block_lock), .core_status0(core_status0), .resetdone(gt_resetdone)
        );
        wire rst156 = ~rst156_n;

        // ---- MACs ----
        wire [255:0] m_rx_d; wire [31:0] m_rx_k; wire [3:0] m_rx_v, m_rx_l, m_rx_u;
        wire [255:0] m_tx_d; wire [31:0] m_tx_k; wire [3:0] m_tx_v, m_tx_l, m_tx_u, m_tx_r;
        wire [3:0] mac_underflow, mac_badfrm, mac_badfcs;
        genvar p;
        for (p = 0; p < 4; p = p + 1) begin : g_mac
            mac10g_port u_mac (
                .clk(clk156), .rst(rst156),
                .tx_tdata(m_tx_d[p*64 +: 64]), .tx_tkeep(m_tx_k[p*8 +: 8]), .tx_tvalid(m_tx_v[p]),
                .tx_tready(m_tx_r[p]), .tx_tlast(m_tx_l[p]), .tx_tuser(m_tx_u[p]),
                .rx_tdata(m_rx_d[p*64 +: 64]), .rx_tkeep(m_rx_k[p*8 +: 8]), .rx_tvalid(m_rx_v[p]),
                .rx_tlast(m_rx_l[p]), .rx_tuser(m_rx_u[p]),
                .xgmii_rxd(x_rxd[p*64 +: 64]), .xgmii_rxc(x_rxc[p*8 +: 8]),
                .xgmii_txd(x_txd[p*64 +: 64]), .xgmii_txc(x_txc[p*8 +: 8]),
                .st_tx_underflow(mac_underflow[p]), .st_rx_bad_frame(mac_badfrm[p]), .st_rx_bad_fcs(mac_badfcs[p]));
        end

        // ---- control into clk156 ----
        wire [1:0] c_mode; wire [3:0] c_dp, c_aes, c_gen; wire [15:0] c_gap; wire c_g2d, c_injmac;
        wire [127:0] c_key; wire [511:0] c_pats;
        netsec_level_cdc #(.WIDTH(2+4+4+4+16+1+1+128+512)) u_cdc_cfg (
            .src_clk(clk125),
            .src_level({pats, aes_key, g10_inj_mac, g10_gen_to_dp, g10_gap, g10_gen_en, g10_aes_en, g10_dp_en, g10_mode}),
            .dst_clk(clk156), .dst_rst_n(rst156_n),
            .dst_level({c_pats, c_key, c_injmac, c_g2d, c_gap, c_gen, c_aes, c_dp, c_mode}));
        wire [3:0] c_inj;
        genvar q;
        for (q = 0; q < 4; q = q + 1) begin : g_inj
            netsec_pulse_cdc u_p (.src_clk(clk125), .src_rst_n(ctl_rst_n), .src_pulse(g10_inj_start[q]),
                                  .dst_clk(clk156), .dst_rst_n(rst156_n), .dst_pulse(c_inj[q]));
        end

        // ---- fabric ----
        wire [255:0] f_tx_d; wire [31:0] f_tx_k; wire [3:0] f_tx_v, f_tx_l, f_tx_u;
        wire [7:0] f_last; wire [3:0] p_rxf_drop, p_rxf_ovf, p_rx, p_tx, p_fwd, p_drop, p_mir, p_dpi, p_csum, p_ovf, p_flow;
        wire [63:0] p_phit; wire [511:0] f_aes_ct; wire [3:0] f_aes_done, f_aes_fold;
        netsec_fabric10g #(.NP(4), .HASH_BITS(HASH_BITS), .ROM_PATTERNS(ROM_PATTERNS), .AES_PIPE(AES_PIPE),
                           .AES_LANES(AES_LANES), .FIFO_BYTES(FIFO_BYTES), .DLY(DLY), .RXFIFO_BYTES(RXFIFO_BYTES)) u_fab10 (
            .clk(clk156), .rst_n(rst156_n), .mode(c_mode), .dp_en(c_dp), .aes_en(c_aes), .gen_en(c_gen),
            .gen_to_dp(c_g2d), .inj_mac(c_injmac), .gap(c_gap), .inj_start(c_inj), .aes_key(c_key), .pats(c_pats),
            .rx_tdata(m_rx_d), .rx_tkeep(m_rx_k), .rx_tvalid(m_rx_v), .rx_tlast(m_rx_l), .rx_tuser(m_rx_u),
            .tx_tdata(m_tx_d), .tx_tkeep(m_tx_k), .tx_tvalid(m_tx_v), .tx_tready(m_tx_r), .tx_tlast(m_tx_l), .tx_tuser(m_tx_u),
            .last_action(f_last), .p_rxf_drop(p_rxf_drop), .p_rxf_ovf(p_rxf_ovf), .p_dp_rx(p_rx), .p_dp_tx(p_tx),
            .p_dp_fwd(p_fwd), .p_dp_drop(p_drop), .p_dp_mir(p_mir), .p_dp_dpi(p_dpi), .p_dp_csum(p_csum),
            .p_dp_ovf(p_ovf), .p_dp_flow(p_flow), .p_phit(p_phit),
            .aes_ct(f_aes_ct), .aes_done(f_aes_done), .aes_fold(f_aes_fold));

        // ---- counters (index = port*32 + k) ----
        wire [127:0] pulses10;
        for (p = 0; p < 4; p = p + 1) begin : g_pl
            assign pulses10[p*32 +: 32] = {
                p_phit[p*16 +: 16],
                p_flow[p], p_ovf[p], p_csum[p], p_dpi[p], p_mir[p], p_drop[p], p_fwd[p], p_tx[p], p_rx[p],
                p_rxf_ovf[p], p_rxf_drop[p],
                mac_underflow[p], (m_tx_v[p] & m_tx_r[p] & m_tx_l[p]),
                mac_badfrm[p], mac_badfcs[p], (m_rx_v[p] & m_rx_l[p]) };
        end
        stat_bank #(.N(128)) u_stat10 (
            .src_clk(clk156), .src_rst_n(rst156_n), .pulse(pulses10),
            .ctl_clk(clk125), .ctl_rst_n(ctl_rst_n), .idx(s10_idx), .snap_req(s10_snap), .clr_req(s10_clr),
            .val(s10_val), .done(s10_done));

        // ---- status back to clk125 ----
        wire [3:0] s_bl, s_cs, s_rd; wire s_ql, s_rstn; wire [7:0] s_last; wire [511:0] s_ct;
        netsec_level_cdc #(.WIDTH(4+4+4+1+1+8+512)) u_cdc_st (
            .src_clk(clk156), .src_level({f_aes_ct, f_last, rst156_n, qplllock, gt_resetdone, core_status0, block_lock}),
            .dst_clk(clk125), .dst_rst_n(ctl_rst_n),
            .dst_level({s_ct, s_last, s_rstn, s_ql, s_rd, s_cs, s_bl}));
        assign g10_status_w = {4'd0, s_rd, s_cs, s_bl};
        assign g10_last_w   = s_last;
        assign g10_aes_ct_w = s_ct;
        genvar a;
        for (a = 0; a < 4; a = a + 1) begin : g_aesd
            netsec_pulse_cdc u_p (.src_clk(clk156), .src_rst_n(rst156_n), .src_pulse(f_aes_done[a]),
                                  .dst_clk(clk125), .dst_rst_n(ctl_rst_n), .dst_pulse(g10_aes_done_w[a]));
        end
        assign status_w = {7'd0, s_rstn, init_b, init_a, idc_rdy, link_b, link_a, (&s_rd), s_ql, mmcm_locked};

        // SFP control pins
        assign sfp_tx_dis = g10_tx_dis;
        for (p = 0; p < 4; p = p + 1) begin : g_rs
            assign sfp_rs0[p] = g10_rs[2*p];
            assign sfp_rs1[p] = g10_rs[2*p+1];
        end
        assign any_bl = |s_bl;
    end else begin : g_no10g
        // Do not drive sfp_txp/txn. They are GTX pads, not fabric pins; a constant
        // driver makes opt_design insert OBUFs and write_bitstream then fails DRC
        // NSTD-1/UCIO-1. k7325fb_no10g.xdc drops the IO buffers on these ports.
        assign sfp_tx_dis = 4'hF; assign sfp_rs0 = 4'hF; assign sfp_rs1 = 4'hF;
        assign clk156 = 1'b0; assign rst156_n = 1'b0; assign qplllock = 1'b0;
        assign block_lock = 4'd0; assign core_status0 = 4'd0; assign gt_resetdone = 4'd0;
        assign g10_status_w = 16'd0; assign g10_last_w = 8'd0; assign g10_aes_ct_w = 512'd0; assign g10_aes_done_w = 4'd0;
        assign s10_val = 32'd0; assign s10_done = 1'b1;
        assign status_w = {7'd0, 1'b0, init_b, init_a, idc_rdy, link_b, link_a, 1'b0, 1'b0, mmcm_locked};
        assign any_bl = 1'b0;
    end endgenerate

    // =====================================================================
    // LEDs
    // =====================================================================
    reg [24:0] act_stretch;
    wire act_pulse = |{f1_rx, cm_pulse_a[0], cm_pulse_b[0]};
    always @(posedge clk125 or negedge ctl_rst_n) begin
        if (!ctl_rst_n) act_stretch <= 25'd0;
        else if (act_pulse) act_stretch <= 25'd12_500_000;
        else if (act_stretch != 0) act_stretch <= act_stretch - 1'b1;
    end
    wire [2:0] led_b = {link_a & link_b, (ENABLE_10G != 0) ? (&block_lock) : 1'b0, uptime_s[0]};
    wire [2:0] led_c = {act_stretch != 0, any_bl, mmcm_locked & ctl_rst_n};
    assign led_base    = LED_ACTIVE_HIGH ? led_b : ~led_b;
    assign led_core    = LED_ACTIVE_HIGH ? led_c : ~led_c;
endmodule
