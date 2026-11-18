# 寄存器映射（AXI4‑Lite，32 位，`clk125` 域）

访问：JTAG（`scripts/hw_regs.tcl`：`ns_rd/ns_wr`）或 UART（`scripts/host/netsec.py`）。写支持字节使能；“W1P”= 写 1 产生单周期脉冲，“W1C”= 写 1 清除。
**不与原工程寄存器兼容。**

## 全局
| 地址 | 名称 | 访问 | 说明 |
|---|---|---|---|
| 0x000 | ID | R | `0x4B373235`（"K725"） |
| 0x004 | VERSION | R | `0x00010000` |
| 0x008 | CTRL | RW | [0] enable（铜口检测总开关，复位 1）；[1] soft_reset（W1P，复位寄存器与逻辑） |
| 0x00C | SCRATCH | RW | |
| 0x010 | STATUS | R | [0] mmcm_locked [1] qpll_lock [2] 4 通道 resetdone [3] 铜口 A 链路 [4] 铜口 B 链路 [5] idelayctrl_rdy [6] PHY A 初始化完成 [7] PHY B 初始化完成 [8] clk156 域复位已释放 |
| 0x014 | UPTIME_S | R | 秒计数 |
| 0x018 | CONFIG | R | [3:0] 10G 口数 [7:4] 铜口数 [15:8] HASH_BITS [19:16] AES_LANES |

## 10G（0x100）
| 地址 | 名称 | 访问 | 说明 |
|---|---|---|---|
| 0x100 | G10_MODE | RW | 0 DISABLE，1 INLINE（0↔1，2↔3），2 LOOP，3 BIST。**改模式前先置 0，等帧发完** |
| 0x104 | G10_DP_EN | RW | [3:0] 每口检测使能（0=旁路）。复位 0xF |
| 0x108 | G10_AES_EN | RW | [3:0] 每口 AES 窗口使能 |
| 0x10C | G10_GEN_EN | RW | [3:0] 每口 `pkt_gen_10g` 使能（BIST 上线；`gen_to_dp` 时进检测引擎） |
| 0x110 | G10_GAP | RW | [15:0] 发生器帧间隔（周期），复位 8 |
| 0x114 | G10_FLAGS | RW | [0] gen_to_dp（发生器/注入帧进本口 dp64，无需线缆）；[1] inj_mac（注入帧直送 MAC TX） |
| 0x118 | G10_INJ | W1P | [3:0] 每口一次性注入 2 帧（#0 正常，#1 含 "GET "） |
| 0x11C | G10_SFP | RW | [3:0] TX_DIS（1=关光，复位 0）；[15:8] {RS1,RS0}×4（复位 0xFF=全速） |
| 0x120 | G10_STATUS | R | [3:0] block_lock [7:4] core_status[0] [11:8] 各通道 resetdone |
| 0x124 | G10_LAST | R | [7:0] 各口最近一次 IPS 动作（2 位/口：0 转发 1 丢弃 2 镜像） |
| 0x128 | G10_AES_DONE | R/W1C | [3:0] 各口 AES 完成（粘滞） |
| 0x12C | G10_RESET | W1P | [0] 复位 10G PCS/PMA（含 GT） |
| 0x130–0x13C | AES_KEY[0..3] | RW | 128 位密钥，**W0=最高字**（键 00 01 … 0F 依次写 0x00010203,0x04050607,0x08090A0B,0x0C0D0E0F） |
| 0x140–0x17C | DPI_PAT[0..15] | RW | 每槽 4 字节（首字节在最高位），复位槽 0="GET "；**全 0 槽=未使用**。0..3 号槽同时用于铜口 |
| 0x180 + 0x10·p + 4·w | AES_CT | R | 10G 口 p 的 AES 密文，w=0 为最高字 |

