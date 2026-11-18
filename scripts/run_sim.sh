#!/usr/bin/env bash
# run_sim.sh — regression of everything that can be simulated without Xilinx libraries (Icarus Verilog >= 11).
#   scripts/run_sim.sh            run all
#   scripts/run_sim.sh ctrl       run one (dp64 fabric10g sys10g fabric1g ctrl elab)
set -u
cd "$(dirname "$0")/.."
V=rtl/third_party/verilog-ethernet; C=rtl/core; X=rtl/crypto
mkdir -p build/sim
fail=0
run() {                       # run <name> <top> <files...>
    local name=$1 top=$2; shift 2
    printf '%-10s ' "$name"
    if ! iverilog -g2012 -s "$top" -o build/sim/$name.vvp "$@" >build/sim/$name.log 2>&1; then echo "COMPILE ERROR (build/sim/$name.log)"; fail=1; return; fi
    local out; out=$(timeout 900 vvp build/sim/$name.vvp 2>&1)
    echo "$out" > build/sim/$name.out
    local np nf; np=$(grep -c '^PASS' <<<"$out"); nf=$(grep -c '^FAIL' <<<"$out")
    if [ "$nf" -eq 0 ] && [ "$np" -gt 0 ]; then echo "PASS ($np checks)"; else echo "FAIL ($nf failed, $np passed) -> build/sim/$name.out"; fail=1; fi
}
want() { [ $# -eq 0 ] || [ "$SEL" = all ] || [ "$SEL" = "$1" ]; }
SEL=${1:-all}
DP="$X/aes_sbox_pkg.sv $X/aes128_pipe.sv $X/aes128_core.sv $C/flow_table_bram.sv $C/dpi_match64.sv $C/ips_decision.sv $C/dp_delay_pipe.sv $C/netsec_dp64.sv"
FIFO="$V/lib/axis/rtl/axis_fifo.v $V/lib/axis/rtl/axis_async_fifo.v"
[ "$SEL" = all -o "$SEL" = dp64 ]      && run dp64      tb_dp64      $DP $FIFO tb/tb_dp64.sv
[ "$SEL" = all -o "$SEL" = fabric10g ] && run fabric10g tb_fabric10g $DP $FIFO $C/pkt_gen_10g.sv $C/pkt_gen_inj64.sv rtl/fabric/netsec_fabric10g.sv tb/tb_fabric10g.sv
[ "$SEL" = all -o "$SEL" = sys10g ]    && run sys10g    tb_sys10g    $DP $FIFO $C/pkt_gen_10g.sv $C/pkt_gen_inj64.sv rtl/fabric/netsec_fabric10g.sv rtl/mac/mac10g_port.sv $V/rtl/eth_mac_10g.v $V/rtl/axis_xgmii_rx_64.v $V/rtl/axis_xgmii_tx_64.v $V/rtl/lfsr.v tb/tb_sys10g.sv
[ "$SEL" = all -o "$SEL" = fabric1g ]  && run fabric1g  tb_fabric1g  $X/aes_sbox_pkg.sv $X/aes128_core.sv $C/packet_parser.sv $C/flow_table.sv $C/dpi_matcher.sv $C/ips_decision.sv $C/sync_fifo.sv $C/checksum_rfc1071.sv $C/pkt_gen_bram.sv $C/netsec_datapath.sv rtl/fabric/netsec_fabric1g.sv tb/tb_fabric1g.sv
[ "$SEL" = all -o "$SEL" = ctrl ]      && run ctrl      tb_ctrl      rtl/ctrl/netsec_regs_k7.sv rtl/ctrl/uart_axil_bridge.sv rtl/ctrl/stat_bank.sv rtl/ctrl/phy_mgmt.sv $C/mdio_master.sv $X/aes_sbox_pkg.sv $X/aes128_core.sv $C/checksum_rfc1071.sv $X/modexp_demo.sv tb/tb_ctrl.sv
if [ "$SEL" = all -o "$SEL" = elab ]; then
    FILES=$(grep -v '^#' scripts/filelist.f | grep -v '^$' | tr '\n' ' ')
    for g in 1 0; do
        printf '%-10s ' "elab10g=$g"
        if iverilog -g2012 -tnull -s netsec_k7_top -P netsec_k7_top.ENABLE_10G=$g tb/stubs/xilinx_stubs.v $FILES >build/sim/elab$g.log 2>&1; then echo "OK (top elaborates against port-accurate Xilinx stubs)"; else echo "ERROR (build/sim/elab$g.log)"; fail=1; fi
    done
fi
exit $fail
