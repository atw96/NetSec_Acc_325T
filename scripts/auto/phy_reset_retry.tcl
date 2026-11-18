# Pulse the shared PHY reset (PHY_CTRL[0]) and re-read PHYID1 at the default addresses.
set here [file dirname [file normalize [info script]]]
source [file join $here .. hw_regs.tcl]
ns_open
puts "before [format 0x%08x [ns_rd 0x230]] [format 0x%08x [ns_rd 0x234]]"
ns_wr 0x228 0x1
after 100
ns_wr 0x228 0x2
after 500
puts "after  [format 0x%08x [ns_rd 0x230]] [format 0x%08x [ns_rd 0x234]] status=[format 0x%08x [ns_rd 0x010]]"
exit 0
