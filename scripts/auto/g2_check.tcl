# g2_check.tcl — copper link, RX tap scan, cable loopback. Requires ns_open's target.
source [file join [file dirname [info script]] hw_lib.tcl]
ns_open
ns_status
set cu [ns_rd 0x208]
set link_a [expr {$cu & 1}]
set link_b [expr {($cu >> 1) & 1}]
set spd_a  [expr {($cu >> 2) & 3}]
set spd_b  [expr {($cu >> 4) & 3}]
puts [format "RESULT: CU_STATUS=0x%04x linkA=%d linkB=%d speedA=%d speedB=%d" $cu $link_a $link_b $spd_a $spd_b]
if {$link_a && $link_b && $spd_a == 2 && $spd_b == 2} {
    puts "PASS: both copper ports link at 1G"
} else {
    puts "FAIL: copper link or speed"
}
set ta [ns_rx_delay_scan a]
set tb [ns_rx_delay_scan b]
if {$ta >= 0 && $tb >= 0} { ns_cu_wire 5 }
puts [format "RESULT: NETSEC_RX_DLY_A=%d NETSEC_RX_DLY_B=%d" $ta $tb]
exit 0
