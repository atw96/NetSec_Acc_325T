# NetSec 加速器 → MK7325FB（XC7K325T）移植计划

源工程：`atw96/NetSec_Acc_ZU4EV`（ZU4EV，1×PL RGMII + PS GEM3 铜口，2×10G SFP，MIT 许可）
目标板：米联客 MK7325FB = `MK7X900B` 核心板（XC7K325T-2FFG900I，DDR3×4，QSPI 256 Mb）+ `MLK-F12-CK03-1156` 底板
目标功能：**4×10G SFP+（GTX Quad 118）+ 2×RJ45（RTL8211FD，RGMII）**，检测引擎全部保留，控制面改为 JTAG‑AXI + UART。

> 状态说明（务必先读）：本机没有 Vivado，**综合/实现/时序/上板均未验证**。已验证的只有可用 Icarus 仿真的部分
> （见 §6）。所有“板级假设”都登记在 [risks.md](risks.md)，并在 §8 的分阶段上板流程里设置了逐项确认点。

---

## 1. 原工程任务 → 325T 实现映射

| # | 原工程任务（ZU4EV） | 325T 上的实现 | 位置 | 验证状态 |
|---|---|---|---|---|
| T1 | 1G 铜口内联检测：parse → 流表 → RFC1071 → Aho‑Corasick DPI → AES(可选) → IPS，MAC 互换回环 | **两路** RGMII（ETHA/ETHB）各一个 `netsec_datapath`；模式 BOUNCE(回弹)/BRIDGE(A↔B 桥接)/L0(片内)/DISABLE | `rtl/fabric/netsec_fabric1g.sv` | 仿真通过 (8 项) |
| T2 | PS GEM3 经网线对接 PL RGMII 做 L3 回环 | 无 PS：两个 RJ45 都在 PL，**网线 A↔B 直连**即可；或接 PC 用 BOUNCE | 同上 | 仿真(桥接/回弹)；板上待测 |
| T3 | 10G 线速检测 `netsec_dp64`（64‑bit 解析、4 字节滑窗 DPI、流表、流水 AES、IPS） | **4 份** `netsec_dp64`，各自独立流表；URAM→BRAM；延迟线 SRL 化 | `rtl/core/netsec_dp64.sv` `flow_table_bram.sv` | 仿真通过 (原 TB + 15 项 + 系统 6 项) |
| T4 | 10G 模式 BIST / INLINE(SFP1↔SFP2) / LOOP / DISABLE | 4 口：INLINE = 0↔1、2↔3 两对串接；LOOP 各口自环；BIST 发生器上线；另有片内注入(`gen_to_dp`/`inj`) | `rtl/fabric/netsec_fabric10g.sv` | 仿真通过 |
| T5 | 10G MAC + 64B/66B PCS（GTH，软 PCS，160.156 MHz 门控时钟） | **Xilinx 10GBASE‑R PCS/PMA IP ×4（GTX）** + verilog‑ethernet `eth_mac_10g`（XGMII 64‑bit），全部在单一 156.25 MHz 时钟域 | `rtl/mac/gt10g_quad.sv` `mac10g_port.sv` | MAC+XGMII 仿真通过；**GTX 未验证** |
| T6 | AXI4‑Lite 寄存器（jtag_axi + PS 固件） | jtag_axi（Vivado hw_axi）+ **UART→AXI‑Lite 桥**（CP2104，无需 Vivado），2 主 1 从仲裁 | `rtl/ctrl/*` | 仿真通过 (32 项) |
| T7 | AES‑128 / RFC1071 / modexp 的 MMIO 引擎 | 保留，寄存器 0x300 起 | `netsec_regs_k7.sv` | 仿真通过（FIPS‑197 向量等） |
| T8 | 统计计数器 | 10G 4×32 + 铜口 2×16 计数器，快照握手跨时钟读取 | `stat_bank.sv` | 仿真通过 |
| T9 | PHY 管理（MDIO） | 每 PHY 一个 `phy_mgmt`：上电后**自动写 RTL8211F 的 TX/RX 延时**、探测 PHY ID、轮询链路 | `phy_mgmt.sv` | 仿真(MDIO 行为模型)；板上待测 |
| T10 | 自测：`hw_jtag.tcl` L0–L5 | `hw_regs.tcl`（JTAG）与 `netsec.py selftest`（UART），含 `--pairs` 线缆对测试 | `scripts/` | 离线逻辑自检；板上待测 |
| T11 | IBERT 诊断 / 时序报告 | 提供 `check_gt_loc.tcl`；IBERT 步骤写入上板手册（G0） | `scripts/` `bringup.md` | — |

