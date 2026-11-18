# NetSec‑Accel‑K7325FB

把 `atw96/NetSec_Acc_ZU4EV`（Zynq UltraScale+ 上的 FPGA 网络安全加速器）移植到 **米联客 MK7325FB**
（XC7K325T‑2FFG900I）：**4×10G SFP+（GTX Quad 118）+ 2×RJ45（RTL8211FD，RGMII）**，
控制面为 JTAG‑to‑AXI + UART。检测引擎（解析 / 流表 / DPI / IPS / AES / 校验和 / modexp）沿用原工程并做了必要修改。

> **状态（2026-11）**：Vivado 2020.1 已综合并实现 `NETSEC_10G=0`，时序为正。`tb_ctrl` 用 xsim 跑过（PASS=32，FAIL=0）。铜口只走 JTAG-AXI，没有 UART。
> 100M 网线环回正常。1G 链路能起来，但帧以 `rx_er` 返回，接收抽头 0..31 没有干净窗口；`USE_CLK90` 开或关都一样。PHY 不驱动 MDIO。4×10G 未构建，QSPI 未写。细节见 [docs/risks.md](docs/risks.md)、[docs/DEPLOY_PLAN.md](docs/DEPLOY_PLAN.md)。

文档：[PLAN（详细移植计划）](docs/PLAN.md) · [上板手册](docs/bringup.md) · [部署规程](docs/DEPLOY_PLAN.md) · [风险登记](docs/risks.md) · [寄存器表](docs/register_map.md) · [引脚表](docs/pinmap.md)

## 板上结论

RJ45 A、B 用网线对接。下载后大约 200 秒，`CU_STATUS`（0x208）里的速率才离开 0：1 表示 100M，2 表示 1G。

| 条件 | 结果 |
|---|---|
| 100M，发送时钟不移相 | 数万帧环回，`bad_frame=0`，`bad_fcs=0` |
| 1G，移相 0° 或 +90° | 链路在，发出的帧回来是一个 `rx_bad_frame`，`mac_rx_good=0`。32 个 IDELAY 抽头相同 |
| MDIO 地址 0..31 | 读数全是 `0xFFFF`。读帧格式已用 ILA 核对，PHY 不驱动总线 |

厂商 1G 示例把 Tri-Mode Ethernet MAC 固定在 `SPEED_1000_MBPS`。2 ns 发送延时由该 IP 自己的 MMCM 产生（数据用 0°，发送时钟用 +90°），接收 IDELAY 固定为 0，没有 10/100 降速。本工程是三速 MAC，接收抽头还可在运行时加大，1G 眼图不在这 32 个抽头里。

`ns_open` 在多根下载线里选择 `xc7k325t`。不要写死某根线的序列号。

## 目录
```
rtl/core      检测引擎与公共模块（dp64、流表、DPI、IPS、铜口数据通路、生成器、CDC…）
rtl/crypto    AES‑128（流水/迭代）、modexp
rtl/fabric    netsec_fabric10g（4 口 10G 交换/检测）、netsec_fabric1g（2 口铜口）
rtl/mac       gt10g_quad（4×PCS/PMA IP）、mac10g_port、rgmii_mac_k7
rtl/ctrl      寄存器、UART 桥、2:1 AXI 仲裁、统计计数器、PHY 管理
rtl/top       netsec_k7_top
rtl/third_party/verilog-ethernet   MIT（与原工程相同的子集 + eth_mac_10g/axis_fifo；iddr/oddr 为上游 7 系列版本）
constraints   k7325fb_pins.xdc  k7325fb_timing.xdc  k7325fb_uart_swap.xdc
scripts       create_project / create_ip / patch_gt_refclk / build / program / flash / check_gt_loc / hw_regs (.tcl)
              run_sim.sh  host/netsec.py
tb            tb_dp64 tb_fabric10g tb_sys10g tb_fabric1g tb_ctrl  + stubs/xilinx_stubs.v
python_model  原工程黄金模型（未改动）
```

## 最短路径
```bat
:: 把 NETSEC_VIVADO 指到本机的 vivado.bat，不要把安装路径写进仓库
set NETSEC_10G=0
vivado -mode batch -source scripts/create_project.tcl
vivado -mode batch -source scripts/build.tcl
vivado -mode batch -source scripts/program.tcl
:: Vivado Tcl:  source scripts/hw_regs.tcl ; ns_open ; ns_status ; ns_selftest
:: 之后 set NETSEC_10G=1 重新生成完整版（4×10G）
```

## 许可
MIT。源自 atw96/NetSec_Acc_ZU4EV（MIT，Copyright (c) 2026 atw96）；verilog‑ethernet 为 MIT（Alex Forencich）。
GT 层使用 Xilinx IP（需在 Vivado 中确认许可状态，见 risks.md R11）。
