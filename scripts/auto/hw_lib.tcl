# hw_lib.tcl — JTAG stand-in for host/netsec.py.
# Every proc prints lines that start with RESULT:, PASS: or FAIL:.
set _hwlib_dir [file dirname [info script]]
source [file normalize [file join $_hwlib_dir .. hw_regs.tcl]]

# Counter names. 10G index = port*32+k, 1G index = port*16+k.
set NS_S10 {mac_rx_frames mac_rx_bad_fcs mac_rx_bad_frame mac_tx_frames mac_tx_underflow \
            rxfifo_drop rxfifo_overflow dp_rx dp_tx dp_forward dp_drop dp_mirror dp_dpi_hit}
set NS_S1G {mac_rx_good rx_bad_frame rx_bad_fcs rx_overflow mac_tx_good tx_underflow \
            dp_rx dp_tx dp_forward dp_drop dp_mirror dp_dpi_hit}

proc ns_stats {bank {nonzero 0}} {
    if {$bank eq "10g"} {
        set names $::NS_S10
        set stride 32
        set ports 4
    } else {
        set names $::NS_S1G
        set stride 16
        set ports 2
    }
    for {set p 0} {$p < $ports} {incr p} {
        for {set k 0} {$k < [llength $names]} {incr k} {
            set v [ns_stat $bank [expr {$p*$stride + $k}]]
            if {$nonzero && $v == 0} continue
            puts [format "RESULT: stat %s p%d %s = %u" $bank $p [lindex $names $k] $v]
        }
    }
}

# secs may be fractional. Frames circulate A->B->A while CU_MODE is BRIDGE.
proc ns_cu_wire {secs} {
    ns_wr 0x200 1
    ns_stat_clr
    set dpi0 [ns_stat 1g 11]
    set dpi1 [ns_stat 1g [expr {16+11}]]
    ns_wr 0x204 0x100
    after [expr {int($secs * 1000)}]
    ns_wr 0x200 3
    set ga [ns_stat 1g 0]
    set ba [ns_stat 1g 1]
    set fa [ns_stat 1g 2]
    set gb [ns_stat 1g 16]
    set bb [ns_stat 1g 17]
    set fb [ns_stat 1g 18]
    set da [expr {[ns_stat 1g 11] - $dpi0}]
    set db [expr {[ns_stat 1g [expr {16+11}]] - $dpi1}]
    puts [format "RESULT: CU_WIRE secs=%s A good=%u bad_frame=%u bad_fcs=%u dpi_hit=%d  B good=%u bad_frame=%u bad_fcs=%u dpi_hit=%d" \
        $secs $ga $ba $fa $da $gb $bb $fb $db]
    set ok [expr {$ga > 0 && $gb > 0 && $ba == 0 && $bb == 0 && $fa == 0 && $fb == 0 && $da > 0 && $db > 0}]
    if {$ok} { puts "PASS: copper cable loopback" } else { puts "FAIL: copper cable loopback" }
    return $ok
}

# Longest contiguous run of taps with frames and no errors. Writes the midpoint.
proc ns_rx_delay_scan {port} {
    if {$port eq "a" || $port eq "A"} { set addr 0x220; set tag A; set which 0 } else { set addr 0x224; set tag B; set which 1 }
    set good {}
    for {set tap 0} {$tap < 32} {incr tap} {
        ns_wr $addr [expr {$tap | 0x100}]
        after 20
        ns_wr 0x200 1
        ns_stat_clr
        ns_wr 0x204 0x100
        after 300
        ns_wr 0x200 3
        set base [expr {$which * 16}]
        set g [ns_stat 1g $base]
        set bf [ns_stat 1g [expr {$base+1}]]
        set fcs [ns_stat 1g [expr {$base+2}]]
        set ok [expr {$g > 0 && $bf == 0 && $fcs == 0}]
        puts [format "RESULT: RX_SCAN %s tap=%d good=%u bad_frame=%u bad_fcs=%u %s" $tag $tap $g $bf $fcs [expr {$ok ? "clean" : "bad"}]]
        lappend good $ok
    }
    set best_a -1
    set best_b -1
    set best_len 0
    set run_a -1
    for {set tap 0} {$tap <= 32} {incr tap} {
        set ok [expr {$tap < 32 && [lindex $good $tap]}]
        if {$ok} {
            if {$run_a < 0} { set run_a $tap }
        } elseif {$run_a >= 0} {
            set run_b [expr {$tap - 1}]
            set len [expr {$run_b - $run_a + 1}]
            if {$len > $best_len} { set best_len $len; set best_a $run_a; set best_b $run_b }
            set run_a -1
        }
    }
    if {$best_len == 0} {
        puts "FAIL: RX_TAP_$tag no clean window"
        return -1
    }
    set mid [expr {($best_a + $best_b) / 2}]
    ns_wr $addr [expr {$mid | 0x100}]
    puts [format "RESULT: RX_TAP_%s=%d window=%d..%d" $tag $mid $best_a $best_b]
    puts "PASS: RX_TAP_$tag"
    return $mid
}

