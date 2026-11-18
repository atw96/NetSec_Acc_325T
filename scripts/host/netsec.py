#!/usr/bin/env python3
"""netsec.py — host tool for the MK7325FB NetSec accelerator (UART register bridge).

    pip install pyserial
    python netsec.py -p COM5 status
    python netsec.py -p /dev/ttyUSB0 selftest
    python netsec.py -p COM5 stats 10g --nonzero
    python netsec.py -p COM5 set-mode 10g inline --dp 0xF
    python netsec.py -p COM5 rx-delay-scan a            # tune the RGMII RX sampling point (needs a link partner sending)
    python netsec.py --offline-check                    # protocol/regmap self-check against a software model

Wire protocol (115200 8N1, big-endian): 'W' A[4] D[4] -> 'K' | 'R' A[4] -> D[4] | 'P' -> 'p'.
"""
import argparse, struct, sys, time

# ----------------------------------------------------------------------------- register map
R = dict(ID=0x000, VERSION=0x004, CTRL=0x008, SCRATCH=0x00C, STATUS=0x010, UPTIME=0x014, CONFIG=0x018,
         G10_MODE=0x100, G10_DP_EN=0x104, G10_AES_EN=0x108, G10_GEN_EN=0x10C, G10_GAP=0x110, G10_FLAGS=0x114,
         G10_INJ=0x118, G10_SFP=0x11C, G10_STATUS=0x120, G10_LAST=0x124, G10_AES_DONE=0x128, G10_RESET=0x12C,
         AES_KEY=0x130, PATS=0x140, G10_AES_CT=0x180,
         CU_MODE=0x200, CU_CTRL=0x204, CU_STATUS=0x208, CU_LAST=0x20C, MDIO_CTRL=0x210, MDIO_ADDR=0x214,
         MDIO_WDATA=0x218, MDIO_RDATA=0x21C, DLY_A=0x220, DLY_B=0x224, PHY_CTRL=0x228, PHY_STATUS=0x22C,
         PHY_ID_A=0x230, PHY_ID_B=0x234, CU_AES_DONE=0x238, CU_AES_CT=0x240,
         MM_CTRL=0x300, MM_STAT=0x304, AES_PT=0x310, AES_CT=0x320, CSUM_DATA=0x330, CSUM_RES=0x334,
         MX_BASE=0x340, MX_EXP=0x344, MX_MOD=0x348, MX_RES=0x34C,
         S10_CTL=0x400, S10_VAL=0x404, S10_CLR=0x408, S10_NUM=0x40C,
         S1G_CTL=0x410, S1G_VAL=0x414, S1G_CLR=0x418, S1G_NUM=0x41C)

MODES10 = {"disable": 0, "inline": 1, "loop": 2, "bist": 3}
MODESCU = {"bounce": 0, "bridge": 1, "l0": 2, "disable": 3}
K10 = ["mac_rx_frames", "mac_rx_bad_fcs", "mac_rx_bad_frame", "mac_tx_frames", "mac_tx_underflow",
       "rxfifo_drop", "rxfifo_overflow", "dp_rx", "dp_tx", "dp_forward", "dp_drop", "dp_mirror", "dp_dpi_hit",
       "dp_csum_err", "dp_overflow", "dp_flow_new"] + [f"pat_hit{i}" for i in range(16)]
K1G = ["mac_rx_good", "mac_rx_bad_frame", "mac_rx_bad_fcs", "mac_rx_overflow", "mac_tx_good", "mac_tx_underflow",
       "dp_rx", "dp_tx", "dp_forward", "dp_drop", "dp_mirror", "dp_dpi_hit"]
ACTIONS = {0: "forward", 1: "drop", 2: "mirror", 3: "other"}


# ----------------------------------------------------------------------------- links
class UartLink:
    def __init__(self, port, baud=115200, timeout=1.0):
        import serial
        self.s = serial.Serial(port, baud, timeout=timeout)
        self.s.reset_input_buffer()

    def _rx(self, n):
        b = self.s.read(n)
        if len(b) != n:
            raise IOError(f"UART timeout (wanted {n} bytes, got {len(b)}): wrong port, wrong pin pair "
                          f"(see constraints/k7325fb_uart_swap.xdc) or design not running")
        return b

    def ping(self):
        self.s.write(b"P"); return self._rx(1) == b"p"

    def read(self, addr):
        self.s.write(b"R" + struct.pack(">I", addr))
        return struct.unpack(">I", self._rx(4))[0]   # an AXI error would be answered by a single 'E' (never seen: the register file always responds OKAY)

    def write(self, addr, val):
        self.s.write(b"W" + struct.pack(">II", addr, val & 0xFFFFFFFF))
        r = self._rx(1)
        if r != b"K": raise IOError(f"write ack {r!r}")


