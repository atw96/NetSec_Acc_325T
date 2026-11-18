# Insert an ILA on PHY A MDIO into the existing synth checkpoint and implement it.
# Clock is clk125, depth 8192. Probes: MDC, mdio_t, mdio_i.
set root [file normalize [file join [file dirname [info script]] .. ..]]
file mkdir [file join $root build out_ila]
open_checkpoint [file join $root build proj netsec_k7.runs synth_1 netsec_k7_top.dcp]

set_property MARK_DEBUG true [get_nets eth_a_mdc_OBUF]
set_property MARK_DEBUG true [get_nets mdio_t_a]
set_property MARK_DEBUG true [get_nets mdio_i_a]

create_debug_core u_ila_mdio ila
set_property C_DATA_DEPTH 8192 [get_debug_cores u_ila_mdio]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_mdio]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_mdio]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_mdio]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_mdio]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_mdio]
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_mdio]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_mdio]
connect_debug_port u_ila_mdio/clk [get_nets clk125]
set_property port_width 1 [get_debug_ports u_ila_mdio/probe0]
connect_debug_port u_ila_mdio/probe0 [get_nets eth_a_mdc_OBUF]
create_debug_port u_ila_mdio probe
set_property port_width 1 [get_debug_ports u_ila_mdio/probe1]
connect_debug_port u_ila_mdio/probe1 [get_nets mdio_t_a]
create_debug_port u_ila_mdio probe
set_property port_width 1 [get_debug_ports u_ila_mdio/probe2]
connect_debug_port u_ila_mdio/probe2 [get_nets mdio_i_a]
implement_debug_core
puts "INFO: ILA inserted"
# The synth checkpoint does not carry PACKAGE_PIN / IOSTANDARD. Timing XDC is already in it.
read_xdc [file join $root constraints k7325fb_pins.xdc]
read_xdc [file join $root constraints k7325fb_no10g.xdc]

opt_design
place_design -directive ExtraTimingOpt
phys_opt_design
route_design -directive Explore
phys_opt_design
report_timing_summary -max_paths 1 -file [file join $root build logs ila_timing.rpt]
write_debug_probes -force [file join $root build out_ila netsec_k7_ila.ltx]
write_bitstream -force [file join $root build out_ila netsec_k7_ila.bit]
puts "INFO: ILA bitstream written"
exit 0
