# =============================================================================
# Timing constraints — netsec_k7_top
# Procedural Tcl (foreach/eval) is rejected by Vivado's XDC parser
# (Designutils 20-1307), so every constraint below is a single command.
# =============================================================================
create_clock -name sys_clk    -period 10.000 [get_ports sys_clk_100m]
create_clock -name mgt_refclk -period 6.400  [get_ports mgt_refclk_p]
create_clock -name rgmii_a_rxc -period 8.000 [get_ports eth_a_rxc]
create_clock -name rgmii_b_rxc -period 8.000 [get_ports eth_b_rxc]

# Control / RGMII-logic clocks (MMCM, derived from sys_clk) and the 10G user clock
# (PCS/PMA, derived from mgt_refclk) are unrelated. Every crossing goes through
# netsec_pulse_cdc / netsec_level_cdc / stat_bank handshakes / async FIFOs.
# IP-internal GT clocks stay in the mgt_refclk group and keep the PCS/PMA XDC.
set_clock_groups -asynchronous \
    -group [get_clocks -quiet -include_generated_clocks sys_clk] \
    -group [get_clocks -quiet -include_generated_clocks mgt_refclk] \
    -group [get_clocks -quiet rgmii_a_rxc] \
    -group [get_clocks -quiet rgmii_b_rxc]

# slow, quasi-static / debug I/O
set_false_path -from [get_ports {rst_btn_n uart_rxd}]
set_false_path -to   [get_ports {uart_txd led_base[*] led_core[*] sfp_tx_dis[*] sfp_rs0[*] sfp_rs1[*] eth_rst_n}]
set_false_path -to   [get_ports {eth_a_mdc eth_b_mdc eth_a_mdio eth_b_mdio}]
set_false_path -from [get_ports {eth_a_mdio eth_b_mdio}]

# RGMII RX data/ctl is sampled by an IDDR whose clock comes through BUFIO, while the
# data goes through IDELAYE2. At tap 0 the clock insertion is ~2.6 ns and the data
# path is ~1.3 ns, so a centred-eye set_input_delay (+/-1.4 ns, risks.md R14) cannot
# meet hold. The operating tap is chosen at run time (regs 0x220/0x224, rx-delay-scan),
# so these pins are not signed off by static timing.
set_false_path -from [get_ports {eth_a_rxd[*] eth_a_rx_ctl eth_b_rxd[*] eth_b_rx_ctl}]
