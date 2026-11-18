// Port-accurate stand-ins for Xilinx primitives / IP so the whole design can be
// *elaborated* with Icarus (catches port-name and width mistakes). Not for simulation of the board.
module IBUF (input I, output O); assign O = I; endmodule
module IOBUF (input I, output O, input T, inout IO); assign IO = T ? 1'bz : I; assign O = IO; endmodule
module BUFG (input I, output O); assign O = I; endmodule
module BUFR #(parameter BUFR_DIVIDE="BYPASS", parameter SIM_DEVICE="7SERIES") (input I, input CE, input CLR, output O); assign O = I; endmodule
module BUFIO (input I, output O); assign O = I; endmodule
module IDELAYCTRL (input REFCLK, input RST, output RDY); assign RDY = 1'b1; endmodule
module IDELAYE2 #(parameter IDELAY_TYPE="FIXED", parameter integer IDELAY_VALUE=0, parameter DELAY_SRC="IDATAIN",
    parameter HIGH_PERFORMANCE_MODE="FALSE", parameter SIGNAL_PATTERN="DATA", parameter real REFCLK_FREQUENCY=200.0,
    parameter CINVCTRL_SEL="FALSE", parameter PIPE_SEL="FALSE")
  (input C, input REGRST, input LD, input CE, input INC, input CINVCTRL, input [4:0] CNTVALUEIN,
   output [4:0] CNTVALUEOUT, input IDATAIN, input DATAIN, output DATAOUT, input LDPIPEEN);
  assign DATAOUT = IDATAIN; assign CNTVALUEOUT = 5'd0;
endmodule
module IDDR #(parameter DDR_CLK_EDGE="SAME_EDGE_PIPELINED", parameter INIT_Q1=1'b0, parameter INIT_Q2=1'b0, parameter SRTYPE="ASYNC")
  (input C, input CE, input D, input R, input S, output reg Q1, output reg Q2);
  always @(posedge C) Q1 <= D; always @(negedge C) Q2 <= D;
endmodule
module ODDR #(parameter DDR_CLK_EDGE="SAME_EDGE", parameter INIT=1'b0, parameter SRTYPE="ASYNC")
  (input C, input CE, input D1, input D2, input R, input S, output Q);
  assign Q = C ? D1 : D2;
endmodule
module MMCME2_BASE #(parameter BANDWIDTH="OPTIMIZED", parameter real CLKIN1_PERIOD=10.0, parameter integer DIVCLK_DIVIDE=1,
    parameter real CLKFBOUT_MULT_F=5.0, parameter real CLKOUT0_DIVIDE_F=1.0, parameter real CLKOUT0_PHASE=0.0,
    parameter integer CLKOUT1_DIVIDE=1, parameter real CLKOUT1_PHASE=0.0,
    parameter integer CLKOUT2_DIVIDE=1, parameter real CLKOUT2_PHASE=0.0)
  (input CLKIN1, input CLKFBIN, output CLKFBOUT, output CLKFBOUTB, output CLKOUT0, output CLKOUT0B, output CLKOUT1,
   output CLKOUT1B, output CLKOUT2, output CLKOUT2B, output CLKOUT3, output CLKOUT3B, output CLKOUT4, output CLKOUT5,
   output CLKOUT6, output LOCKED, input PWRDWN, input RST);
  assign CLKFBOUT = CLKIN1; assign CLKOUT0 = CLKIN1; assign CLKOUT1 = CLKIN1; assign CLKOUT2 = CLKIN1; assign LOCKED = 1'b1;
  assign CLKFBOUTB=0; assign CLKOUT0B=0; assign CLKOUT1B=0; assign CLKOUT2B=0; assign CLKOUT3=0; assign CLKOUT3B=0;
  assign CLKOUT4=0; assign CLKOUT5=0; assign CLKOUT6=0;
