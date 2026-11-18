# build.tcl — synthesis, implementation, bitstream, reports and flash image.
#   vivado -mode batch -source scripts/build.tcl            (after create_project.tcl)
set here [file dirname [file normalize [info script]]]
set root [file normalize [file join $here ..]]
set projdir [file join $root build proj]
set jobs 8
if {[info exists ::env(NETSEC_JOBS)]} { set jobs $::env(NETSEC_JOBS) }
open_project [file join $projdir netsec_k7.xpr]

reset_run synth_1
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "synthesis failed" }
open_run synth_1 -name synth_1
set rpt [file join $root build reports]; file mkdir $rpt
report_utilization -file [file join $rpt utilization_synth.rpt]
report_utilization -hierarchical -file [file join $rpt utilization_synth_hier.rpt]
report_clock_networks -file [file join $rpt clock_networks_synth.rpt]
report_cdc -file [file join $rpt cdc_synth.rpt]
close_design

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "implementation failed" }
open_run impl_1
report_timing_summary -delay_type min_max -max_paths 20 -file [file join $rpt timing_summary.rpt]
report_utilization -file [file join $rpt utilization_impl.rpt]
report_clock_interaction -file [file join $rpt clock_interaction.rpt]
report_methodology -file [file join $rpt methodology.rpt]
report_drc -file [file join $rpt drc.rpt]
report_io -file [file join $rpt io.rpt]
report_power -file [file join $rpt power.rpt]

set out [file join $root build out]; file mkdir $out
set bit [file join $projdir netsec_k7.runs impl_1 netsec_k7_top.bit]
file copy -force $bit [file join $out netsec_k7_top.bit]
write_cfgmem -force -format mcs -size 32 -interface SPIx4 -loadbit "up 0x0 $bit" [file join $out netsec_k7_top.mcs]
set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
puts "RESULT: WNS=$wns ns  WHS=$whs ns"
puts "RESULT: bitstream -> $out/netsec_k7_top.bit , flash image -> $out/netsec_k7_top.mcs"
if {$wns < 0} { puts "WARNING: timing not met — see docs/PLAN.md §7 (timing closure ladder)" }