不移植的内容：PS 固件(`firmware/`)、Zynq 块设计、DDR（本设计不用）、PCIe/HDMI/USB3/FEP（板上有，未使用）。

---

## 2. 平台差异与对应决策

| 项目 | ZU4EV 原工程 | MK7325FB | 决策 |
|---|---|---|---|
| 处理器 | Zynq PS（A53、GEM3、OCM 固件） | 无 | 控制面改 JTAG‑AXI + UART 桥；GEM3 对端改为第二路 PL RGMII |
| 铜口 PHY | JL2121，需要特殊 RX 相位 | 2×RTL8211FD，RGMII 1.8 V（bank 13），PHY 地址 2/1 | PHY 内部开 TX/RX 2 ns 延时（MDIO 自动配置），FPGA 侧 TXC 对齐输出；RX 用 `IDELAYE2` 可调（寄存器 0x220/0x224） |
| 10G 收发器 | GTH，GT 内置 gearbox，160.156 MHz 门控时钟 | **GTX**，Quad 118（SFP A..D = CH0..3），-2 速度等级支持 10.3125 Gb/s | 改用 Xilinx 10GBASE‑R PCS/PMA IP（XGMII，156.25 MHz，单时钟域），**不再需要 BUFGCE 门控时钟** |
| GT 参考时钟 | 125 MHz SiT9121 | CDCM61002 → **MGTREFCLK1_118（E8/E7）**，拨码 SW4 选 156.25 MHz | IP 共享逻辑默认接 GTREFCLK0 → `patch_gt_refclk.tcl` 在 IP 生成后改接 GTREFCLK1（风险 R1） |
| 片上存储 | 有 URAM（流表 16 块/口） | **无 URAM**，445×BRAM36 | `flow_table_bram`；默认 `HASH_BITS=10`（4 路×1K=4096 流/口）；`HASH_BITS` 可调 |
| 延迟线 | 480×75 bit 异步复位寄存器（≈3.6 万 FF/口） | FF 407 k | `dp_delay_pipe`：无复位 SRL；复位后输入关闭至管线冲刷完（`flush_done`） |
| 系统时钟 | 200 MHz 差分 | 100 MHz 单端（AD12，bank 33） | MMCM：125 / 125∠90° / 200 MHz；`clk125` 同时作控制时钟、IP DCLK、RGMII 逻辑时钟 |
| SFP 控制 | 有 | 仅 TX_DIS、RS0、RS1 连到 FPGA（无 LOS/FAULT/MOD_ABS/I2C） | 寄存器 0x11C 控制；链路状态靠 PCS block_lock |
| 按键/LED | — | 底板 3 键 3 LED，核心板 1 键 3 LED | BUT2=复位；LED 指示心跳/链路/活动 |

---

## 3. 目标架构

```
                           ┌────────────── clk125 (MMCM, 控制域) ───────────────┐
 JTAG ─ jtag_axi ─┐        │                                                    │
                  ├ arb2 ──┤ netsec_regs_k7 ── stat_bank(1G) ── phy_mgmt×2 ── MDIO×2
 UART ─ uart_axil ┘        │        │                                          │
                           │  netsec_fabric1g (2×netsec_datapath, 8-bit)       │
 RJ45 A ─ rgmii_mac_k7 ────┤        ▲ BOUNCE / BRIDGE / L0                      │
 RJ45 B ─ rgmii_mac_k7 ────┘        ▼                                           │
                                                                                │
 SFP A..D ─ GTX×4 ─ ten_gig_eth_pcs_pma ×4 ─ XGMII ─ mac10g_port ×4  (clk156) ──┘ (CDC: level / pulse / 握手)
                                   │
                         netsec_fabric10g: rx FIFO → [gen/inj] → netsec_dp64 → 路由 → MAC tx
                         模式 DISABLE / INLINE(0↔1,2↔3) / LOOP / BIST ；stat_bank(10G, clk156)
```

