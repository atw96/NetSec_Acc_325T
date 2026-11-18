# Arm the MDIO ILA, let the 10 ms link poll provide edges, dump a CSV.
set root [file normalize [file join [file dirname [info script]] .. ..]]
set bit [file join $root build out_ila netsec_k7_ila.bit]
set ltx [file join $root build out_ila netsec_k7_ila.ltx]
source [file join $root scripts hw_regs.tcl]
ns_open
set dev [current_hw_device]
set_property PROGRAM.FILE $bit $dev
set_property PROBES.FILE $ltx $dev
program_hw_devices $dev
refresh_hw_device $dev
after 200
set ila [lindex [get_hw_ilas -of_objects $dev] 0]
puts "INFO: ILA $ila"
set_property CONTROL.DATA_DEPTH 8192 $ila
set_property CONTROL.TRIGGER_POSITION 256 $ila
foreach p [get_hw_probes -of_objects $ila] { puts "INFO: probe $p" }
set mdc_p [lindex [get_hw_probes -of_objects $ila] 0]
puts "INFO: trigger probe $mdc_p"
set_property TRIGGER_COMPARE_VALUE eq1'b1 $mdc_p
run_hw_ila $ila
wait_on_hw_ila $ila
set csv [file join $root build logs g1_mdio_ila.csv]
write_hw_ila_data -force -csv_file $csv [upload_hw_ila_data $ila]
puts "INFO: wrote $csv"
exit 0
