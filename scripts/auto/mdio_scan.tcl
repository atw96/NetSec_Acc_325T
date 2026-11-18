# Scan PHY addresses 0..31 on both MDIO ports. Register 2 is PHYID1 (RTL8211F = 0x001C).
set here [file dirname [file normalize [info script]]]
source [file join $here .. hw_regs.tcl]
ns_open
puts [format "PHY_CTRL=0x%08x PHY_STATUS=0x%08x" [ns_rd 0x228] [ns_rd 0x22C]]
proc mdio_rd {port phy reg} {
    ns_wr 0x214 [expr {($reg & 0x1F) | (($phy & 0x1F) << 8)}]
    ns_wr 0x210 [expr {($port << 2) | (1 << 9) | (1 << 3) | 1}]
    for {set i 0} {$i < 200} {incr i} {
        if {[ns_rd 0x210] & 0x200} break
        after 2
    }
    return [ns_rd 0x21C]
}
for {set phy 0} {$phy < 32} {incr phy} {
    set a [mdio_rd 0 $phy 2]
    set b [mdio_rd 1 $phy 2]
    puts [format "PHY %2d  A=0x%04x  B=0x%04x" $phy [expr {$a & 0xFFFF}] [expr {$b & 0xFFFF}]]
}
puts [format "REG3 A(addr2)=0x%04x B(addr1)=0x%04x" [expr {[mdio_rd 0 2 3] & 0xFFFF}] [expr {[mdio_rd 1 1 3] & 0xFFFF}]]
exit 0