时钟域：`clk125`（控制+铜口逻辑）、`clk156`（10G，来自 PCS/PMA `coreclk`）、`rgmii_rxc`×2（只存在于 MAC 内部异步 FIFO 之前）。
全部跨域路径：配置/状态用 `netsec_level_cdc`，脉冲用 `netsec_pulse_cdc`，计数器用 `stat_bank` 请求‑应答快照，数据用异步 FIFO；XDC 将四个时钟声明为 asynchronous。

10G 模式（`0x100`）：0 DISABLE，1 INLINE，2 LOOP，3 BIST。**与原工程编码不同**（原：0 BIST…3 DISABLE），
默认 DISABLE 更安全；脚本里统一用名字。铜口模式（`0x200`）：0 BOUNCE，1 BRIDGE，2 L0，3 DISABLE。

---

## 4. 板级资料核对（来源：两本手册 + 两份原理图）

* **SFP+**：A: TX D2/D1 RX E4/E3；B: C4/C3 D6/D5；C: B2/B1 B6/B5；D: A4/A3 A8/A7 —— 全在 Quad 118（原理图 P09 的 MGTXTXP0..3_118 对应 D2,C4,B2,A4 ✓）。
* **参考时钟**：`MGT118_CLK1` = E8(P)/E7(N) = MGTREFCLK1_118（原理图 P09 `MGTREFCLK1` 引脚 ✓），由 U160 CDCM61002 输出；**CLK0（C8/C7）接 Si570 焊位，默认不焊**。
* **CDCM61002 / SW4**：手册表 5‑3‑2‑3 的 10GigE 行：`Prescale 3, Feedback 25, PR1/PR0=10, VCO 1875 MHz, Output divider 4, OD2/OD1/OD0=011, Output 156.25 MHz`。**拨码对应哪一边为 ON 以板上丝印为准**，上板前用 IBERT/示波器确认 156.25 MHz（G0）。
* **RGMII**：ETHA(addr 2)：RXC AB27，RXD AE30/AE29/AD29/AC27，RX_CTL AF30，TXC AF28，TXD AG28/AG27/AF27/AF26，TX_CTL AE28，MDC W27，MDIO W28。
  ETHB(addr 1)：RXC AG29，RXD AH27/AJ27/AK28/AJ26，RX_CTL AH26，TXC AK26，TXD AH30/AJ28/AJ29/AK29，TX_CTL AG30，MDC AC26，MDIO AD26。共用复位 AK30（低有效）。
  手册表与原理图 P05/P06 引脚列表逐项一致。均为 bank 13（1.8 V，底板强制），RXC 在 MRCC 引脚上 ✓。
* **其他**：UART（CP2104，bank 13）AA26/Y26，复位键 BUT2=Y28，LED 见 `constraints/k7325fb_pins.xdc`。完整表见 [pinmap.md](pinmap.md)。
* **配置**：QSPI x4（S25FL256S），`CFGBVS=VCCO`、`CONFIG_VOLTAGE=3.3`（核心板 VCCO_0 为 3.3 V，原理图 P03/P10 推断，见 R9）。

---

## 5. 资源与时序预估（推算，非实测）

依据原工程综合层次报告（ZU4EV，`utilization_synth_hier.rpt`）：一个 `netsec_dp64` 约 **3.6 k LUT（不含 AES）+ 每条流水 AES 通道 ≈ 9.7 k LUT**
（u_dpa：3 条通道共 32.7 k；u_dpb：2 条通道共 22.1 k）；流表本体只有 226 LUT（存储在 URAM，现改 BRAM）；
原 dp64 的 FF 中约 3.67 万是 480 拍延迟线（已改 SRL）。非 dp64 部分（PS 接口、铜口、PCS/MAC 等）原工程合计约 21.6 k LUT。

| 资源 | 估算（默认：4×dp64，AES_LANES=1，HASH_BITS=10） | XC7K325T 容量 | 占比 |
|---|---|---|---|
| LUT | 4×(3.6+9.7)≈ 53 k + 铜口 2 路/MAC×4/PCS 接口/控制/统计 ≈ 25–30 k → **≈ 80–85 k** | 203 800 | ≈ 40 % |
| FF | 4×≈9 k（dp64 去掉延迟线 FF）+ 其余 ≈ 25 k → **≈ 60 k** | 407 600 | ≈ 15 % |
| BRAM36 | 4×(帧 FIFO ≈19 + rx FIFO ≈3 + 流表 ≈14) + 铜口 ≈ **150–160** | 445 | ≈ 35 % |
| GTX | 4 | 16 | — |

