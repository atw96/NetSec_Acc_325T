// rgmii_mac_k7.sv — 1G RGMII MAC for one RTL8211FD on 7-series (Kintex-7).
//   * verilog-ethernet eth_mac_1g_rgmii_fifo (IODDR + BUFR on rxc)
//   * IDELAYE2 (VAR_LOAD) on rxd/rx_ctl so the RX sampling point can be tuned
//     at run time from a register (5 taps, ~78 ps each @ 200 MHz IDELAYCTRL)
//   * gtx_clk = clk125, gtx_clk90 = clk125_90 (only used when USE_CLK90="TRUE")
// logic domain == clk125, 8-bit AXI-Stream, no tkeep.
`timescale 1ns / 1ps
module rgmii_mac_k7 #(
    parameter USE_CLK90 = "FALSE",   // PHY adds the TXC delay (strap or MDIO) -> FALSE
    parameter [4:0] DLY_INIT = 5'd0
) (
    input  wire        clk125,
    input  wire        clk125_90,
    input  wire        rst,           // active-high, sync to clk125

    input  wire [7:0]  tx_tdata,
    input  wire        tx_tvalid,
    output wire        tx_tready,
    input  wire        tx_tlast,
    input  wire        tx_tuser,

    output wire [7:0]  rx_tdata,
    output wire        rx_tvalid,
    input  wire        rx_tready,
    output wire        rx_tlast,
    output wire        rx_tuser,

    input  wire        rgmii_rxc,
    input  wire [3:0]  rgmii_rd,
    input  wire        rgmii_rx_ctl,
    output wire        rgmii_txc,
    output wire [3:0]  rgmii_td,
    output wire        rgmii_tx_ctl,

    input  wire [4:0]  dly_tap,
    input  wire        dly_load,      // 1-cycle pulse, clk125

    output wire [1:0]  speed,
    output wire        p_rx_bad_frame,
    output wire        p_rx_bad_fcs,
    output wire        p_rx_good,
    output wire        p_rx_ovf,
    output wire        p_tx_good,
    output wire        p_tx_underflow
);
    // ---- runtime-loadable input delay ----
    reg [2:0] rst_d;
    always @(posedge clk125) rst_d <= {rst_d[1:0], rst};
    // rst_d[0]/[1] = rst delayed by 1/2 cycles: rst_d[1]&~rst_d[0] is the cycle after reset release
    wire init_load = rst_d[1] & ~rst_d[0];
    wire ld = init_load | dly_load;
    wire [4:0] cnt_in = init_load ? DLY_INIT : dly_tap;

    wire [3:0] rd_dly;
    wire       ctl_dly;
    genvar k;
    generate
        for (k = 0; k < 5; k = k + 1) begin : g_dly
            wire din = (k == 4) ? rgmii_rx_ctl : rgmii_rd[k];
            wire dout;
            (* IODELAY_GROUP = "k7_rgmii_dly" *)
            IDELAYE2 #(
                .IDELAY_TYPE("VAR_LOAD"),
                .IDELAY_VALUE(DLY_INIT),
                .DELAY_SRC("IDATAIN"),
                .HIGH_PERFORMANCE_MODE("TRUE"),
                .SIGNAL_PATTERN("DATA"),
                .REFCLK_FREQUENCY(200.0),
                .CINVCTRL_SEL("FALSE"),
                .PIPE_SEL("FALSE")
            ) u_idly (
                .C(clk125), .REGRST(1'b0), .LD(ld), .CE(1'b0), .INC(1'b0),
                .CINVCTRL(1'b0), .CNTVALUEIN(cnt_in), .CNTVALUEOUT(),
                .IDATAIN(din), .DATAIN(1'b0), .DATAOUT(dout), .LDPIPEEN(1'b0)
            );
            if (k == 4) assign ctl_dly = dout; else assign rd_dly[k] = dout;
        end
    endgenerate

    eth_mac_1g_rgmii_fifo #(
        .TARGET("XILINX"),
        .IODDR_STYLE("IODDR"),
        .CLOCK_INPUT_STYLE("BUFR"),
        .USE_CLK90(USE_CLK90),
        .ENABLE_PADDING(1),
        .MIN_FRAME_LENGTH(64),
        .TX_FIFO_DEPTH(4096), .TX_FRAME_FIFO(1),
        .RX_FIFO_DEPTH(4096), .RX_FRAME_FIFO(1)
    ) u_mac (
        .gtx_clk(clk125), .gtx_clk90(clk125_90), .gtx_rst(rst),
        .logic_clk(clk125), .logic_rst(rst),
        .tx_axis_tdata(tx_tdata), .tx_axis_tkeep(1'b1), .tx_axis_tvalid(tx_tvalid),
        .tx_axis_tready(tx_tready), .tx_axis_tlast(tx_tlast), .tx_axis_tuser(tx_tuser),
        .rx_axis_tdata(rx_tdata), .rx_axis_tkeep(), .rx_axis_tvalid(rx_tvalid),
        .rx_axis_tready(rx_tready), .rx_axis_tlast(rx_tlast), .rx_axis_tuser(rx_tuser),
        .rgmii_rx_clk(rgmii_rxc), .rgmii_rxd(rd_dly), .rgmii_rx_ctl(ctl_dly),
        .rgmii_tx_clk(rgmii_txc), .rgmii_txd(rgmii_td), .rgmii_tx_ctl(rgmii_tx_ctl),
        .tx_error_underflow(p_tx_underflow), .tx_fifo_overflow(), .tx_fifo_bad_frame(),
        .tx_fifo_good_frame(p_tx_good),
        .rx_error_bad_frame(p_rx_bad_frame), .rx_error_bad_fcs(p_rx_bad_fcs),
        .rx_fifo_overflow(p_rx_ovf), .rx_fifo_bad_frame(), .rx_fifo_good_frame(p_rx_good),
        .speed(speed),
        .cfg_ifg(8'd12), .cfg_tx_enable(1'b1), .cfg_rx_enable(1'b1)
    );
endmodule
