# NetSec_Acc_K7325FB 部署到 米联客 MK7325FB 的自动化计划（供 Grok 执行）

本文件是可执行部署规程。命令都在工程根目录执行。背景见 [PLAN.md](PLAN.md)、[bringup.md](bringup.md)、[risks.md](risks.md)。

## 0. 约定

- 以下命令都在工程根目录下用 PowerShell 运行。
- Vivado：`$VIV` 指向本机 Vivado 2020.1 的 `vivado.bat`（不在 PATH 中，必须用全路径）。批处理统一写法：
  `& $VIV -mode batch -nojournal -log build\logs\<step>.log -source <script.tcl>`
- 环境变量用 PowerShell 写法：`$env:NETSEC_10G="0"`。每次构建前显式设置全部变量，不要依赖上一次的值。
- 每一步结束都检查：进程退出码为 0、日志里没有 `ERROR:`，然后按本文的“通过条件”判定。不满足就进入该步的失败分支；失败分支用完仍不通过，就停下来报告，不要跳到后面的阶段。
- `create_project.tcl` 每次都会覆盖 `build\proj`。每个阶段出的 bit 要立即复制到带标签的目录（例如 `build\out_g1\`）。
- 人工确认点（拨码、插线、上电/断电）出现时，暂停并请用户确认后再继续。
- 只改 `scripts/`、`constraints/`、环境变量，以及失败分支里明确写出的 RTL 参数；不要改检测引擎的 RTL。

## 1. 总体流程

P0 环境预检 → H0 人工（上电 / SW4 / 接线）→ B1 构建 10G=0 → G1 JTAG 下载 + 控制面/PHY 自测 → G2 铜口链路 + RX 延时扫描 → B2 构建完整 4×10G → 若 WNS < 0 走时序收敛梯度 TC1..TC5 后重跑 B2 → G4 下载 + 10G 链路 → G5 10G 功能自测 → G6 性能扫描 → F1 写 QSPI Flash + 断电重启复验。

## 2. P0 环境预检（全自动）

1. `Test-Path $VIV`；`& $VIV -version` 输出中必须有 `v2020.1`。
2. `python --version`（Python 3.10）；`python -c "import serial"`，失败就执行 `pip install pyserial`。
3. `python scripts\host\netsec.py --offline-check`：主机脚本离线自检必须通过（退出码 0）。
4. 串口探测：`Get-CimInstance Win32_PnPEntity | ? Name -match 'CP210'` 找到 `COMx`，记为 `$COM`。找不到就进入人工确认点（检查 Micro-USB 线和 CP210x 驱动）。
5. JTAG 探测：写 `build\auto\hw_probe.tcl`（`open_hw_manager; connect_hw_server; open_hw_target;` 打印 `get_hw_devices`），批处理运行，日志里必须出现 `xc7k325t`。
6. 仿真回归 `scripts/run_sim.sh` 需要 Icarus，本机没装则跳过。

## 3. H0 人工确认点

请用户确认：12 V 已上电；SW4 已拨到手册表 5-3-2-3 的 10GigE 行（156.25 MHz，风险 R2）；SFP+ 模块或 DAC 已插好，口 0↔1、2↔3 用 DAC/光纤互连；RJ45 A↔B 已用网线直连，或 A 接 PC。
IBERT 摸底不作为前置步骤，只在 G4 出现 `qpll_lock=0` 时作为失败分支执行。

## 4. 自动化脚本

- `scripts/auto/hw_check.tcl`：`source` `scripts/hw_regs.tcl`，然后 `ns_open; ns_status; ns_selftest`，最后打印 `SELFTEST_FAILS=$f`。
- `scripts/auto/deploy.ps1`：`Invoke-Viv <step> <tcl>`（建日志目录、跑 Vivado、检查退出码和 `ERROR:`）和 `Save-Out <tag>`（把 `build\out\*`、`build\reports\*` 复制到 `build\out_<tag>\`）。
- `create_project.tcl`：`NETSEC_UART_SWAP=1` 时把 `constraints/k7325fb_uart_swap.xdc` 以 `PROCESSING_ORDER LATE` 加入 constrs_1，覆盖 UART 引脚。

## 5. B1 + G1：控制面与铜口版本（NETSEC_10G=0）

构建：

```powershell
$env:NETSEC_10G="0"; $env:NETSEC_AES_PIPE="1"; $env:NETSEC_JOBS="8"
& $VIV -mode batch -nojournal -log build\logs\b1_create.log -source scripts\create_project.tcl
& $VIV -mode batch -nojournal -log build\logs\b1_build.log  -source scripts\build.tcl
```

B1 通过条件：`b1_build.log` 中有 `RESULT: WNS=` 且 WNS ≥ 0、WHS ≥ 0；`build\reports\drc.rpt` 没有 Error 级条目（重点看 BIVC / CFGBVS / IOSTANDARD，对应 R3、R9）。然后 `Save-Out g1`。

B1 失败分支：

- `create_ip` 端口比对失败或 `jtag_axi PROTOCOL` 报错（R10）：按日志里列出的 missing/extra 端口修改 `rtl/top/netsec_k7_top.sv` 的 jtag_axi 例化。
- DRC 报 AD12 电平冲突（R3）：在 `constraints/k7325fb_pins.xdc` 把 `sys_clk_100m` 的 IOSTANDARD 依次改为 `LVCMOS135`、`SSTL135`，然后重建。

G1 下载与自测：

```powershell
$env:NETSEC_BIT="$PWD\build\out_g1\netsec_k7_top.bit"
& $VIV -mode batch -nojournal -log build\logs\g1_prog.log  -source scripts\program.tcl
& $VIV -mode batch -nojournal -log build\logs\g1_check.log -source scripts\auto\hw_check.tcl
python scripts\host\netsec.py -p $COM ping
python scripts\host\netsec.py -p $COM status
```

G1 通过条件（`g1_check.log`）：

- `ID=0x4B373235`，`mmcm=1`，`idlyctrl=1`，uptime 在增长，`PHY IDs: A=0x001c B=0x001c`。
- 自测里以下项全部 PASS：ID、scratch、MMCM+IDELAYCTRL、uptime、PHY A/B ID1、AES FIPS-197、modexp、copper port 0/1 L0。
- 预期 FAIL（10G=0 版本没有 10G 通路）：QPLL、four GTX、10G port 0..3，共 6 项。所以 `SELFTEST_FAILS=6` 且失败项正好是这 6 个，才算通过。
- UART `ping` 返回 `pong`。

G1 失败分支：

- 所有寄存器读到 0xFFFFFFFF，或没有 hw_axi 对象：MMCM 没锁，即 AD12 时钟问题（R3），按 B1 的电平分支处理。
- UART 无应答、JTAG 正常（R5）：设 `NETSEC_UART_SWAP=1` 重建。记下这个决定，B2 也要带上。G1 其它项照常判定。
- PHY ID 不是 0x001C（R6）：`python scripts\host\netsec.py -p $COM mdio a 2 --phy N` 扫 N=0..31，找到读出 0x001C 的地址后改顶层参数 `PHYADDR_A/B`，然后重建 B1。

## 6. G2：铜口链路

1. `netsec.py -p $COM set-mode cu bridge`，然后 `status`：link_a=1、link_b=1。
2. 如果 A 接的是 PC：`set-mode cu bounce`，PC 侧 ping 对端。
3. 对端持续发包，运行 `rx-delay-scan a` 和 `rx-delay-scan b`，必须扫出一段连续无错的抽头窗口；脚本会把窗口中点写入 0x220/0x224。记入报告。
4. `stats 1g --nonzero`：FCS 错为 0。

失败分支（R7/R14）：扫不出窗口时，设 `NETSEC_USE_CLK90_A=TRUE`（B 口同理），重建 B1 再测。仍然失败则停下报告。

## 7. B2：完整 4×10G 版本 + 时序收敛回路

```powershell
$env:NETSEC_10G="1"; $env:NETSEC_REFCLK="1"; $env:NETSEC_AES_PIPE="1"; $env:NETSEC_JOBS="8"
& $VIV -mode batch -nojournal -log build\logs\b2_create.log -source scripts\create_project.tcl
& $VIV -mode batch -nojournal -log build\logs\b2_build.log  -source scripts\build.tcl
```

加上 G1/G2 得出的决定：`NETSEC_USE_CLK90_*`、`NETSEC_UART_SWAP`、PHYADDR 修改。

B2 过程检查：

- `b2_create.log` 必须有 `ten_gig_eth_pcs_pma_0/1 port list matches` 和 `INFO: GT refclk patch done: N file(s), M substitution(s)`，其中 M ≥ 3（R1）。报 `GT refclk patch failed` 时停下报告，并附上生成的 `*_gt_common*.v` 路径。
- IP 许可报错（R11）：停下报告。
- 构建完成后：`open_project` → `open_run impl_1` → `source scripts/check_gt_loc.tcl`。4 个 `GTXE2_CHANNEL` 必须在同一个 Quad（bank 118），`GTXE2_COMMON` 和 `IBUFDS_GTE2` 也在这个 Quad，`E8/E7` 的 func 为 MGTREFCLK1。

时序收敛梯度（WNS < 0 时按顺序逐级尝试，每级重新跑 B2，WNS/WHS 和最差路径族记入 `build\logs\timing_ladder.md`）：

- TC1：`NETSEC_AES_PIPE=0`。WNS 转正就记下“瓶颈在 AES 流水”，带着这个配置继续。
- TC2：在 `create_project.tcl` 末尾加 `set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraTimingOpt [get_runs impl_1]`（只在 WNS > -0.3 ns 时有意义）。
- TC3：最差路径集中在 `u_fab10.g_p[*].u_dp` 时，新建 `constraints/k7325fb_pblock.xdc`，给 4 个 dp64 各建一个 pblock，靠近 Quad 118 所在的时钟区域。
- TC4：`NETSEC_HASH_BITS=8`；如有需要再降 `DLY` 和 `ROM_PATTERNS`（RTL 参数修改，写进报告）。
- TC5：停下报告最好的一版结果，请用户决定是否只启用 2 个 dp64。

WHS < 0 一律视为错误，停下报告。

B2 通过条件：WNS ≥ 0、WHS ≥ 0，DRC 无 Error，GT 位置检查通过。然后 `Save-Out g4`。

## 8. G4：10G 链路

下载 `build\out_g4\netsec_k7_top.bit`，跑 `hw_check.tcl` 和 `netsec.py status`。
通过条件：`qpll=1`、`resetdone=0xF`、插了模块/DAC 的口 `block_lock` 对应位为 1（口 0..3 都插了就是 0xF）、`rst156_ok=1`。

失败分支：

- `qpll=0`：参考时钟问题（R1/R2）。人工确认点复查 SW4；同时生成 IBERT 摸底工程（`ibert_7series_gtx`，Quad 118，REFCLK1，156.25 MHz，10.3125 Gb/s，放在 `build\ibert\`），下载后看 QPLL 是否锁定。IBERT 也锁不上就停下报告。
- `resetdone≠0xF`：写 0x12C=1 复位一次后再读。
- `block_lock` 缺位：写 0x11C=0xFF00 清 `tx_disable`，检查模块是否为 10G 模块（R8）。

## 9. G5：10G 功能

1. `hw_check.tcl`：`SELFTEST_FAILS=0`，每个口都是 `inj -> 2 inspected, 1 DPI hit, 1 mirrored`。
2. `netsec.py selftest`，然后 `selftest --pairs`：0↔1、2↔3 对端收到的帧数等于发送帧数，FCS 错为 0。
3. `set-mode 10g loop` 和 `set-mode 10g inline` 各跑一轮，`stats 10g --nonzero` 没有 `rxfifo_overflow` / `mac_tx_underflow`。没有外部测试仪时，INLINE 只记录计数，不判定通过与否。

失败分支：DPI 项失败时，写完 DPI 表后等待 ≥100 µs 再重测（R12）；其它项失败就停下报告，附上统计计数。

## 10. G6：性能扫描

对 `G10_GAP`（0x110）扫 0、4、8、16、32、64，每个值跑 BIST 5 s，读 `stats 10g` 的 `mac_tx_frames`、`dp_rx`、`rxfifo_drop`；四口并发再跑一轮。结果写入 `build\logs\perf.md`。只记录数据，不设通过门槛。

## 11. F1：固化到 QSPI Flash

前提：G1、G2、G4、G5 全部通过。

```powershell
& $VIV -mode batch -nojournal -log build\logs\f1_flash.log -source scripts\flash.tcl
```

通过条件：日志里有 `INFO: flash programmed`，且 verify 没有报错。随后请用户断电再上电。上电后不下载 bit，直接跑 `hw_check.tcl` 和 `netsec.py status`，结果应与 G5 一致。

失败分支：`get_cfgmem_parts` 找不到 `s25fl256sxxxxxx0-spi-x1_x2_x4` 时，用 `get_cfgmem_parts *s25fl256*` 列出可用名称后替换。上电后没有自动加载时，检查 `CONFIG_MODE SPIx4` 和板上 M[2:0] 启动模式跳线。

## 12. 最终交付

写 `build\logs\DEPLOY_REPORT.md`：每个阶段的通过/失败、最终环境变量和 XDC/参数修改、WNS/WHS 与资源占用、RX 延时窗口、GT 位置、性能表、R1–R14 中各项已确认或已修改的状态。

## 13. 本机实际走的 JTAG 路径（2026-11-14）

主机没有 CP2104，UART 不作为门槛。控制全部走 JTAG-AXI。同一台 hw_server 上可能还有别的板（例如 PL 未上电的 Zynq）。`scripts/hw_regs.tcl` 的 `ns_open` 会逐个 target 打开并选中 `xc7k325t`，`program.tcl` / `flash.tcl` 都走它。不要用裸的 `open_hw_target`。

铜口测试入口是 `scripts/auto/hw_lib.tcl`，不经过 `netsec.py`：

- `ns_rx_delay_scan a|b`：对 0..31 抽头各发一帧突发（约 300 ms），`mac_rx_good>0` 且 `rx_bad_frame=0`、`rx_bad_fcs=0` 才算干净。连续窗口的中点写回 0x220/0x224。
- 下载后不要立刻读速率。`CU_STATUS`（0x208）的 speed 在 RXC 还没起来时是 0；这次板上要大约 200 s 才离开 0。speed=2 才是 125 MHz RXC（1G），speed=1 是 25 MHz（100M）。
- 厂商 RGMII 示例 `ref/MLK-325T/3-1-04_ex_udp_pl_lan/01_udp_rgmii_1g/01_udp_loop_rgmii` 的引脚、`SSTL135`（AD12）、复位低有效后拉高、TX 时钟用 125 MHz 移相 90°，都已对过。该示例不用 MDIO。

G2 的失败分支已经用完：`USE_CLK90=FALSE` 和 `TRUE` 在稳定 1G 下都扫不出窗口。按第 6 节停下，没有进入 B2。测量记在 `build/logs/DEPLOY_REPORT.md`。