→ **面积不是问题（还有一倍余量，必要时可 `AES_LANES=2`），时序才是。**

降低面积/改善时序的旋钮（`create_project.tcl` 环境变量）：`NETSEC_AES_PIPE=0`（迭代 AES，每口省 ≈ 10 k LUT 且去掉最长的“每周期一轮”路径）、`NETSEC_AES_LANES`、`NETSEC_HASH_BITS`。

**时序是头号工程风险**：原工程在 UltraScale+ ‑1 上 160.156 MHz 仅 +0.09 ns；Kintex‑7 ‑2 的逻辑速度约慢 20–30 %，而目标是 156.25 MHz（6.4 ns）。见 §7。

---

## 6. 已完成的验证（本机 Icarus，`scripts/run_sim.sh` 全部通过）

| 测试 | 内容 | 结果 |
|---|---|---|
| `tb_dp64`（原 TB，对改动后的 dp64） | 1000 帧背靠背、GET 镜像丢弃、AES FIPS、校验和错误计数 | 5/5 |
| `tb_fabric10g` | 4 口：DISABLE/INLINE(4 方向)/LOOP/BIST/inj/inj_mac/gen_to_dp/坏帧丢弃/dp 旁路；AES_PIPE=0 也跑过 | 15/15 |
| `tb_sys10g` | 4 个真实 `eth_mac_10g` + XGMII 两两对接：BIST 231 帧零差错、INLINE 端到端 DPI 命中、帧循环 84 次无 FCS 错 | 6/6 |
| `tb_fabric1g` | BOUNCE(MAC 互换)、BRIDGE、DPI 命中、L0 生成器、DISABLE | 8/8 |
| `tb_ctrl` | UART 桥（读/写/ping）、寄存器、AES/校验和/modexp 引擎、跨时钟统计快照、PHY 自动配置+MDIO 行为模型 | 32/32 |
| 顶层展开 | 与端口精确的 Xilinx 桩（含 4 个 IP）一起展开，`ENABLE_10G=0/1`、`AES_PIPE=0/1` | 无错误 |

仿真过程中发现并修复的**原工程/移植缺陷**（详见 §10）：
1. 铜口 `dpi_matcher` 把全零（未使用）的模式槽当成模式 → 任意含 4 个连续 0x00 的帧（如以太网零填充）都会被判 DPI 命中并丢弃；
2. 原工程 vendored 的 `iddr.v/oddr.v` 被改成 UltraScale+ 的 `IDDRE1/ODDRE1`，在 Kintex‑7 上不存在 → 已换回上游 7 系列版本；
3. 10G 发生器在使能关闭时会中途截断帧 → MAC TX 下溢；修为“发完当前帧”，路由器对在途帧保持通路。

**未被验证**：Vivado 综合/实现/时序、IP 实际端口名（`create_ip.tcl` 会在生成后自动比对并报错）、XDC 合法性、GTX 链路、RGMII 采样裕量。

---

## 7. 时序收敛梯度（按顺序尝试）

1. 先 `NETSEC_AES_PIPE=0` 出一版 → 若 clk156 WNS ≥ 0，则 AES 流水线是瓶颈，再决定是否把 `aes128_pipe` 每轮拆两级。
2. 默认配置若 WNS 在 ‑0.3 ns 内：`Performance_ExplorePostRoutePhysOpt` 已默认；加 `set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraTimingOpt`。
3. 查 `build/reports/timing_summary.rpt` 的最差路径族：若集中在 `u_fab10.g_p[i].u_dp` 的 DPI/IPS/流表 → 为每口加 pblock（把四个 dp64 分开放置，靠近各自的 GTX 通道/时钟区域，先看布局图确认 Quad 118 的位置）。
4. 降 `DLY`（480→128）减小 SRL 链、`HASH_BITS` 10→8、`ROM_PATTERNS` 160→64。
5. 最后手段：只开 2 个 dp64（`dp_en` 在运行时关闭其余口走旁路；或改 `NP`）。

---

## 8. 分阶段上板计划（每阶段有明确通过条件，失败时停在该阶段排查）

