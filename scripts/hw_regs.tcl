# hw_regs.tcl — register access and a quick self-test over JTAG (Vivado Hardware Manager, no UART needed).
#
#   vivado -mode tcl
#   source scripts/hw_regs.tcl ; ns_open ; ns_status ; ns_selftest
#
# All procs talk to the JTAG-to-AXI master in the design (axi_clk = 125 MHz, 32-bit, AXI4-Lite).
proc ns_open {} {
    open_hw_manager
    connect_hw_server -quiet
    set dev ""
    foreach t [get_hw_targets] {
        if {[current_hw_target -quiet] ne ""} { close_hw_target }
        open_hw_target -quiet $t
        set dev [lindex [get_hw_devices -quiet xc7k325t*] 0]
        if {$dev ne ""} { break }
        puts "INFO: skip $t (no xc7k325t)"
        set dev ""
    }
    if {$dev eq ""} { error "no xc7k325t on any JTAG target" }
    current_hw_device $dev
    refresh_hw_device -quiet $dev
    puts "INFO: JTAG [current_hw_target] device $dev"
    puts "hw_axi objects: [get_hw_axis]"
}
proc ns_axi {} { return [lindex [get_hw_axis] 0] }
proc ns_wr {addr val} {
    create_hw_axi_txn -force ns_wr_txn [ns_axi] -type write -address [format %08x $addr] -data [format %08x $val] -len 1
    run_hw_axi -quiet ns_wr_txn
    delete_hw_axi_txn ns_wr_txn
}
proc ns_rd {addr} {
    create_hw_axi_txn -force ns_rd_txn [ns_axi] -type read -address [format %08x $addr] -len 1
    run_hw_axi -quiet ns_rd_txn
    set d [get_property DATA [get_hw_axi_txns ns_rd_txn]]
    delete_hw_axi_txn ns_rd_txn
    return [expr {"0x$d"}]
}
# statistic counter: bank "10g" (index = port*32+k) or "1g" (index = port*16+k)
proc ns_stat {bank idx} {
    if {$bank eq "10g"} { set ctl 0x400; set val 0x404 } else { set ctl 0x410; set val 0x414 }
    ns_wr $ctl $idx
    for {set i 0} {$i < 50} {incr i} { if {[ns_rd $ctl] & 1} break }
    return [ns_rd $val]
}
proc ns_stat_clr {} { ns_wr 0x408 1; ns_wr 0x418 1; after 5 }

proc ns_status {} {
    puts [format "ID=0x%08x VERSION=0x%08x CONFIG=0x%08x uptime=%ds" [ns_rd 0x000] [ns_rd 0x004] [ns_rd 0x018] [ns_rd 0x014]]
    set s [ns_rd 0x010]
    puts [format "STATUS=0x%04x  mmcm=%d qpll=%d gt_rdy=%d linkA=%d linkB=%d idlyctrl=%d phyA_init=%d phyB_init=%d rst156_ok=%d" \
        $s [expr {$s&1}] [expr {($s>>1)&1}] [expr {($s>>2)&1}] [expr {($s>>3)&1}] [expr {($s>>4)&1}] [expr {($s>>5)&1}] \
        [expr {($s>>6)&1}] [expr {($s>>7)&1}] [expr {($s>>8)&1}]]
    set g [ns_rd 0x120]
    puts [format "10G: block_lock=0x%x core_status=0x%x resetdone=0x%x   PHY IDs: A=0x%04x B=0x%04x" \
        [expr {$g&0xF}] [expr {($g>>4)&0xF}] [expr {($g>>8)&0xF}] [ns_rd 0x230] [ns_rd 0x234]]
}

proc ns__chk {name cond} {
    if {$cond} { puts "PASS: $name"; return 0 } else { puts "FAIL: $name"; return 1 }
}
proc ns_selftest {} {
    set f 0
    incr f [ns__chk "ID = K725" [expr {[ns_rd 0x000] == 0x4B373235}]]
    ns_wr 0x00C 0xA5A55A5A
    incr f [ns__chk "scratch write/read" [expr {[ns_rd 0x00C] == 0xA5A55A5A}]]
    set s [ns_rd 0x010]
    incr f [ns__chk "MMCM locked + IDELAYCTRL ready" [expr {($s & 0x21) == 0x21}]]
    set u0 [ns_rd 0x014]; after 1200; set u1 [ns_rd 0x014]
    incr f [ns__chk "uptime counter runs" [expr {$u1 > $u0}]]
    incr f [ns__chk "PHY A ID1 = 0x001C" [expr {[ns_rd 0x230] == 0x001C}]]
    incr f [ns__chk "PHY B ID1 = 0x001C" [expr {[ns_rd 0x234] == 0x001C}]]
    # AES FIPS-197 C.1 via MMIO engine
    foreach {a v} {0x130 0x00010203 0x134 0x04050607 0x138 0x08090A0B 0x13C 0x0C0D0E0F \
                   0x310 0x00112233 0x314 0x44556677 0x318 0x8899AABB 0x31C 0xCCDDEEFF} { ns_wr $a $v }
    ns_wr 0x300 1; after 20
    incr f [ns__chk "AES-128 FIPS-197 vector (MMIO)" [expr {[ns_rd 0x320] == 0x69C4E0D8 && [ns_rd 0x32C] == 0x70B4C55A}]]
    # modexp
    ns_wr 0x340 7; ns_wr 0x344 13; ns_wr 0x348 101; ns_wr 0x300 4; after 20
    incr f [ns__chk "modexp 7^13 mod 101 = 75" [expr {[ns_rd 0x34C] == 75}]]
    # 10G: GT clocking
    incr f [ns__chk "QPLL locked (156.25 MHz refclk present)" [expr {([ns_rd 0x010] >> 1) & 1}]]
    incr f [ns__chk "all four GTX channels out of reset" [expr {(([ns_rd 0x120] >> 8) & 0xF) == 0xF}]]
    # 10G inspection engine without cables: injector -> dp -> LOOP -> MAC (SFP lasers disabled)
    ns_wr 0x11C 0x000F          ;# tx_disable = all (RS bits cleared too: restore below)
    ns_wr 0x100 2               ;# LOOP
    ns_wr 0x104 0xF
    ns_wr 0x114 0               ;# inject into dp, not into the MAC
    ns_stat_clr
    ns_wr 0x118 0xF
    after 50
    for {set p 0} {$p < 4} {incr p} {
        set b [expr {$p*32}]
        incr f [ns__chk "10G port $p: inj -> 2 frames inspected, 1 DPI hit, 1 mirrored" \
            [expr {[ns_stat 10g [expr {$b+7}]] == 2 && [ns_stat 10g [expr {$b+12}]] == 1 && [ns_stat 10g [expr {$b+11}]] == 1}]]
    }
    ns_wr 0x100 0; ns_wr 0x11C 0xFF00   ;# disable, SFP lasers on again, RS0/RS1 = full bandwidth
    # copper L0
    ns_wr 0x200 2; ns_stat_clr; ns_wr 0x204 0x100; after 50
    for {set p 0} {$p < 2} {incr p} {
        incr f [ns__chk "copper port $p: L0 generator -> 2 inspected, 1 DPI hit" \
            [expr {[ns_stat 1g [expr {$p*16+6}]] == 2 && [ns_stat 1g [expr {$p*16+11}]] == 1}]]
    }
    ns_wr 0x200 3
    puts [expr {$f == 0 ? "SELFTEST PASSED" : "SELFTEST FAILED ($f)"}]
    return $f
}
