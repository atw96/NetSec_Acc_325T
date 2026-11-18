# 引脚表（由 `constraints/k7325fb_pins.xdc` 自动生成，依据手册表 5‑x 与原理图交叉核对）

IOSTANDARD 列为约束文件中设置的值；`GT 专用` 为 GTX 收发器引脚（无 IOSTANDARD）。带 [VERIFY] 的假设见 [risks.md](risks.md)。


### 系统/控制

| 端口 | 引脚 | IOSTANDARD |
|---|---|---|
| `sys_clk_100m` | AD12 | LVCMOS15 |
| `rst_btn_n` | Y28 | LVCMOS18 |
| `uart_rxd` | AA26 | LVCMOS18 |
| `uart_txd` | Y26 | LVCMOS18 |

### LED

| 端口 | 引脚 | IOSTANDARD |
|---|---|---|
| `led_base[0]` | AB28 | LVCMOS18 |
| `led_base[1]` | AA27 | LVCMOS18 |
| `led_base[2]` | J21 | LVCMOS33 |
| `led_core[0]` | T30 | LVCMOS33 |
| `led_core[1]` | U30 | LVCMOS33 |
| `led_core[2]` | V30 | LVCMOS33 |

### GTX 参考时钟

| 端口 | 引脚 | IOSTANDARD |
|---|---|---|
| `mgt_refclk_p` | E8 | GT 专用 |
| `mgt_refclk_n` | E7 | GT 专用 |

### SFP+ A（GTX 通道 0，Quad 118）

| 端口 | 引脚 | IOSTANDARD |
|---|---|---|
| `sfp_txp[0]` | D2 | GT 专用 |
| `sfp_txn[0]` | D1 | GT 专用 |
| `sfp_rxp[0]` | E4 | GT 专用 |
| `sfp_rxn[0]` | E3 | GT 专用 |
| `sfp_tx_dis[0]` | B23 | LVCMOS33 |
| `sfp_rs0[0]` | A23 | LVCMOS33 |
| `sfp_rs1[0]` | A25 | LVCMOS33 |

### SFP+ B（GTX 通道 1，Quad 118）

| 端口 | 引脚 | IOSTANDARD |
|---|---|---|
| `sfp_txp[1]` | C4 | GT 专用 |
| `sfp_txn[1]` | C3 | GT 专用 |
| `sfp_rxp[1]` | D6 | GT 专用 |
| `sfp_rxn[1]` | D5 | GT 专用 |
| `sfp_tx_dis[1]` | AA25 | LVCMOS18 |
| `sfp_rs0[1]` | AB25 | LVCMOS18 |
| `sfp_rs1[1]` | AD27 | LVCMOS18 |

### SFP+ C（GTX 通道 2，Quad 118）

| 端口 | 引脚 | IOSTANDARD |
|---|---|---|
| `sfp_txp[2]` | B2 | GT 专用 |
| `sfp_txn[2]` | B1 | GT 专用 |
| `sfp_rxp[2]` | B6 | GT 专用 |
| `sfp_rxn[2]` | B5 | GT 专用 |
| `sfp_tx_dis[2]` | AD28 | LVCMOS18 |
| `sfp_rs0[2]` | Y30 | LVCMOS18 |
| `sfp_rs1[2]` | AA30 | LVCMOS18 |

### SFP+ D（GTX 通道 3，Quad 118）

| 端口 | 引脚 | IOSTANDARD |
|---|---|---|
| `sfp_txp[3]` | A4 | GT 专用 |
| `sfp_txn[3]` | A3 | GT 专用 |
| `sfp_rxp[3]` | A8 | GT 专用 |
| `sfp_rxn[3]` | A7 | GT 专用 |
| `sfp_tx_dis[3]` | AB29 | LVCMOS18 |
| `sfp_rs0[3]` | AB30 | LVCMOS18 |
| `sfp_rs1[3]` | AC29 | LVCMOS18 |

### ETHA / RJ45 A（PHY 地址 2）

| 端口 | 引脚 | IOSTANDARD |
|---|---|---|
| `eth_a_rxc` | AB27 | LVCMOS18 |
| `eth_a_rxd[0]` | AE30 | LVCMOS18 |
| `eth_a_rxd[1]` | AE29 | LVCMOS18 |
| `eth_a_rxd[2]` | AD29 | LVCMOS18 |
| `eth_a_rxd[3]` | AC27 | LVCMOS18 |
| `eth_a_rx_ctl` | AF30 | LVCMOS18 |
| `eth_a_txc` | AF28 | LVCMOS18 |
| `eth_a_txd[0]` | AG28 | LVCMOS18 |
| `eth_a_txd[1]` | AG27 | LVCMOS18 |
| `eth_a_txd[2]` | AF27 | LVCMOS18 |
| `eth_a_txd[3]` | AF26 | LVCMOS18 |
| `eth_a_tx_ctl` | AE28 | LVCMOS18 |
| `eth_a_mdc` | W27 | LVCMOS18 |
| `eth_a_mdio` | W28 | LVCMOS18 |

### ETHB / RJ45 B（PHY 地址 1）

| 端口 | 引脚 | IOSTANDARD |
|---|---|---|
| `eth_b_rxc` | AG29 | LVCMOS18 |
| `eth_b_rxd[0]` | AH27 | LVCMOS18 |
| `eth_b_rxd[1]` | AJ27 | LVCMOS18 |
| `eth_b_rxd[2]` | AK28 | LVCMOS18 |
| `eth_b_rxd[3]` | AJ26 | LVCMOS18 |
| `eth_b_rx_ctl` | AH26 | LVCMOS18 |
| `eth_b_txc` | AK26 | LVCMOS18 |
| `eth_b_txd[0]` | AH30 | LVCMOS18 |
| `eth_b_txd[1]` | AJ28 | LVCMOS18 |
| `eth_b_txd[2]` | AJ29 | LVCMOS18 |
| `eth_b_txd[3]` | AK29 | LVCMOS18 |
| `eth_b_tx_ctl` | AG30 | LVCMOS18 |
| `eth_b_mdc` | AC26 | LVCMOS18 |
| `eth_b_mdio` | AD26 | LVCMOS18 |

### PHY 复位

| 端口 | 引脚 | IOSTANDARD |
|---|---|---|
| `eth_rst_n` | AK30 | LVCMOS18 |
