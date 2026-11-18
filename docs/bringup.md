# 上板手册（按 PLAN §8 的阶段顺序）

前置：Vivado **2020.1**（原工程所用版本；其它版本见 risks.md R10）、Python 3 + `pip install pyserial`、USB‑JTAG 下载线、Micro‑USB（CP2104 串口）线、
12 V/5 A 电源、SFP+ 模块或 DAC。

## 0. 构建

```bat
cd NetSec_Acc_K7325FB
:: 先出只含 控制面+2×RJ45 的版本（G1/G2 用，综合快，不依赖 GTX/refclk）
set NETSEC_10G=0
vivado -mode batch -source scripts/create_project.tcl
vivado -mode batch -source scripts/build.tcl
vivado -mode batch -source scripts/program.tcl

:: 完整版（4×10G）
set NETSEC_10G=1
set NETSEC_REFCLK=1          :: 156.25 MHz 在 MGTREFCLK1（出厂板，需要补丁，见 R1）；Si570 焊好放 REFCLK0 时用 0
vivado -mode batch -source scripts/create_project.tcl
vivado -mode batch -source scripts/build.tcl
```
常用环境变量：`NETSEC_AES_PIPE=0`（时序/面积兜底）、`NETSEC_AES_LANES`、`NETSEC_HASH_BITS`、`NETSEC_USE_CLK90_A/B`、`NETSEC_JOBS`。
产物：`build/out/netsec_k7_top.bit`、`netsec_k7_top.mcs`（`flash.tcl` 写 QSPI）、`build/reports/*.rpt`。
`create_project.tcl` 在 IP 生成后会**自动比对 IP 端口名**并执行 GT 参考时钟补丁，任何不一致都会直接报错并给出处理建议。

纯仿真回归（无需 Vivado）：`bash scripts/run_sim.sh`。

## G0 — 硬件摸底
1. 核心板+底板上电，12 V。确认 QSPI/JTAG 能被 Vivado 识别（`xc7k325t`）。
2. SW4 设为手册 10GigE 行（156.25 MHz，见 risks.md R2）；插好 SFP+ 模块/DAC。
3. （推荐）新建 IBERT 工程（7 Series GTX，Quad 118，refclk=`REFCLK1` 156.25 MHz，线速 10.3125 Gb/s），下载后确认 CH0‑CH3 PLL 锁定；
   两端 DAC 互连的口跑 PRBS31 无误码。**此步不通过就不要继续 G3 之后的步骤。**

## G1 — 控制面 + PHY（`NETSEC_10G=0`）
```
vivado -mode tcl
source scripts/hw_regs.tcl
ns_open
ns_status          ;# ID=0x4B373235  mmcm=1  idlyctrl=1  PHY IDs=0x001C
ns_selftest        ;# 10G 相关项在 10G=0 版本里会失败，属预期；其余应全部 PASS
```
UART：`python scripts/host/netsec.py -p COM5 ping` → `pong`；不通见 R5。
若 `PHY ID1 ≠ 0x001C`：用 `netsec.py mdio a 2 --phy N` 扫描 N=0..31 找真实地址，然后改顶层参数 `PHYADDR_A/B`。

## G2 — 铜口线上
* **A↔B 直连**：`netsec.py set-mode cu bridge`；`status` 里 link_a/link_b 应为 1。把 PC 接到 A，对 B 侧另一台设备/第二网卡通信，
  或直接用 BOUNCE：`set-mode cu bounce`，PC 接 A，向任意 MAC 发包，帧会以 MAC 互换形式返回。
* 抽头扫描：`netsec.py rx-delay-scan a`（对端持续发包，如 `ping -f`/iperf）→ 选连续无错窗口中点；`b` 同理。
* 检测验证：`netsec.py stats 1g --nonzero`；发含 `GET ` 的 TCP 载荷应看到 dp_dpi_hit/dp_mirror 增加（DPI 表写入后等 ≥100 µs，R12）。

## G3/G4 — 10G 综合与链路（完整版）
1. 综合/实现后：`vivado -mode batch -source scripts/check_gt_loc.tcl`（在打开实现结果的会话中），确认四个 SFP 口落在同一 Quad 的 4 个 GTX 上、`IBUFDS_GTE2` 在同 Quad。
2. 时序：看 `build/reports/timing_summary.rpt`；不达标按 PLAN §7。
3. 下载后：`netsec.py status` → `qpll_lock=1`、`resetdone=15`（0xF）；插好模块/DAC 的口 `block_lock` 对应位置 1。

## G5 — 10G 功能
* `netsec.py selftest`：无缆测试（激光关闭），每口 `injector → dp64` 应得到 `2 inspected / 1 DPI hit / 1 mirrored`。
* `netsec.py selftest --pairs`：口 0↔1、2↔3 用 DAC/光纤互连，BIST 发生器 0 和 2 发包，对端 MAC 收到的帧数应与发送完全相等且 FCS 错为 0。
* INLINE：`set-mode 10g inline`；测试仪/主机接在口 0 与口 1 两端（或 2 与 3），检查转发无丢包，含 `GET ` 的帧被镜像丢弃。
* 回环：`set-mode 10g loop` → 各口把自己收到的帧（经检测）从同一口发回。

## G6 — 性能
`G10_GAP`（0x110）调发生器间隔，`stats 10g` 读 `mac_tx_frames/dp_rx/rxfifo_drop`；
记录每口线速以及四口并发时是否出现 `rxfifo_overflow` / `mac_tx_underflow`。

## 排错速查
| 现象 | 先看 |
|---|---|
| 所有寄存器读到 0xFFFFFFFF / UART 无应答 | MMCM 未锁（AD12 时钟，R3）；UART 引脚方向（R5） |
| STATUS[0]=1 但 uptime 不走 | 复位被按住（BUT2）/ `ctl_rst_n` |
| PHY ID 读到 0 或 0xFFFF | PHY 地址（R6）、PHY 复位（`PHY_CTRL[0]` 是否被置位）、MDIO 上拉 |
| 铜口链路 up 但全是坏帧 | `rx-delay-scan`；`USE_CLK90_*`/PHY 延时（R7） |
| `qpll_lock=0` | 无 156.25 MHz（R2）；refclk 补丁（R1） |
| `resetdone≠0xF` | 复位一次：写 0x12C=1；检查 SFP 模块是否支持 10G |
| 10G 帧有 FCS 错 | 光模块/DAC 质量；IBERT 误码；`G10_SFP` 的 RS 位 |
