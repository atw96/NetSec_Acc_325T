# flash.tcl — write the .mcs to the on-board S25FL256S QSPI flash (power-cycle afterwards).
set root [file normalize [file join [file dirname [info script]] ..]]
set mcs  [file join $root build out netsec_k7_top.mcs]
source [file join $root scripts hw_regs.tcl]
ns_open
set dev [current_hw_device]
create_hw_cfgmem -hw_device $dev [lindex [get_cfgmem_parts {s25fl256sxxxxxx0-spi-x1_x2_x4}] 0]
set cm [get_property PROGRAM.HW_CFGMEM $dev]
set_property PROGRAM.ADDRESS_RANGE {use_file} $cm
set_property PROGRAM.FILES [list $mcs] $cm
set_property PROGRAM.PRM_FILE {} $cm
set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} $cm
set_property PROGRAM.BLANK_CHECK 0 $cm
set_property PROGRAM.ERASE 1 $cm
set_property PROGRAM.CFG_PROGRAM 1 $cm
set_property PROGRAM.VERIFY 1 $cm
set_property PROGRAM.CHECKSUM 0 $cm
create_hw_bitstream -hw_device $dev [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]
program_hw_devices $dev
program_hw_cfgmem -hw_cfgmem $cm
puts "INFO: flash programmed — power-cycle the board"