class Board:
    def __init__(self, link): self.l = link
    def rd(self, name_or_addr):
        return self.l.read(R[name_or_addr] if isinstance(name_or_addr, str) else name_or_addr)
    def wr(self, name_or_addr, val):
        self.l.write(R[name_or_addr] if isinstance(name_or_addr, str) else name_or_addr, val)

    def stat(self, bank, idx, timeout=0.5):
        ctl, val = (R["S10_CTL"], R["S10_VAL"]) if bank == "10g" else (R["S1G_CTL"], R["S1G_VAL"])
        self.wr(ctl, idx)
        t0 = time.time()
        while not (self.rd(ctl) & 1):
            if time.time() - t0 > timeout: raise IOError("stat snapshot timeout (is the 156.25 MHz domain up?)")
        return self.rd(val)

    def stat_clear(self):
        self.wr("S10_CLR", 1); self.wr("S1G_CLR", 1); time.sleep(0.01)

    def status(self):
        s = self.rd("STATUS"); g = self.rd("G10_STATUS")
        names = ["mmcm_locked", "qpll_lock", "gt_all_resetdone", "link_a", "link_b", "idelayctrl_rdy",
                 "phy_a_init", "phy_b_init", "rst156_released"]
        d = {n: (s >> i) & 1 for i, n in enumerate(names)}
        d.update(block_lock=g & 0xF, core_status=(g >> 4) & 0xF, resetdone=(g >> 8) & 0xF,
                 phy_id_a=self.rd("PHY_ID_A"), phy_id_b=self.rd("PHY_ID_B"),
                 uptime_s=self.rd("UPTIME"), id=self.rd("ID"), version=self.rd("VERSION"), config=self.rd("CONFIG"))
        return d

    def set_key(self, key16):
        for i in range(4): self.wr(R["AES_KEY"] + 4 * i, int.from_bytes(key16[4 * i:4 * i + 4], "big"))
    def set_pattern(self, slot, text4):
        self.wr(R["PATS"] + 4 * slot, int.from_bytes(text4.ljust(4, b"\0")[:4], "big"))

    def mdio(self, port, reg, phy=None, wdata=None):
        self.wr("MDIO_ADDR", (reg & 0x1F) | (((phy or 0) & 0x1F) << 8))
        ctl = (port << 2) | (1 << 9)                       # clear sticky done
        if phy is not None: ctl |= 1 << 3
        if wdata is not None:
            self.wr("MDIO_WDATA", wdata); ctl |= 1 << 1
        self.wr("MDIO_CTRL", ctl | 1)
        t0 = time.time()
        while not (self.rd("MDIO_CTRL") & 0x200):
            if time.time() - t0 > 0.5: raise IOError("MDIO timeout")
        return self.rd("MDIO_RDATA")