proc ns_g10_map {} {
    ns_wr 0x100 3
    ns_wr 0x104 0xF
    ns_wr 0x114 0
    set links {}
    for {set p 0} {$p < 4} {incr p} {
        ns_wr 0x10C 0
        ns_stat_clr
        ns_wr 0x10C [expr {1 << $p}]
        after 200
        ns_wr 0x10C 0
        set tx [ns_stat 10g [expr {$p*32 + 3}]]
        set dest -1
        for {set q 0} {$q < 4} {incr q} {
            set rx [ns_stat 10g [expr {$q*32 + 0}]]
            set fcs [ns_stat 10g [expr {$q*32 + 1}]]
            puts [format "RESULT: G10_MAP src=%d tx=%u dst=%d rx=%u bad_fcs=%u" $p $tx $q $rx $fcs]
            if {$tx > 0 && $rx == $tx && $fcs == 0} { set dest $q }
        }
        if {$dest < 0} {
            puts "FAIL: G10_LINK $p has no intact receiver"
        } else {
            puts "RESULT: G10_LINK $p->$dest"
            puts "PASS: G10_LINK $p->$dest"
        }
        lappend links $dest
    }
    ns_wr 0x100 0
    return $links
}

proc ns_g10_circulate {secs} {
    ns_wr 0x100 2
    ns_wr 0x104 0xF
    ns_wr 0x114 0x2
    ns_stat_clr
    ns_wr 0x118 0xF
    after [expr {int($secs * 1000)}]
    set bad 0
    set circ 1
    set mirrored 1
    for {set p 0} {$p < 4} {incr p} {
        set b [expr {$p*32}]
        set rx [ns_stat 10g [expr {$b+7}]]
        set hit [ns_stat 10g [expr {$b+12}]]
        set mir [ns_stat 10g [expr {$b+11}]]
        set fcs [ns_stat 10g [expr {$b+1}]]
        puts [format "RESULT: G10_LOOP p%d dp_rx=%u dp_dpi_hit=%u dp_mirror=%u mac_rx_bad_fcs=%u" $p $rx $hit $mir $fcs]
        if {$fcs != 0} { set bad 1 }
        if {$rx < 2} { set circ 0 }
        if {$hit < 1 || $mir < 1} { set mirrored 0 }
    }
    ns_wr 0x100 0
    ns_wr 0x114 0
    if {!$bad && $circ && $mirrored} { puts "PASS: G10 loop circulate" } else { puts "FAIL: G10 loop circulate" }
    return [expr {!$bad && $circ && $mirrored}]
}

# 8 beats x 8 bytes, see rtl/core/pkt_gen_10g.sv.
set NS_G10_FRAME_BYTES 64

proc ns_perf_sweep {} {
    set gaps {0 4 8 16 32 64}
    ns_wr 0x100 3
    ns_wr 0x104 0xF
    ns_wr 0x114 0
    set rows {}
    foreach g $gaps {
        ns_wr 0x110 $g
        for {set p 0} {$p < 4} {incr p} {
            ns_wr 0x10C 0
            ns_stat_clr
            ns_wr 0x10C [expr {1 << $p}]
            after 5000
            set tx [ns_stat 10g [expr {$p*32 + 3}]]
            ns_wr 0x10C 0
            set gbps [expr {$tx * $::NS_G10_FRAME_BYTES * 8.0 / 5.0 / 1.0e9}]
            puts [format "RESULT: PERF gap=%d port=%d frames=%u Gbps=%.3f" $g $p $tx $gbps]
            lappend rows [list $g $p $tx $gbps]
        }
    }
    ns_wr 0x110 0
    ns_stat_clr
    ns_wr 0x10C 0xF
    after 5000
    ns_wr 0x10C 0
    for {set p 0} {$p < 4} {incr p} {
        set tx [ns_stat 10g [expr {$p*32 + 3}]]
        set gbps [expr {$tx * $::NS_G10_FRAME_BYTES * 8.0 / 5.0 / 1.0e9}]
        puts [format "RESULT: PERF gap=0 port=%d concurrent frames=%u Gbps=%.3f" $p $tx $gbps]
        lappend rows [list 0 "c$p" $tx $gbps]
    }
    ns_wr 0x100 0
    set md [file normalize [file join $::_hwlib_dir .. .. build logs perf.md]]
    file mkdir [file dirname $md]
    set fh [open $md w]
    puts $fh "# 10G BIST, 64-byte frames, 5 s per point"
    puts $fh ""
    puts $fh "| gap | port | frames | Gb/s |"
    puts $fh "| ---: | ---: | ---: | ---: |"
    foreach r $rows {
        puts $fh [format "| %s | %s | %u | %.3f |" [lindex $r 0] [lindex $r 1] [lindex $r 2] [lindex $r 3]]
    }
    close $fh
    puts "RESULT: PERF wrote $md"
    return $rows
}
