# check_gt_loc.tcl — run on the *synthesised or implemented* design to confirm which GTX site each SFP+ port landed on
# and that the reference clock pins belong to the same quad.
#   vivado -mode batch -source scripts/check_gt_loc.tcl   (after build) or  source it in the Tcl console
set pins {E4 E3 D2 D1 D6 D5 C4 C3 B6 B5 B2 B1 A8 A7 A4 A3 E8 E7}
foreach p $pins {
    set pk [get_package_pins $p]
    puts [format "%-4s bank=%-4s site=%-24s func=%s" $p [get_property BANK $pk] [get_property SITE_NAME [get_sites -quiet -of_objects $pk]] [get_property PIN_FUNC $pk]]
}
puts "--- placed GT cells ---"
foreach c [get_cells -hier -filter {REF_NAME =~ GTXE2_CHANNEL || REF_NAME =~ GTXE2_COMMON || REF_NAME =~ IBUFDS_GTE2}] {
    puts [format "%-80s %-16s %s" $c [get_property REF_NAME $c] [get_property LOC $c]]
}