# ----------------------------------------------------------------------------- self test
def selftest(b, pairs=False):
    fails = 0
    def chk(name, cond, info=""):
        nonlocal fails
        print(("PASS" if cond else "FAIL") + f": {name}" + (f"   [{info}]" if info else ""))
        if not cond: fails += 1
    st = b.status()
    chk("ID 'K725'", st["id"] == 0x4B373235, hex(st["id"]))
    b.wr("SCRATCH", 0xA5A55A5A); chk("scratch r/w", b.rd("SCRATCH") == 0xA5A55A5A)
    chk("MMCM locked / IDELAYCTRL ready", st["mmcm_locked"] and st["idelayctrl_rdy"])
    t0 = b.rd("UPTIME"); time.sleep(1.2); chk("uptime runs", b.rd("UPTIME") > t0)
    chk("PHY A answers on MDIO (ID1 0x001C)", st["phy_id_a"] == 0x001C, hex(st["phy_id_a"]))
    chk("PHY B answers on MDIO (ID1 0x001C)", st["phy_id_b"] == 0x001C, hex(st["phy_id_b"]))
    print(f"INFO: copper link A={st['link_a']} B={st['link_b']} ; PHY RGMII delays configured by phy_mgmt "
          f"(init A={st['phy_a_init']} B={st['phy_b_init']})")
    # MMIO engines
    b.set_key(bytes(range(16)))
    pt = bytes.fromhex("00112233445566778899aabbccddeeff")
    for i in range(4): b.wr(R["AES_PT"] + 4 * i, int.from_bytes(pt[4 * i:4 * i + 4], "big"))
    b.wr("MM_CTRL", 1); time.sleep(0.02)
    ct = b"".join(b.rd(R["AES_CT"] + 4 * i).to_bytes(4, "big") for i in range(4))
    chk("AES-128 FIPS-197 C.1", ct.hex() == "69c4e0d86a7b0430d8cdb78070b4c55a", ct.hex())
    for a, v in (("MX_BASE", 7), ("MX_EXP", 13), ("MX_MOD", 101)): b.wr(a, v)
    b.wr("MM_CTRL", 4); time.sleep(0.02); chk("modexp 7^13 mod 101", b.rd("MX_RES") == pow(7, 13, 101))
    # 10G
    chk("QPLL locked", bool(st["qpll_lock"]))
    chk("4 GTX channels out of reset", st["resetdone"] == 0xF, bin(st["resetdone"]))
    if st["qpll_lock"]:
        b.wr("G10_SFP", 0x000F)                       # lasers off during the cable-less test
        b.wr("G10_MODE", MODES10["loop"]); b.wr("G10_DP_EN", 0xF); b.wr("G10_FLAGS", 0)
        b.stat_clear(); b.wr("G10_INJ", 0xF); time.sleep(0.05)
        for p in range(4):
            v = {k: b.stat("10g", p * 32 + i) for i, k in enumerate(K10[:16])}
            chk(f"10G port {p}: injector -> dp64 (2 inspected, 1 DPI hit, 1 mirrored)",
                v["dp_rx"] == 2 and v["dp_dpi_hit"] == 1 and v["dp_mirror"] == 1,
                f"rx={v['dp_rx']} dpi={v['dp_dpi_hit']} mir={v['dp_mirror']} fwd={v['dp_forward']} tx={v['dp_tx']}")
        b.wr("G10_MODE", 0); b.wr("G10_SFP", 0xFF00)
        print(f"INFO: SFP block lock (modules + fibre/DAC present): {st['block_lock']:04b} (bit0 = SFP A)")
        if pairs:
            # needs DAC/fibre between ports (0<->1) and (2<->3): BIST generator on one side, count at the other
            b.wr("G10_MODE", MODES10["bist"]); b.stat_clear()
            b.wr("G10_GEN_EN", 0b0101); time.sleep(0.5); b.wr("G10_GEN_EN", 0); time.sleep(0.05)
            for tx, rx in ((0, 1), (2, 3)):
                t = b.stat("10g", tx * 32 + 3); r = b.stat("10g", rx * 32 + 0); bad = b.stat("10g", rx * 32 + 1)
                chk(f"10G cable {tx}->{rx}: {t} frames sent, all received, no FCS errors", t > 0 and r == t and bad == 0, f"rx={r} badfcs={bad}")
            b.wr("G10_MODE", 0)
    # copper L0
    b.wr("CU_MODE", MODESCU["l0"]); b.stat_clear(); b.wr("CU_CTRL", 0x100); time.sleep(0.05)
    for p in range(2):
        rx = b.stat("1g", p * 16 + 6); dpi = b.stat("1g", p * 16 + 11)
        chk(f"copper port {p}: L0 generator (2 inspected, 1 DPI hit)", rx == 2 and dpi == 1, f"rx={rx} dpi={dpi}")
    b.wr("CU_MODE", MODESCU["disable"])
    print("SELFTEST PASSED" if not fails else f"SELFTEST FAILED ({fails})")
    return fails


def dump_stats(b, bank, nonzero):
    nports, per, names = (4, 32, K10) if bank == "10g" else (2, 16, K1G)
    for p in range(nports):
        row = []
        for k, n in enumerate(names):
            v = b.stat(bank, p * per + k)
            if v or not nonzero: row.append(f"{n}={v}")
        print(f"[{bank} port {p}] " + (", ".join(row) if row else "(all zero)"))


