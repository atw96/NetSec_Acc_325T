# g5_check.tcl — selftest, discovered 10G topology, loop circulation.
# INLINE is recorded and is not a pass/fail gate.
source [file join [file dirname [info script]] hw_lib.tcl]
ns_open
set f [ns_selftest]
puts "RESULT: SELFTEST_FAILS=$f"
if {$f == 0} { puts "PASS: selftest" } else { puts "FAIL: selftest" }
ns_g10_map
ns_g10_circulate 2
ns_wr 0x100 1
after 200
ns_stats 10g 1
ns_wr 0x100 0
puts "RESULT: INLINE recorded, not gated"
exit 0
