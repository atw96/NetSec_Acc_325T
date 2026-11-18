# 风险登记（板级假设与未验证项）

编号在 `constraints/*.xdc`、`scripts/*.tcl`、`PLAN.md` 中被引用。“确认方法”都是上板时的具体动作。

| ID | 风险 | 依据 / 为什么不确定 | 确认方法 | 备选方案 |
|---|---|---|---|---|
| **R1** | 参考时钟在 **MGTREFCLK1_118**（E8/E7），而 `ten_gig_eth_pcs_pma`（SupportLevel=1）共享逻辑的 `IBUFDS_GTE2` 默认连 `GTREFCLK0` | 原理图 P09/P17：CDCM 输出 `MGT118_CLK1`；CLK0（C8/C7）接 Si570 空焊位。IP 内部连接我无法在本机看到 | `create_ip.tcl` 生成后自动运行 `patch_gt_refclk.tcl`，打印修改的文件和替换次数（0 次则报错停止）；综合后 `check_gt_loc.tcl` | (a) 在 U161 焊 Si570 并设 156.25 MHz，`NETSEC_REFCLK=0`；(b) 用 7 Series Transceivers Wizard 自己生成 GTX 包装，替换 `gt10g_quad.sv`（接口：XGMII×4、`clk156`、`rst156_n`、状态位） |
| **R2** | SW4 拨码位置与 156.25 MHz 的对应关系 | 手册只给出模式表，未给丝印方向 | 用户已用 IBERT 测过四个 SFP+ 口，结果正常。本轮不再怀疑 GTX 本身 | 若以后 QPLL 不锁，再核对 SW4 |
| **R3** | 100 MHz 系统时钟 AD12 位于 HP bank 33（DDR_VCCIO=1.35 V）；板上经电阻网络接 3.3 V 晶振 | 手册只写“100 MHz 单端 AD12”；原理图 P03 的电阻值不足以判断电平 | 综合后 `report_drc`；示波器看 AD12；MMCM `LOCKED`（STATUS[0]） | 在 XDC 改 `LVCMOS135/LVCMOS18`；或焊差分晶振 XT5（T26/T27）并改顶层为 IBUFDS |
| **R4** | **156.25 MHz 时序收敛**（Kintex‑7 ‑2 对原工程 UltraScale+ ‑1 的 +0.09 ns） | 原工程在 US+ 上刚好满足；K7 ‑2 慢 20–30 % | `build/reports/timing_summary.rpt`；PLAN §7 梯度 | `NETSEC_AES_PIPE=0`、pblock、降 `DLY/HASH_BITS`、只启用部分口 |
| **R5** | UART 方向 | 手册信号名 `UART_TXD` 接 CP2104 的 TXD 脚（从 CP2104 视角命名）→ FPGA 在 AA26 *接收* | `netsec.py ping`；无应答则用 `k7325fb_uart_swap.xdc` | JTAG 路径不受影响 |
| **R6** | PHY 地址 2/1，以及 MDIO 是否有器件应答 | 原理图地址是 A=2、B=1。`mdio_master` 的 Clause-22 时序已按下降沿出数、上升沿采样改过，xsim `tb_ctrl` 为 PASS=32 FAIL=0。ILA（`build/logs/g1_mdio_ila.csv`）抓到的读帧格式正确：前导 32 个 1、ST=01、OP=10、PHY=00010、REG=00001，MDC 高电平正好 50 个 clk125。地址 0..31 的读数仍是 `0xFFFF`，释放总线后 `mdio_i` 一直为 1 | 不是地址错，也不是现在的 MDIO 时序。PHY 不驱动 MDIO。厂商能点亮 RJ45 灯的 UDP 示例本身也不使用 MDIO | 铜口数据面不再依赖 MDIO。延时只能靠 strap 或 FPGA 侧 90° 时钟 |
| **R7** | RGMII 2 ns 延时。MDIO 写不进去，strap 状态未知 | 厂商 TEMAC 把 TX 时钟 ODDR 放在 `gtx_clk90`（MMCM +90°），数据 ODDR 放在 `gtx_clk`。本工程 `USE_CLK90=TRUE` 时结构相同 | 100M（speed=1）网线环回通过：2 s 内约 5.2 万帧，`bad_frame=0`、`bad_fcs=0`。稳定 1G（speed=2，上电后约 200 s）时，`USE_CLK90` 为 FALSE 和 TRUE 都是每发一帧回来一个 `rx_bad_frame`，`mac_rx_good=0`，32 个抽头一样 | 1G 失败分支已用完，见部署报告。不要再靠 MDIO 改 TXDLY/RXDLY |
| **R8** | SFP 控制极性与速率脚；无 LOS/FAULT/MOD_ABS | 手册表 5‑11‑1 只给出 TX_DIS/RS0/RS1 的 FPGA 引脚；TX_DIS 高=关断（SFF‑8431） | 插光模块后 `block_lock`；用示波器/光功率计看 TX_DIS | 铜缆 SFP/DAC 通常不需要 RS |
| **R9** | `CFGBVS=VCCO` / `CONFIG_VOLTAGE=3.3`；LED3(J21) 实为 bank 15（3.3 V）而手册写 bank 13 | 核心板原理图 P03：bank 0 为 3.3V_VCCIO；引脚→bank 对照 | Vivado `report_drc`（BIVC/CFGBVS 项）；核心板厂商 XDC 对照 | 修改 XDC 对应行 |
| **R10** | `jtag_axi` 的 AXI4‑Lite 配置（`CONFIG.PROTOCOL=2`）与端口集 | 来自原工程用法；2020.1 之外的版本未验证 | `create_ip.tcl` 生成后比对 `.veo` 端口，不一致直接报错 | 改用 AXI4 全协议并在顶层加简单转换 |
| **R11** | `ten_gig_eth_pcs_pma` 许可状态 | PG068 称 PCS/PMA 随 Vivado 免费，但我无法在本机确认 | IP Catalog 里看 License 列；不要求 MAC 许可（MAC 用开源 verilog‑ethernet） | 评估版/改自研 PCS+GT Wizard（R1 备选 b） |
| **R12** | DPI 表构建延迟 | 铜口 `dpi_matcher` 在复位或模式改写后需 ≈4.5 k 周期（≈36 µs @125 MHz）才生效；写完 `0x140..0x17C` 后请等 ≥100 µs 再送流量 | 自测里 DPI 项失败时先加等待 | — |
| **R13** | 许可证 | 原工程 MIT；verilog‑ethernet MIT；**未使用** Forencich 的 Taxi（CERN‑OHL‑S‑2.0）代码，仅参考了其 7 系列 GTX 公开配置作交叉检查 | — | — |
| **R14** | RGMII 接收抽头。约束已改为 `set_false_path`，采样点靠运行时 IDELAY | 1G 下 A/B 口 0..31 抽头全部是 `good=0 bad_frame=1 bad_fcs=0`，没有连续窗口，不能选出中点 | 100M 时抽头 0 可用。1G 没有可用的 `NETSEC_RX_DLY_A/B` | 抽头保持默认 0。不要把 -1 写进 Flash 参数 |

## 开工前最该先确认的三件事（成本最低）

1. 量 SW4 设定后 CDCM 输出（R2），并确认 AD12 有 100 MHz（R3）；
2. 先出 `NETSEC_10G=0` 版本，确认控制面+PHY ID（R5/R6），建立信心；
3. 再出完整版，看 `patch_gt_refclk` 的输出（R1）。
