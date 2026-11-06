"""Read the exported-symbol version table (ksymtab + kcrctab) out of a raw arm64 kernel Image.

usage: ksymtab.py Image kallsyms out_prefix
Writes out_prefix.crcs (crc symbol) and out_prefix.symvers (Module.symvers format).
"""
import struct
import sys

BASE = 0xFFFFFF8008080000
img = open(sys.argv[1], "rb").read()
syms = {}
for line in open(sys.argv[2]):
    a, t, n = line.split()[:3]
    syms[n] = int(a, 16)
out = sys.argv[3]


def rd(addr, n):
    o = addr - BASE
    return img[o:o + n]


def u32(addr):
    return struct.unpack("<I", rd(addr, 4))[0]


def s32(addr):
    return struct.unpack("<i", rd(addr, 4))[0]


def cstr(addr):
    o = addr - BASE
    e = img.index(b"\0", o)
    return img[o:e].decode(errors="replace")


# known reference values from the router's own modules, to pick the right decoding
KNOWN = {"kfree_skb": 0xE7869EA5, "module_layout": 0x37269833, "sk_free": 0xEFCDF9E7, "__alloc_skb": 0x698B7F81}

table = {}
for sec in ("", "_gpl", "_gpl_future", "_unused", "_unused_gpl"):
    start, stop = syms.get(f"__start___ksymtab{sec}"), syms.get(f"__stop___ksymtab{sec}")
    crcs = syms.get(f"__start___kcrctab{sec}")
    if not start or not stop or stop <= start:
        continue
    # arm64 4.19 uses 8-byte entries (two 32-bit self-relative offsets)
    n = (stop - start) // 8
    hits = {"abs": 0, "rel": 0}
    rows = []
    for i in range(n):
        ent = start + 8 * i
        name = cstr(ent + 4 + s32(ent + 4))
        c_abs = c_rel = None
        if crcs:
            ca = crcs + 4 * i
            v = s32(ca)
            c_abs = v & 0xFFFFFFFF
            try:
                c_rel = u32(ca + v)
            except Exception:
                c_rel = None
        rows.append((name, c_abs, c_rel))
        if name in KNOWN:
            hits["abs"] += c_abs == KNOWN[name]
            hits["rel"] += c_rel == KNOWN[name]
    mode = "rel" if hits["rel"] > hits["abs"] else "abs"
    print(f"ksymtab{sec}: {n} symbols, known-value hits abs={hits['abs']} rel={hits['rel']} -> using {mode}")
    for name, ca, cr in rows:
        table[name] = cr if mode == "rel" else ca

with open(out + ".crcs", "w") as f, open(out + ".symvers", "w") as g:
    for name in sorted(table):
        c = table[name]
        if c is None:
            continue
        f.write(f"0x{c:08x} {name}\n")
        g.write(f"0x{c:08x}\t{name}\tvmlinux\tEXPORT_SYMBOL\n")
print("total exported symbols with CRC:", sum(1 for v in table.values() if v is not None))
for k in ("tcp_register_congestion_control", "tcp_unregister_congestion_control", "minmax_running_max", "prandom_u32", "module_layout", "tcp_slow_start", "sk_free", "kfree_skb"):
    print(f"  {k}: {table.get(k) and hex(table[k])}")
