// mac10g_port.sv — one 10G MAC (verilog-ethernet eth_mac_10g, XGMII/64-bit) with
// all pause/PFC/PTP options tied off. Both directions run on clk156, the single
// 156.25 MHz domain provided by the PCS/PMA shared logic.
`timescale 1ns / 1ps
module mac10g_port (
    input  wire         clk,
    input  wire         rst,            // active-high, synchronous to clk
    // AXI-Stream into MAC (toward wire)
    input  wire [63:0]  tx_tdata,
    input  wire [7:0]   tx_tkeep,
    input  wire         tx_tvalid,
    output wire         tx_tready,
    input  wire         tx_tlast,
    input  wire         tx_tuser,
    // AXI-Stream out of MAC (from wire), no back-pressure
    output wire [63:0]  rx_tdata,
    output wire [7:0]   rx_tkeep,
    output wire         rx_tvalid,
    output wire         rx_tlast,
    output wire         rx_tuser,
    // XGMII to/from PCS/PMA
    input  wire [63:0]  xgmii_rxd,
    input  wire [7:0]   xgmii_rxc,
    output wire [63:0]  xgmii_txd,
    output wire [7:0]   xgmii_txc,
    // status pulses
    output wire         st_tx_underflow,
    output wire         st_rx_bad_frame,
    output wire         st_rx_bad_fcs
);
    eth_mac_10g #(
        .DATA_WIDTH(64),
        .ENABLE_PADDING(1),
        .ENABLE_DIC(1),
        .MIN_FRAME_LENGTH(64),
        .PTP_TS_ENABLE(0),
        .PFC_ENABLE(0),
        .PAUSE_ENABLE(0)
    ) u_mac (
        .rx_clk(clk), .rx_rst(rst), .tx_clk(clk), .tx_rst(rst),
        .tx_axis_tdata(tx_tdata), .tx_axis_tkeep(tx_tkeep), .tx_axis_tvalid(tx_tvalid),
        .tx_axis_tready(tx_tready), .tx_axis_tlast(tx_tlast), .tx_axis_tuser(tx_tuser),
        .rx_axis_tdata(rx_tdata), .rx_axis_tkeep(rx_tkeep), .rx_axis_tvalid(rx_tvalid),
        .rx_axis_tlast(rx_tlast), .rx_axis_tuser(rx_tuser),
        .xgmii_rxd(xgmii_rxd), .xgmii_rxc(xgmii_rxc),
        .xgmii_txd(xgmii_txd), .xgmii_txc(xgmii_txc),
        .tx_ptp_ts(96'd0), .rx_ptp_ts(96'd0),
        .tx_axis_ptp_ts(), .tx_axis_ptp_ts_tag(), .tx_axis_ptp_ts_valid(),
        .tx_lfc_req(1'b0), .tx_lfc_resend(1'b0), .rx_lfc_en(1'b0), .rx_lfc_req(), .rx_lfc_ack(1'b0),
        .tx_pfc_req(8'd0), .tx_pfc_resend(1'b0), .rx_pfc_en(8'd0), .rx_pfc_req(), .rx_pfc_ack(8'd0),
        .tx_lfc_pause_en(1'b0), .tx_pause_req(1'b0), .tx_pause_ack(),
        .tx_start_packet(), .tx_error_underflow(st_tx_underflow),
        .rx_start_packet(), .rx_error_bad_frame(st_rx_bad_frame), .rx_error_bad_fcs(st_rx_bad_fcs),
        .stat_tx_mcf(), .stat_rx_mcf(),
        .stat_tx_lfc_pkt(), .stat_tx_lfc_xon(), .stat_tx_lfc_xoff(), .stat_tx_lfc_paused(),
        .stat_tx_pfc_pkt(), .stat_tx_pfc_xon(), .stat_tx_pfc_xoff(), .stat_tx_pfc_paused(),
        .stat_rx_lfc_pkt(), .stat_rx_lfc_xon(), .stat_rx_lfc_xoff(), .stat_rx_lfc_paused(),
        .stat_rx_pfc_pkt(), .stat_rx_pfc_xon(), .stat_rx_pfc_xoff(), .stat_rx_pfc_paused(),
        .cfg_ifg(8'd12), .cfg_tx_enable(1'b1), .cfg_rx_enable(1'b1),
        .cfg_mcf_rx_eth_dst_mcast(48'd0), .cfg_mcf_rx_check_eth_dst_mcast(1'b0),
        .cfg_mcf_rx_eth_dst_ucast(48'd0), .cfg_mcf_rx_check_eth_dst_ucast(1'b0),
        .cfg_mcf_rx_eth_src(48'd0), .cfg_mcf_rx_check_eth_src(1'b0),
        .cfg_mcf_rx_eth_type(16'd0), .cfg_mcf_rx_opcode_lfc(16'd0), .cfg_mcf_rx_check_opcode_lfc(1'b0),
        .cfg_mcf_rx_opcode_pfc(16'd0), .cfg_mcf_rx_check_opcode_pfc(1'b0),
        .cfg_mcf_rx_forward(1'b0), .cfg_mcf_rx_enable(1'b0),
        .cfg_tx_lfc_eth_dst(48'd0), .cfg_tx_lfc_eth_src(48'd0), .cfg_tx_lfc_eth_type(16'd0),
        .cfg_tx_lfc_opcode(16'd0), .cfg_tx_lfc_en(1'b0), .cfg_tx_lfc_quanta(16'd0), .cfg_tx_lfc_refresh(16'd0),
        .cfg_tx_pfc_eth_dst(48'd0), .cfg_tx_pfc_eth_src(48'd0), .cfg_tx_pfc_eth_type(16'd0),
        .cfg_tx_pfc_opcode(16'd0), .cfg_tx_pfc_en(1'b0), .cfg_tx_pfc_quanta(128'd0), .cfg_tx_pfc_refresh(128'd0),
        .cfg_rx_lfc_opcode(16'd0), .cfg_rx_lfc_en(1'b0), .cfg_rx_pfc_opcode(16'd0), .cfg_rx_pfc_en(1'b0)
    );
endmodule
