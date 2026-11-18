# patch_gt_refclk.tcl — make the 10GBASE-R shared logic use MGTREFCLK1 instead of MGTREFCLK0.
#
# Why: on the MK7325FB the CDCM61002 (156.25 MHz when SW4 selects the 10GigE row) is wired to
# MGTREFCLK1 of GTX quad 118 (pins E8/E7). The generated shared logic of ten_gig_eth_pcs_pma
# (SupportLevel=1) connects its IBUFDS_GTE2 output to GTREFCLK0 of the GTXE2_COMMON and selects it
# with QPLLREFCLKSEL = 3'b001. We swap GTREFCLK0 <-> GTREFCLK1 and select 3'b010.
#
# The script only edits files that contain a GTXE2_COMMON instantiation and prints every change.
# If it reports 0 substitutions, inspect the generated file by hand (see docs/risks.md R1).
proc ns_rglob {dir} {
    set out {}
    foreach f [glob -nocomplain -directory $dir -types f *] { lappend out $f }
    foreach d [glob -nocomplain -directory $dir -types d *] { set out [concat $out [ns_rglob $d]] }
    return $out
}

proc ns_patch_gt_refclk {ip_name} {
    set ip   [get_ips $ip_name]
    set dir  [file dirname [get_property IP_FILE $ip]]
    set nfiles 0; set ntotal 0
    foreach f [ns_rglob $dir] {
        if {![regexp {\.(v|sv|vhd)$} $f]} continue
        set fh [open $f r]; set txt [read $fh]; close $fh
        if {![regexp {GTXE2_COMMON} $txt]} continue
        if {[regexp {GTXE2_CHANNEL} $txt]} {
            puts "WARNING: $f has both GTXE2_COMMON and GTXE2_CHANNEL, skipping (patch the COMMON connection by hand)"
            continue
        }
        set n 0
        # swap the two reference-clock connections of the GTXE2_COMMON
        set re0 {\.GTREFCLK0\s*\(\s*([^()]*?)\s*\)}
        set re1 {\.GTREFCLK1\s*\(\s*([^()]*?)\s*\)}
        if {[regexp $re0 $txt -> e0] && [regexp $re1 $txt -> e1]} {
            regsub $re0 $txt ".GTREFCLK0 (\u0001TMP0\u0001)" txt
            regsub $re1 $txt ".GTREFCLK1 ($e0)" txt
            regsub {\u0001TMP0\u0001} $txt $e1 txt
            incr n 2
        }
        incr n [regsub -all {QPLLREFCLKSEL\s*\(\s*3'b001\s*\)}      $txt {QPLLREFCLKSEL(3'b010)}      txt]
        incr n [regsub -all {SIM_QPLLREFCLK_SEL\s*\(\s*3'b001\s*\)} $txt {SIM_QPLLREFCLK_SEL(3'b010)} txt]
        if {$n > 0} {
            catch {file attributes $f -readonly 0}
            catch {file attributes $f -permissions 0644}
            set fh [open $f w]; puts -nonewline $fh $txt; close $fh
            puts "INFO: patched $f ($n substitutions)"
            incr nfiles; incr ntotal $n
        } else {
            puts "WARNING: $f contains GTXE2_COMMON but none of the expected patterns matched"
        }
    }
    if {$ntotal == 0} {
        puts "ERROR: patch_gt_refclk found nothing to patch under $dir."
        puts "       Open the generated *_gt_common.v / *_support.v, make GTREFCLK1 (not GTREFCLK0) carry the"
        puts "       IBUFDS_GTE2 output and set QPLLREFCLKSEL to 3'b010, or re-run with NETSEC_REFCLK=0 if the"
        puts "       156.25 MHz clock is on MGTREFCLK0 (Si570 populated)."
        error "GT refclk patch failed"
    }
    puts "INFO: GT refclk patch done: $nfiles file(s), $ntotal substitution(s)"
}
