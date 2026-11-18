# =============================================================================
# MK7325FB (XC7K325T-2FFG900I) pin constraints for netsec_k7_top
# Source: MLK-F12-CK03-1156-K7325FB hardware manual (tables 5-x) cross-checked against the
#         base-board schematic (P03..P14) and core-module schematic (P03..P09).
# Bank voltages on the MiLianKe base board: banks 12/13 = 1.8 V (forced), 15/16 = 3.3 V,
# bank 14 = 3.3 V, bank 18 = VCCADJ (1.8 V default), HP banks 32/33/34 = 1.35 V (DDR3).
# Items marked [VERIFY] are inferred and listed in docs/risks.md.
# =============================================================================

# ---- configuration ----------------------------------------------------------
set_property CFGBVS VCCO                       [current_design]
set_property CONFIG_VOLTAGE 3.3                [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE   [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4   [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33    [current_design]
set_property CONFIG_MODE SPIx4                 [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLUP [current_design]

# ---- 100 MHz system clock (core board XT1, bank 33 MRCC) --------------------
# [VERIFY] Bank 33 is powered from DDR_VCCIO (1.35 V). The manual only states "100 MHz single ended, AD12".
set_property PACKAGE_PIN AD12     [get_ports sys_clk_100m]
set_property IOSTANDARD  SSTL135  [get_ports sys_clk_100m]   ;# bank 33 is 1.35 V; same as the vendor RGMII example

# ---- reset button BUT2 (base board, bank 13, active low, external pull-up) --
set_property PACKAGE_PIN Y28      [get_ports rst_btn_n]
set_property IOSTANDARD  LVCMOS18 [get_ports rst_btn_n]
set_property PULLUP      true     [get_ports rst_btn_n]

# ---- UART (CP2104, bank 13 @1.8 V) -------------------------------------------
# Net names in the manual are from the CP2104's point of view: "UART_TXD" (AA26) is the CP2104 TXD
# output, i.e. the FPGA *receives* on AA26. If nothing answers on the UART, use k7325fb_uart_swap.xdc.
set_property PACKAGE_PIN AA26     [get_ports uart_rxd]
set_property PACKAGE_PIN Y26      [get_ports uart_txd]
set_property IOSTANDARD  LVCMOS18 [get_ports {uart_rxd uart_txd}]

# ---- LEDs --------------------------------------------------------------------
# base board D4/D5 (bank 13, 1.8 V) and D6 (J21 is a bank-15 pin -> 3.3 V) [VERIFY polarity: top parameter LED_ACTIVE_HIGH]
set_property PACKAGE_PIN AB28     [get_ports {led_base[0]}]
set_property PACKAGE_PIN AA27     [get_ports {led_base[1]}]
set_property PACKAGE_PIN J21      [get_ports {led_base[2]}]
set_property IOSTANDARD  LVCMOS18 [get_ports {led_base[0] led_base[1]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {led_base[2]}]
# core board D17/D16/D15 (bank 14, 3.3 V)
set_property PACKAGE_PIN T30      [get_ports {led_core[0]}]
set_property PACKAGE_PIN U30      [get_ports {led_core[1]}]
set_property PACKAGE_PIN V30      [get_ports {led_core[2]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {led_core[*]}]
set_property SLEW SLOW            [get_ports {led_base[*] led_core[*]}]

# ---- 10G: GTX quad 118 -----------------------------------------------------
# Reference clock: CDCM61002 OUT -> MGTREFCLK1 of quad 118 (E8/E7). 156.25 MHz when SW4 = 10GigE row.
set_property PACKAGE_PIN E8 [get_ports mgt_refclk_p]
set_property PACKAGE_PIN E7 [get_ports mgt_refclk_n]
# SFP+ A..D = GTX channels 0..3 of quad 118 (TX P/N, RX P/N)
set_property PACKAGE_PIN D2 [get_ports {sfp_txp[0]}]
set_property PACKAGE_PIN D1 [get_ports {sfp_txn[0]}]
set_property PACKAGE_PIN E4 [get_ports {sfp_rxp[0]}]
set_property PACKAGE_PIN E3 [get_ports {sfp_rxn[0]}]
set_property PACKAGE_PIN C4 [get_ports {sfp_txp[1]}]
set_property PACKAGE_PIN C3 [get_ports {sfp_txn[1]}]
set_property PACKAGE_PIN D6 [get_ports {sfp_rxp[1]}]
set_property PACKAGE_PIN D5 [get_ports {sfp_rxn[1]}]
set_property PACKAGE_PIN B2 [get_ports {sfp_txp[2]}]
set_property PACKAGE_PIN B1 [get_ports {sfp_txn[2]}]
set_property PACKAGE_PIN B6 [get_ports {sfp_rxp[2]}]
set_property PACKAGE_PIN B5 [get_ports {sfp_rxn[2]}]
set_property PACKAGE_PIN A4 [get_ports {sfp_txp[3]}]
set_property PACKAGE_PIN A3 [get_ports {sfp_txn[3]}]
set_property PACKAGE_PIN A8 [get_ports {sfp_rxp[3]}]
set_property PACKAGE_PIN A7 [get_ports {sfp_rxn[3]}]

# SFP+ module control. SFP A is wired straight to bank 16 (3.3 V); B/C/D go through a TXS0108
# level shifter from bank 13 (1.8 V). TX_FAULT / LOS / MOD_ABS / I2C are not routed to the FPGA.
set_property PACKAGE_PIN B23  [get_ports {sfp_tx_dis[0]}]
set_property PACKAGE_PIN A23  [get_ports {sfp_rs0[0]}]
set_property PACKAGE_PIN A25  [get_ports {sfp_rs1[0]}]
set_property PACKAGE_PIN AA25 [get_ports {sfp_tx_dis[1]}]
set_property PACKAGE_PIN AB25 [get_ports {sfp_rs0[1]}]
set_property PACKAGE_PIN AD27 [get_ports {sfp_rs1[1]}]
set_property PACKAGE_PIN AD28 [get_ports {sfp_tx_dis[2]}]
set_property PACKAGE_PIN Y30  [get_ports {sfp_rs0[2]}]
set_property PACKAGE_PIN AA30 [get_ports {sfp_rs1[2]}]
set_property PACKAGE_PIN AB29 [get_ports {sfp_tx_dis[3]}]
set_property PACKAGE_PIN AB30 [get_ports {sfp_rs0[3]}]
set_property PACKAGE_PIN AC29 [get_ports {sfp_rs1[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sfp_tx_dis[0] sfp_rs0[0] sfp_rs1[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {sfp_tx_dis[1] sfp_rs0[1] sfp_rs1[1] sfp_tx_dis[2] sfp_rs0[2] sfp_rs1[2] sfp_tx_dis[3] sfp_rs0[3] sfp_rs1[3]}]
set_property SLEW SLOW  [get_ports {sfp_tx_dis[*] sfp_rs0[*] sfp_rs1[*]}]
set_property DRIVE 4    [get_ports {sfp_tx_dis[*] sfp_rs0[*] sfp_rs1[*]}]

# ---- RGMII A = ETHA (RTL8211FD, PHY address 2), bank 13 @ 1.8 V -------------
set_property PACKAGE_PIN AB27 [get_ports eth_a_rxc]
set_property PACKAGE_PIN AE30 [get_ports {eth_a_rxd[0]}]
set_property PACKAGE_PIN AE29 [get_ports {eth_a_rxd[1]}]
set_property PACKAGE_PIN AD29 [get_ports {eth_a_rxd[2]}]
set_property PACKAGE_PIN AC27 [get_ports {eth_a_rxd[3]}]
set_property PACKAGE_PIN AF30 [get_ports eth_a_rx_ctl]
set_property PACKAGE_PIN AF28 [get_ports eth_a_txc]
set_property PACKAGE_PIN AG28 [get_ports {eth_a_txd[0]}]
set_property PACKAGE_PIN AG27 [get_ports {eth_a_txd[1]}]
set_property PACKAGE_PIN AF27 [get_ports {eth_a_txd[2]}]
set_property PACKAGE_PIN AF26 [get_ports {eth_a_txd[3]}]
set_property PACKAGE_PIN AE28 [get_ports eth_a_tx_ctl]
set_property PACKAGE_PIN W27  [get_ports eth_a_mdc]
set_property PACKAGE_PIN W28  [get_ports eth_a_mdio]
# ---- RGMII B = ETHB (RTL8211FD, PHY address 1) ------------------------------
set_property PACKAGE_PIN AG29 [get_ports eth_b_rxc]
set_property PACKAGE_PIN AH27 [get_ports {eth_b_rxd[0]}]
set_property PACKAGE_PIN AJ27 [get_ports {eth_b_rxd[1]}]
set_property PACKAGE_PIN AK28 [get_ports {eth_b_rxd[2]}]
set_property PACKAGE_PIN AJ26 [get_ports {eth_b_rxd[3]}]
set_property PACKAGE_PIN AH26 [get_ports eth_b_rx_ctl]
set_property PACKAGE_PIN AK26 [get_ports eth_b_txc]
set_property PACKAGE_PIN AH30 [get_ports {eth_b_txd[0]}]
set_property PACKAGE_PIN AJ28 [get_ports {eth_b_txd[1]}]
set_property PACKAGE_PIN AJ29 [get_ports {eth_b_txd[2]}]
set_property PACKAGE_PIN AK29 [get_ports {eth_b_txd[3]}]
set_property PACKAGE_PIN AG30 [get_ports eth_b_tx_ctl]
set_property PACKAGE_PIN AC26 [get_ports eth_b_mdc]
set_property PACKAGE_PIN AD26 [get_ports eth_b_mdio]
# shared PHY reset (active low, to both PHYs through the level shifter)
set_property PACKAGE_PIN AK30 [get_ports eth_rst_n]

set_property IOSTANDARD LVCMOS18 [get_ports {eth_a_* eth_b_* eth_rst_n}]
set_property SLEW FAST  [get_ports {eth_a_txc eth_a_txd[*] eth_a_tx_ctl eth_b_txc eth_b_txd[*] eth_b_tx_ctl}]
set_property DRIVE 12   [get_ports {eth_a_txc eth_a_txd[*] eth_a_tx_ctl eth_b_txc eth_b_txd[*] eth_b_tx_ctl}]
set_property SLEW SLOW  [get_ports {eth_a_mdc eth_b_mdc eth_rst_n eth_a_mdio eth_b_mdio}]
set_property DRIVE 4    [get_ports {eth_a_mdc eth_b_mdc eth_rst_n eth_a_mdio eth_b_mdio}]
set_property PULLUP true [get_ports {eth_a_mdio eth_b_mdio}]
