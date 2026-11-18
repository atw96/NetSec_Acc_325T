# hw_check.tcl — JTAG register self-test in batch mode.
#   vivado -mode batch -source scripts/auto/hw_check.tcl
# Prints SELFTEST_FAILS=<n> so a wrapper can grep the result.
set here [file dirname [file normalize [info script]]]
source [file join $here .. hw_regs.tcl]
ns_open
ns_status
set f [ns_selftest]
puts "SELFTEST_FAILS=$f"
if {$f != 0} { puts "WARNING: selftest reported $f failing check(s)" }
