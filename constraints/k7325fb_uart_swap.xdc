# Loaded only when NETSEC_UART_SWAP=1 (create_project.tcl, PROCESSING_ORDER LATE).
# Swaps the CP2104 pair relative to k7325fb_pins.xdc: FPGA receives on Y26, transmits on AA26.
set_property PACKAGE_PIN Y26      [get_ports uart_rxd]
set_property PACKAGE_PIN AA26     [get_ports uart_txd]
set_property IOSTANDARD  LVCMOS18 [get_ports {uart_rxd uart_txd}]
