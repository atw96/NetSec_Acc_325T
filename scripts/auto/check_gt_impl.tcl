# check_gt_impl.tcl — open the implemented design and print GTX placement.
#   vivado -mode batch -source scripts/auto/check_gt_impl.tcl
set here [file dirname [file normalize [info script]]]
set root [file normalize [file join $here .. ..]]
open_project [file join $root build proj netsec_k7.xpr]
open_run impl_1
source [file join $root scripts check_gt_loc.tcl]
exit 0