## 铜口（0x200）
| 地址 | 名称 | 访问 | 说明 |
|---|---|---|---|
| 0x200 | CU_MODE | RW | 0 BOUNCE（MAC 互换回弹），1 BRIDGE（A↔B），2 L0（片内生成器，不上线），3 DISABLE（复位 0） |
| 0x204 | CU_CTRL | RW | [1:0] 每口 AES 使能；[8] W1P 启动两口生成器（2 帧/口） |
| 0x208 | CU_STATUS | R | [0] linkA [1] linkB [3:2] speed A [5:4] speed B（`speed` 来自 MAC：00=10M 01=100M 10=1G） |
| 0x20C | CU_LAST | R | [3:0] 最近 IPS 动作（2 位/口） |
| 0x210 | MDIO_CTRL | RW | 写：[0] go（W1P）[1] we [2] port(0=A,1=B) [3] phy_ovr(用 0x214 的 PHY 地址) [9] 清 done；读：[8] busy [9] done |
| 0x214 | MDIO_ADDR | RW | [4:0] 寄存器号，[12:8] PHY 地址（phy_ovr=1 时） |
| 0x218 | MDIO_WDATA | RW | |
| 0x21C | MDIO_RDATA | R | |
| 0x220 / 0x224 | DLY_A / DLY_B | RW | [4:0] RX 数据 IDELAY 抽头；写时同时给 [8]=1 才加载 |
| 0x228 | PHY_CTRL | RW | [0] 强制 PHY 复位 [1] auto_en（复位后自动写 TX/RX 延时，复位 1） |
| 0x22C | PHY_STATUS | R | [0] linkA [1] linkB [2] initA [3] initB |
| 0x230 / 0x234 | PHY_ID_A/B | R | PHYID1 读数（RTL8211F=0x001C） |
| 0x238 | CU_AES_DONE | R/W1C | [1:0] |
| 0x240 + 0x10·p + 4·w | CU_AES_CT | R | 铜口 p 的 AES 密文 |

## MMIO 加速引擎（0x300）
| 地址 | 名称 | 说明 |
|---|---|---|
| 0x300 | MM_CTRL / MM_STAT | 写 W1P：[0] AES 启动 [1] 校验和复位 [2] modexp 启动；读：[0] AES done [1] checksum valid [2] modexp done（粘滞，启动时清零） |
| 0x310–0x31C | AES_PT[0..3] | 明文，W0 最高字；使用 0x130 的密钥 |
| 0x320–0x32C | AES_CT[0..3] | 密文 |
| 0x330 | CSUM_DATA | 写：[15:0] 数据字，[16] last；每次写推送一个 16 位字 |
| 0x334 | CSUM_RES | 读：[15:0] RFC1071 校验和（取反后） |
| 0x340/0x344/0x348 | MX_BASE/EXP/MOD | 32 位 |
| 0x34C | MX_RES | base^exp mod mod |

## 统计计数器
窗口：写 `*_CTL=idx` → 触发快照；读 `*_CTL[0]`=1 表示完成 → 读 `*_VAL`。`*_CLR` 写 1 清零全部。
| 窗口 | CTL / VAL / CLR / NUM | 索引 |
|---|---|---|
| 10G（clk156 域，128 个） | 0x400 / 0x404 / 0x408 / 0x40C | `port*32 + k` |
| 铜口（clk125 域，32 个） | 0x410 / 0x414 / 0x418 / 0x41C | `port*16 + k` |

10G：k = 0 mac_rx_frames，1 mac_rx_bad_fcs，2 mac_rx_bad_frame，3 mac_tx_frames，4 mac_tx_underflow，5 rxfifo_drop，6 rxfifo_overflow，
7 dp_rx，8 dp_tx，9 dp_forward，10 dp_drop，11 dp_mirror，12 dp_dpi_hit，13 dp_csum_err，14 dp_overflow，15 dp_flow_new，16..31 pat_hit0..15。
铜口：k = 0 mac_rx_good，1 rx_bad_frame，2 rx_bad_fcs，3 rx_overflow，4 mac_tx_good，5 tx_underflow，6 dp_rx，7 dp_tx，8 dp_forward，9 dp_drop，10 dp_mirror，11 dp_dpi_hit。
