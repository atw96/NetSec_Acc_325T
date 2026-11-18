// gt10g_quad.sv — four 10GBASE-R PCS/PMA channels on one GTX quad (Quad 118 on MK7325FB).
//
// Uses the Xilinx "10GBASE-R/KR PCS/PMA" LogiCORE (ten_gig_eth_pcs_pma), configured
// without MDIO, BASE-R, DClkRate = 125:
//   ten_gig_eth_pcs_pma_0 : SupportLevel=1  (QPLL, clocking and reset logic in the core)  -> SFP A
//   ten_gig_eth_pcs_pma_1 : SupportLevel=0  (takes the shared clocks/QPLL from core 0)    -> SFP B,C,D
// The wiring follows the 4-lane 7-series reference in verilog-ethernet (NetFPGA-SUME).
//
// Everything user-side runs on coreclk (156.25 MHz) = clk156.
//
// !! REFCLK: the CDCM61002 on this board feeds MGTREFCLK1 of Quad 118 (pins E8/E7), while
// !! the stock shared logic of the core connects its IBUFDS_GTE2 to GTREFCLK0.
// !! scripts/patch_gt_refclk.tcl rewrites the generated shared-logic file to use GTREFCLK1.
`timescale 1ns / 1ps
module gt10g_quad (
    input  wire         dclk,              // free-running 125 MHz
    input  wire         reset_in,          // active-high, async
    input  wire         refclk_p,
    input  wire         refclk_n,

    output wire [3:0]   txp,
    output wire [3:0]   txn,
    input  wire [3:0]   rxp,
    input  wire [3:0]   rxn,

    output wire         clk156,
    output wire         rst156_n,          // synchronous to clk156, low until all channels are up

    input  wire [255:0] xgmii_txd,         // 4 x 64
    input  wire [31:0]  xgmii_txc,         // 4 x 8
    output wire [255:0] xgmii_rxd,
    output wire [31:0]  xgmii_rxc,

    output wire         qplllock,
    output wire [3:0]   block_lock,        // per channel (status_vector[256])
    output wire [3:0]   core_status0,      // per channel core_status[0]
    output wire [3:0]   resetdone          // per channel (core0: resetdone_out, others: tx&rx)
);
    wire txusrclk, txusrclk2, coreclk, qplloutclk, qplloutrefclk;
    wire gttxreset, gtrxreset, txuserrdy, areset_datapathclk, reset_counter_done;
    wire core_reset;
    wire core_reset_n;

    // reset into the cores is synchronised to coreclk (as in the reference design)
    u_reset_sync u_rs_core (.clk(coreclk), .async_rst_n(~reset_in), .sync_rst_n(core_reset_n));
    assign core_reset = ~core_reset_n;

    wire [535:0] cfg_vec = 536'd0;           // no loopback / test patterns / resets
    wire [447:0] st_vec0;
    wire [7:0]   cs0;
    wire         rdone0;

    assign clk156 = coreclk;

    ten_gig_eth_pcs_pma_0 u_pcs0 (
        .dclk(dclk), .rxrecclk_out(),
        .refclk_p(refclk_p), .refclk_n(refclk_n),
        .sim_speedup_control(1'b0),
        .coreclk_out(coreclk), .qplloutclk_out(qplloutclk), .qplloutrefclk_out(qplloutrefclk),
        .qplllock_out(qplllock), .txusrclk_out(txusrclk), .txusrclk2_out(txusrclk2),
        .areset_datapathclk_out(areset_datapathclk), .gttxreset_out(gttxreset), .gtrxreset_out(gtrxreset),
        .txuserrdy_out(txuserrdy), .reset_counter_done_out(reset_counter_done),
        .reset(core_reset),
        .xgmii_txd(xgmii_txd[63:0]),  .xgmii_txc(xgmii_txc[7:0]),
        .xgmii_rxd(xgmii_rxd[63:0]),  .xgmii_rxc(xgmii_rxc[7:0]),
        .txp(txp[0]), .txn(txn[0]), .rxp(rxp[0]), .rxn(rxn[0]),
        .configuration_vector(cfg_vec), .status_vector(st_vec0), .core_status(cs0),
        .resetdone_out(rdone0),
        .signal_detect(1'b1), .tx_fault(1'b0),
        .drp_req(), .drp_gnt(1'b1), .drp_den_o(), .drp_dwe_o(), .drp_daddr_o(), .drp_di_o(),
        .drp_drdy_o(), .drp_drpdo_o(), .drp_den_i(1'b0), .drp_dwe_i(1'b0), .drp_daddr_i(16'd0),
        .drp_di_i(16'd0), .drp_drdy_i(1'b0), .drp_drpdo_i(16'd0),
        .pma_pmd_type(3'd0), .tx_disable()
    );

    wire [447:0] st_vec_s [1:3];
    wire [7:0]   cs_s     [1:3];
    wire [3:1]   trd, rrd;
    genvar gk;
    generate
        for (gk = 1; gk < 4; gk = gk + 1) begin : g_slave
            ten_gig_eth_pcs_pma_1 u_pcs (
                .dclk(dclk), .rxrecclk_out(), .coreclk(coreclk), .txusrclk(txusrclk), .txusrclk2(txusrclk2),
                .txoutclk(), .areset(core_reset), .areset_coreclk(areset_datapathclk),
                .gttxreset(gttxreset), .gtrxreset(gtrxreset), .sim_speedup_control(1'b0),
                .txuserrdy(txuserrdy), .qplllock(qplllock), .qplloutclk(qplloutclk), .qplloutrefclk(qplloutrefclk),
                .reset_counter_done(reset_counter_done),
                .xgmii_txd(xgmii_txd[gk*64 +: 64]), .xgmii_txc(xgmii_txc[gk*8 +: 8]),
                .xgmii_rxd(xgmii_rxd[gk*64 +: 64]), .xgmii_rxc(xgmii_rxc[gk*8 +: 8]),
                .txp(txp[gk]), .txn(txn[gk]), .rxp(rxp[gk]), .rxn(rxn[gk]),
                .configuration_vector(cfg_vec), .status_vector(st_vec_s[gk]), .core_status(cs_s[gk]),
                .tx_resetdone(trd[gk]), .rx_resetdone(rrd[gk]),
                .signal_detect(1'b1), .tx_fault(1'b0),
                .drp_req(), .drp_gnt(1'b1), .drp_den_o(), .drp_dwe_o(), .drp_daddr_o(), .drp_di_o(),
                .drp_drdy_o(), .drp_drpdo_o(), .drp_den_i(1'b0), .drp_dwe_i(1'b0), .drp_daddr_i(16'd0),
                .drp_di_i(16'd0), .drp_drdy_i(1'b0), .drp_drpdo_i(16'd0),
                .pma_pmd_type(3'd0), .tx_disable()
            );
        end
    endgenerate

    assign block_lock   = {st_vec_s[3][256], st_vec_s[2][256], st_vec_s[1][256], st_vec0[256]};
    assign core_status0 = {cs_s[3][0], cs_s[2][0], cs_s[1][0], cs0[0]};
    assign resetdone    = {trd[3] & rrd[3], trd[2] & rrd[2], trd[1] & rrd[1], rdone0};

    // user-side reset: released once every channel has finished its GT reset sequence
    wire all_rdone = &resetdone;
    u_reset_sync u_rs_156 (.clk(coreclk), .async_rst_n(all_rdone), .sync_rst_n(rst156_n));
endmodule
