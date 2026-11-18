# create_project.tcl — builds the Vivado project for the MK7325FB NetSec accelerator.
#
#   vivado -mode batch -source scripts/create_project.tcl
#
# Environment variables (all optional):
#   NETSEC_10G      1 (default) | 0   : include the 4x10G GTX/PCS/PMA path; 0 builds the 2xRJ45 design only
#   NETSEC_REFCLK   1 (default) | 0   : 1 = refclk on MGTREFCLK1 (stock board, patch shared logic), 0 = MGTREFCLK0
#   NETSEC_PART     xc7k325tffg900-2
#   NETSEC_HASH_BITS (10) NETSEC_AES_LANES (1) NETSEC_AES_PIPE (1; 0 = small iterative AES core) NETSEC_USE_CLK90_A/B (FALSE)
#   NETSEC_UART_SWAP  1 | 0 (default) : also load constraints/k7325fb_uart_swap.xdc (LATE) if the CP2104 pair is reversed
#   NETSEC_RX_DLY_A/B (0) : IDELAY tap loaded at reset, so a flash boot needs no register write
set here [file dirname [file normalize [info script]]]
set ::netsec_root [file normalize [file join $here ..]]
proc env_or {n d} { if {[info exists ::env($n)]} { return $::env($n) } else { return $d } }

set part       [env_or NETSEC_PART xc7k325tffg900-2]
set ::enable_10g [env_or NETSEC_10G 1]
set ::gt_refclk  [env_or NETSEC_REFCLK 1]
set hash_bits  [env_or NETSEC_HASH_BITS 10]
set aes_lanes  [env_or NETSEC_AES_LANES 1]
set aes_pipe   [env_or NETSEC_AES_PIPE 1]
set clk90_a    [env_or NETSEC_USE_CLK90_A FALSE]
set clk90_b    [env_or NETSEC_USE_CLK90_B FALSE]
set rx_dly_a   [env_or NETSEC_RX_DLY_A 0]
set rx_dly_b   [env_or NETSEC_RX_DLY_B 0]
set projdir    [file join $::netsec_root build proj]

file mkdir $projdir
create_project -force netsec_k7 $projdir -part $part
set_property target_language Verilog [current_project]
set_property default_lib xil_defaultlib [current_project]

# ---- sources ----
set fh [open [file join $here filelist.f] r]
set srcs {}
foreach line [split [read $fh] "\n"] {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} continue
    lappend srcs [file join $::netsec_root $line]
}
close $fh
add_files -norecurse $srcs
set_property file_type SystemVerilog [get_files -filter {NAME =~ *.sv}]
add_files -fileset constrs_1 -norecurse [file join $::netsec_root constraints k7325fb_pins.xdc] \
                                          [file join $::netsec_root constraints k7325fb_timing.xdc]
if {$::enable_10g eq "0"} {
    set nf [file join $::netsec_root constraints k7325fb_no10g.xdc]
    add_files -fileset constrs_1 -norecurse $nf
    puts "INFO: 10G disabled — GT pads unbuffered (k7325fb_no10g.xdc)"
}
set uart_swap [env_or NETSEC_UART_SWAP 0]
if {$uart_swap eq "1"} {
    set uf [file join $::netsec_root constraints k7325fb_uart_swap.xdc]
    add_files -fileset constrs_1 -norecurse $uf
    set_property PROCESSING_ORDER LATE [get_files $uf]
    puts "INFO: UART pin swap enabled (k7325fb_uart_swap.xdc)"
}
set_property top netsec_k7_top [current_fileset]

# ---- IP ----
source [file join $here create_ip.tcl]

# ---- generics ----
set gen [list ENABLE_10G=$::enable_10g HASH_BITS=$hash_bits AES_LANES=$aes_lanes AES_PIPE=$aes_pipe \
              USE_CLK90_A=\"$clk90_a\" USE_CLK90_B=\"$clk90_b\" RX_DLY_A=$rx_dly_a RX_DLY_B=$rx_dly_b]
set_property generic $gen [current_fileset]

set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraTimingOpt [get_runs impl_1]
update_compile_order -fileset sources_1
puts "INFO: project created in $projdir (10G=$::enable_10g refclk=MGTREFCLK$::gt_refclk)"