def rx_delay_scan(b, port, dwell=0.5):
    """Sweep the 32 IDELAYE2 taps on RGMII RX and report good/bad frame counts per tap.
    Requires a link partner that keeps sending (e.g. ping -f / iperf from the PC) in BOUNCE or any mode."""
    reg = R["DLY_A"] if port == "a" else R["DLY_B"]
    base = 0 if port == "a" else 16
    res = []
    for tap in range(32):
        b.wr(reg, tap | 0x100); b.stat_clear(); time.sleep(dwell)
        good = b.stat("1g", base + 0); bad = b.stat("1g", base + 1) + b.stat("1g", base + 2)
        res.append((tap, good, bad)); print(f"tap {tap:2d}: good={good:6d} bad={bad:6d}")
    ok = [t for t, g, bd in res if g > 0 and bd == 0]
    if ok:
        mid = ok[len(ok) // 2]; print(f"working window taps {ok[0]}..{ok[-1]} -> use {mid}"); b.wr(reg, mid | 0x100)
    else:
        print("no clean window: check PHY delay config / USE_CLK90 parameter")


# ----------------------------------------------------------------------------- offline model
class FakeLink:
    """Tiny register-model of the board used by --offline-check (verifies the host-side logic only)."""
    def __init__(self):
        self.m = {R["ID"]: 0x4B373235, R["VERSION"]: 0x10000, R["STATUS"]: 0x1FF, R["G10_STATUS"]: 0xF0F,
                  R["PHY_ID_A"]: 0x1C, R["PHY_ID_B"]: 0x1C, R["UPTIME"]: 0}
        self.ctl = {}; self.cnt = {}; self.t = 0
    def read(self, a):
        if a == R["UPTIME"]: self.t += 1; return self.t
        if a in (R["S10_CTL"], R["S1G_CTL"]): return 1
        if a in (R["S10_VAL"], R["S1G_VAL"]): return self.cnt.get((a, self.ctl.get(a - 4, 0)), 0)
        if a == R["AES_CT"] + 0: return 0x69C4E0D8
        if a == R["AES_CT"] + 4: return 0x6A7B0430
        if a == R["AES_CT"] + 8: return 0xD8CDB780
        if a == R["AES_CT"] + 12: return 0x70B4C55A
        if a == R["MX_RES"]: return 75
        return self.m.get(a, 0)
    def write(self, a, v):
        self.m[a] = v
        if a in (R["S10_CTL"], R["S1G_CTL"]): self.ctl[a] = v
        if a == R["G10_INJ"]:
            for p in range(4):
                for k, val in ((7, 2), (12, 1), (11, 1)): self.cnt[(R["S10_VAL"], p * 32 + k)] = val
        if a == R["CU_CTRL"] and v & 0x100:
            for p in range(2):
                for k, val in ((6, 2), (11, 1)): self.cnt[(R["S1G_VAL"], p * 16 + k)] = val


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-p", "--port"); ap.add_argument("-b", "--baud", type=int, default=115200)
    ap.add_argument("--offline-check", action="store_true")
    sub = ap.add_subparsers(dest="cmd")
    sub.add_parser("ping"); sub.add_parser("status")
    r = sub.add_parser("read"); r.add_argument("addr")
    w = sub.add_parser("write"); w.add_argument("addr"); w.add_argument("value")
    s = sub.add_parser("stats"); s.add_argument("bank", choices=["10g", "1g"]); s.add_argument("--nonzero", action="store_true")
    sub.add_parser("clear-stats")
    t = sub.add_parser("selftest"); t.add_argument("--pairs", action="store_true", help="also test DAC/fibre pairs 0<->1, 2<->3 (BIST)")
    m = sub.add_parser("set-mode"); m.add_argument("which", choices=["10g", "cu"]); m.add_argument("mode"); m.add_argument("--dp", default="0xF")
    d = sub.add_parser("rx-delay-scan"); d.add_argument("port", choices=["a", "b"])
    md = sub.add_parser("mdio"); md.add_argument("port", choices=["a", "b"]); md.add_argument("reg"); md.add_argument("--phy"); md.add_argument("--write")
    a = ap.parse_args()

    if a.offline_check:
        b = Board(FakeLink()); sys.exit(1 if selftest(b) else 0)
    if not a.port or not a.cmd: ap.error("need -p PORT and a command (or --offline-check)")
    b = Board(UartLink(a.port, a.baud))
    if a.cmd == "ping": print("pong" if b.l.ping() else "no answer")
    elif a.cmd == "status":
        for k, v in b.status().items(): print(f"{k:18s} {hex(v) if k in ('id','version','config','phy_id_a','phy_id_b') else v}")
    elif a.cmd == "read": print(hex(b.rd(int(a.addr, 0))))
    elif a.cmd == "write": b.wr(int(a.addr, 0), int(a.value, 0))
    elif a.cmd == "stats": dump_stats(b, a.bank, a.nonzero)
    elif a.cmd == "clear-stats": b.stat_clear()
    elif a.cmd == "selftest": sys.exit(1 if selftest(b, a.pairs) else 0)
    elif a.cmd == "set-mode":
        if a.which == "10g": b.wr("G10_MODE", MODES10[a.mode]); b.wr("G10_DP_EN", int(a.dp, 0))
        else: b.wr("CU_MODE", MODESCU[a.mode])
    elif a.cmd == "rx-delay-scan": rx_delay_scan(b, a.port)
    elif a.cmd == "mdio":
        port = 0 if a.port == "a" else 1
        v = b.mdio(port, int(a.reg, 0), int(a.phy, 0) if a.phy else None, int(a.write, 0) if a.write else None)
        print(hex(v))

if __name__ == "__main__":
    main()
