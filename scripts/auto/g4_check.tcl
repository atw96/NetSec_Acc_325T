# g4_check.tcl — 10G clock and link. One reset + laser retry if nothing locks.
source [file join [file dirname [info script]] hw_lib.tcl]
ns_open

proc g4_read {} {
    set s [ns_rd 0x010]
    set g [ns_rd 0x120]
    set qpll [expr {($s >> 1) & 1}]
    set rst156 [expr {($s >> 8) & 1}]
    set done [expr {($g >> 8) & 0xF}]
    set lock [expr {$g & 0xF}]
    puts [format "RESULT: G4 qpll=%d resetdone=0x%X rst156_ok=%d block_lock=0x%X" $qpll $done $rst156 $lock]
    return [list $qpll $done $rst156 $lock]
}

lassign [g4_read] qpll done rst156 lock
if {$lock == 0} {
    puts "RESULT: G4 no block_lock, pulsing GT reset and enabling lasers"
    ns_wr 0x12C 1
    after 200
    ns_wr 0x11C 0xFF00
    after 500
    lassign [g4_read] qpll done rst156 lock
}
if {$qpll == 1 && $done == 0xF && $rst156 == 1} { puts "PASS: G4 clock and reset" } else { puts "FAIL: G4 clock and reset" }
if {$lock != 0} { puts "PASS: G4 block_lock $lock" } else { puts "FAIL: G4 block_lock" }
exit 0