| 阶段 | 做什么 | 通过条件 | 失败时先查 |
|---|---|---|---|
| **G0 硬件摸底**（不依赖本设计） | 供电；SW4 设 10GigE 156.25 MHz；插 SFP+ 光模块或 DAC；用 Vivado IBERT（Quad 118，refclk=REFCLK1 156.25，10.3125 G）跑 CH0‑3 | 四通道 PLL 锁定，同口自环/互连 BER 正常 | SW4、SFP 供电、REFCLK 引脚（R1/R2） |
| **G1 仅铜口+控制面**：`NETSEC_10G=0` | `create_project/build/program`；`hw_regs.tcl` → `ns_status`/`ns_selftest` | ID=`K725`、MMCM/IDELAYCTRL 就绪、uptime 走、**PHY A/B ID1=0x001C**、AES/modexp 通过、铜口 L0 通过 | AD12 电平（R3）、UART 方向（R5）、PHY 地址（R6） |
| **G2 铜口线上**：A↔B 直连或接 PC | `CU_MODE=BRIDGE`/`BOUNCE`；PC `ping`/iperf；`netsec.py rx-delay-scan` | 链路 up（STATUS[3:4]），无 FCS 错，BOUNCE 能 ping 通，扫描出连续窗口 | PHY 延时配置（R7）、`USE_CLK90_*` |
| **G3 10G 可综合性**：全功能 bitstream | 出 bit；`check_gt_loc.tcl` 确认 SFP A..D=四个 GTX 且同 Quad、refclk 在同 Quad | 综合/实现无 DRC 错误；时序按 §7 收敛 | R1（refclk 补丁）、R4（时序） |
| **G4 10G 链路** | 插模块/DAC；`netsec.py status` | `qpll_lock=1`，`resetdone=0xF`，插线口 `block_lock` 置位 | SFP 速率/TX_DIS、R1、R8 |
| **G5 10G 功能** | `selftest`（无缆：注入→dp64 计数）；`selftest --pairs`（0↔1、2↔3 用 DAC 互连：BIST 帧零 FCS 错）；INLINE：两对口之间串测试仪/主机 | 计数断言通过；INLINE 转发无丢包 | 计数器索引表、DPI 表构建等待 |
| **G6 性能** | `G10_GAP` 扫描 + 统计计数，测每口线速及四口并发 | 记录各口吞吐/丢包曲线 | 时序/FIFO 深度 |

---

## 9. 工作量与交付物清单

* `rtl/`（≈ 40 个源文件，其中 14 个新增）、`constraints/`、`scripts/`（Tcl+Python+仿真）、`tb/`、`docs/`、`python_model/`（原黄金模型，未改动）。
* 一键流程：`vivado -mode batch -source scripts/create_project.tcl` → `…/build.tcl` → `…/program.tcl`；仿真：`bash scripts/run_sim.sh`。
* 预计首次上板调试量：G0–G2 约 1 天；G3 时序收敛 1–3 天（取决于 §7 走到哪一步）；G4–G6 约 1–2 天。

---

## 10. 相对原工程的改动清单

| 文件 | 改动 | 原因 |
|---|---|---|
| `netsec_dp64.sv` | 延迟管线改 `dp_delay_pipe`（SRL）+ `flush_done`；流表换 `flow_table_bram`；`HASH_BITS` 默认 10 | 无 URAM；省约 3.6 万 FF/口 |
| `flow_table_bram.sv`（新） | URAM→BRAM，哈希折叠对任意 `HASH_BITS` 有效 | 原哈希要求 `HASH_BITS|104` |
| `netsec_datapath.sv` | 新增 `mac_swap_en` 输入 | BOUNCE/BRIDGE 运行时切换 |
| `dpi_matcher.sv` | 全零模式槽视为未使用 | 缺陷 1 |
| `pkt_gen_10g.sv` | 使能关闭时发完当前帧 | 缺陷 3 |
| `netsec_cdc.sv` | 同步器加 `ASYNC_REG` | 7 系列 CDC 分析 |
| `third_party/.../iddr.v, oddr.v` | 还原为上游 7 系列版本 | 缺陷 2 |
| 其余新增 | `netsec_fabric10g/1g`、`mac10g_port`、`gt10g_quad`、`rgmii_mac_k7`、`phy_mgmt`、`stat_bank`、`uart_axil_bridge`、`axil_arb2`、`netsec_regs_k7`、`netsec_k7_top` | 平台移植 |

寄存器映射**不与原工程兼容**（见 [register_map.md](register_map.md)）。
