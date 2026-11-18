# program.tcl — load the bitstream over JTAG (volatile).   vivado -mode batch -source scripts/program.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
set bit  [file join $root build out netsec_k7_top.bit]
if {[info exists ::env(NETSEC_BIT)]} { set bit $::env(NETSEC_BIT) }
source [file join $root scripts hw_regs.tcl]
ns_open
set dev [current_hw_device]
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
refresh_hw_device $dev
puts "INFO: programmed $bit"
