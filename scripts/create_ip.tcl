# create_ip.tcl — creates the three IP cores used by netsec_k7_top.
#   jtag_axi_0              JTAG-to-AXI4-Lite master (Vivado hw_axi access to the register file)
#   ten_gig_eth_pcs_pma_0   10GBASE-R PCS/PMA, SupportLevel=1 (QPLL + clocking + reset in core)  -> SFP A
#   ten_gig_eth_pcs_pma_1   10GBASE-R PCS/PMA, SupportLevel=0                                      -> SFP B,C,D
# Expects (set by create_project.tcl): ::enable_10g, ::gt_refclk (1 = patch shared logic to MGTREFCLK1)
# After generation it verifies the instantiation ports of every IP against the names used in the RTL, so a
# Vivado-version difference is reported here with a precise message instead of as an elaboration error.

proc ns_ip_ports {ip_name} {
    set veo [get_files -all -quiet "${ip_name}.veo"]
    if {$veo eq ""} { return {} }
    set fh [open [lindex $veo 0] r]; set txt [read $fh]; close $fh
    set ports {}
    foreach {all p} [regexp -all -inline {\.([A-Za-z0-9_]+)\s*\(} $txt] { lappend ports $p }
    return [lsort -unique $ports]
}

proc ns_check_ports {ip_name expected} {
    set got [ns_ip_ports $ip_name]
    if {[llength $got] == 0} { puts "WARNING: no .veo found for $ip_name, port check skipped"; return }
    set missing {}; set extra {}
    foreach p $expected { if {[lsearch -exact $got $p] < 0} { lappend missing $p } }
    foreach p $got      { if {[lsearch -exact $expected $p] < 0} { lappend extra $p } }
    if {[llength $missing] || [llength $extra]} {
        puts "ERROR: port mismatch for $ip_name"
        puts "  used by RTL but not on the IP : $missing"
        puts "  on the IP but not used by RTL : $extra"
        puts "  -> adapt rtl/mac/gt10g_quad.sv (or rtl/top/netsec_k7_top.sv for jtag_axi) to this Vivado version."
        error "IP port check failed for $ip_name"
    }
    puts "INFO: $ip_name port list matches the RTL ([llength $got] ports)"
}

# ---------------- JTAG-to-AXI ----------------
create_ip -name jtag_axi -vendor xilinx.com -library ip -module_name jtag_axi_0
set_property -dict [list CONFIG.PROTOCOL {2} CONFIG.M_AXI_ADDR_WIDTH {32} CONFIG.M_AXI_DATA_WIDTH {32}] [get_ips jtag_axi_0]
if {[get_property CONFIG.PROTOCOL [get_ips jtag_axi_0]] ne "2"} {
    error "jtag_axi_0: AXI4-Lite protocol (CONFIG.PROTOCOL=2) was not accepted by this Vivado version"
}

# ---------------- 10GBASE-R PCS/PMA ----------------
if {$::enable_10g} {
    create_ip -name ten_gig_eth_pcs_pma -vendor xilinx.com -library ip -module_name ten_gig_eth_pcs_pma_0
    set_property -dict [list CONFIG.MDIO_Management {false} CONFIG.base_kr {BASE-R} \
                             CONFIG.SupportLevel {1} CONFIG.DClkRate {125}] [get_ips ten_gig_eth_pcs_pma_0]
    create_ip -name ten_gig_eth_pcs_pma -vendor xilinx.com -library ip -module_name ten_gig_eth_pcs_pma_1
    set_property -dict [list CONFIG.MDIO_Management {false} CONFIG.base_kr {BASE-R} \
                             CONFIG.SupportLevel {0} CONFIG.DClkRate {125}] [get_ips ten_gig_eth_pcs_pma_1]
}

# global (not out-of-context) synthesis so that the patched shared-logic file below is what gets synthesised
foreach ip [get_ips] {
    set_property generate_synth_checkpoint false [get_files [get_property IP_FILE $ip]]
}
generate_target {instantiation_template synthesis simulation} [get_ips]

ns_check_ports jtag_axi_0 {aclk aresetn m_axi_awaddr m_axi_awprot m_axi_awvalid m_axi_awready m_axi_wdata m_axi_wstrb m_axi_wvalid m_axi_wready m_axi_bresp m_axi_bvalid m_axi_bready m_axi_araddr m_axi_arprot m_axi_arvalid m_axi_arready m_axi_rdata m_axi_rresp m_axi_rvalid m_axi_rready}
if {$::enable_10g} {
    ns_check_ports ten_gig_eth_pcs_pma_0 {dclk rxrecclk_out refclk_p refclk_n sim_speedup_control coreclk_out qplloutclk_out qplloutrefclk_out qplllock_out txusrclk_out txusrclk2_out areset_datapathclk_out gttxreset_out gtrxreset_out txuserrdy_out reset_counter_done_out reset xgmii_txd xgmii_txc xgmii_rxd xgmii_rxc txp txn rxp rxn configuration_vector status_vector core_status resetdone_out signal_detect tx_fault drp_req drp_gnt drp_den_o drp_dwe_o drp_daddr_o drp_di_o drp_drdy_o drp_drpdo_o drp_den_i drp_dwe_i drp_daddr_i drp_di_i drp_drdy_i drp_drpdo_i pma_pmd_type tx_disable}
    ns_check_ports ten_gig_eth_pcs_pma_1 {dclk rxrecclk_out coreclk txusrclk txusrclk2 txoutclk areset areset_coreclk gttxreset gtrxreset sim_speedup_control txuserrdy qplllock qplloutclk qplloutrefclk reset_counter_done xgmii_txd xgmii_txc xgmii_rxd xgmii_rxc txp txn rxp rxn configuration_vector status_vector core_status tx_resetdone rx_resetdone signal_detect tx_fault drp_req drp_gnt drp_den_o drp_dwe_o drp_daddr_o drp_di_o drp_drdy_o drp_drpdo_o drp_den_i drp_dwe_i drp_daddr_i drp_di_i drp_drdy_i drp_drpdo_i pma_pmd_type tx_disable}
    if {$::gt_refclk == 1} {
        source [file join $::netsec_root scripts patch_gt_refclk.tcl]
        ns_patch_gt_refclk ten_gig_eth_pcs_pma_0
    }
}