endmodule
module jtag_axi_0 (input aclk, input aresetn,
  output [31:0] m_axi_awaddr, output [2:0] m_axi_awprot, output m_axi_awvalid, input m_axi_awready,
  output [31:0] m_axi_wdata, output [3:0] m_axi_wstrb, output m_axi_wvalid, input m_axi_wready,
  input [1:0] m_axi_bresp, input m_axi_bvalid, output m_axi_bready,
  output [31:0] m_axi_araddr, output [2:0] m_axi_arprot, output m_axi_arvalid, input m_axi_arready,
  input [31:0] m_axi_rdata, input [1:0] m_axi_rresp, input m_axi_rvalid, output m_axi_rready);
  assign m_axi_awaddr=0; assign m_axi_awprot=0; assign m_axi_awvalid=0; assign m_axi_wdata=0; assign m_axi_wstrb=0;
  assign m_axi_wvalid=0; assign m_axi_bready=1; assign m_axi_araddr=0; assign m_axi_arprot=0; assign m_axi_arvalid=0; assign m_axi_rready=1;
endmodule
module ten_gig_eth_pcs_pma_0 (input dclk, output rxrecclk_out, input refclk_p, input refclk_n, input sim_speedup_control,
  output coreclk_out, output qplloutclk_out, output qplloutrefclk_out, output qplllock_out, output txusrclk_out,
  output txusrclk2_out, output areset_datapathclk_out, output gttxreset_out, output gtrxreset_out, output txuserrdy_out,
  output reset_counter_done_out, input reset, input [63:0] xgmii_txd, input [7:0] xgmii_txc, output [63:0] xgmii_rxd,
  output [7:0] xgmii_rxc, output txp, output txn, input rxp, input rxn, input [535:0] configuration_vector,
  output [447:0] status_vector, output [7:0] core_status, output resetdone_out, input signal_detect, input tx_fault,
  output drp_req, input drp_gnt, output drp_den_o, output drp_dwe_o, output [15:0] drp_daddr_o, output [15:0] drp_di_o,
  output drp_drdy_o, output [15:0] drp_drpdo_o, input drp_den_i, input drp_dwe_i, input [15:0] drp_daddr_i,
  input [15:0] drp_di_i, input drp_drdy_i, input [15:0] drp_drpdo_i, input [2:0] pma_pmd_type, output tx_disable);
  assign coreclk_out = refclk_p; assign xgmii_rxd = 64'h0707070707070707; assign xgmii_rxc = 8'hFF;
  assign status_vector = 0; assign core_status = 0; assign resetdone_out = 1;
endmodule
module ten_gig_eth_pcs_pma_1 (input dclk, output rxrecclk_out, input coreclk, input txusrclk, input txusrclk2, output txoutclk,
  input areset, input areset_coreclk, input gttxreset, input gtrxreset, input sim_speedup_control, input txuserrdy,
  input qplllock, input qplloutclk, input qplloutrefclk, input reset_counter_done, input [63:0] xgmii_txd, input [7:0] xgmii_txc,
  output [63:0] xgmii_rxd, output [7:0] xgmii_rxc, output txp, output txn, input rxp, input rxn, input [535:0] configuration_vector,
  output [447:0] status_vector, output [7:0] core_status, output tx_resetdone, output rx_resetdone, input signal_detect,
  input tx_fault, output drp_req, input drp_gnt, output drp_den_o, output drp_dwe_o, output [15:0] drp_daddr_o,
  output [15:0] drp_di_o, output drp_drdy_o, output [15:0] drp_drpdo_o, input drp_den_i, input drp_dwe_i,
  input [15:0] drp_daddr_i, input [15:0] drp_di_i, input drp_drdy_i, input [15:0] drp_drpdo_i, input [2:0] pma_pmd_type,
  output tx_disable);
  assign xgmii_rxd = 64'h0707070707070707; assign xgmii_rxc = 8'hFF; assign status_vector = 0; assign core_status = 0;
  assign tx_resetdone = 1; assign rx_resetdone = 1;
endmodule
