"""For functions in net/core/dev.c and devinet.c, print the memory-operand immediates the router kernel
uses vs my build, to see where struct net_device differs.

usage: devoffs.py <tree> <router_dir> fn1 fn2 ...
"""
import re
import subprocess
import sys

tree, rdir = sys.argv[1], sys.argv[2]
fns = sys.argv[3:]
BASE = 0xFFFFFF8008080000
imm_re = re.compile(r"\[(x(?:[0-9]|1[0-9]|2[0-8])|w[0-9]+), #(-?\d+)\]")
syms = sorted((int(l.split()[0], 16), l.split()[1], l.split()[2]) for l in open(f"{rdir}/kallsyms"))
addr = {n: a for a, t, n in syms}
OBJS = ["net/core/dev.o", "net/ipv4/devinet.o", "net/core/sock.o", "net/core/skbuff.o", "net/core/rtnetlink.o", "net/ethernet/eth.o", "net/sched/sch_generic.o", "net/sched/sch_api.o"]


def img_dis(fn):
    a = addr.get(fn)
    if a is None:
        return None
    nxt = next(x for x, t, n in syms if x > a and t in "tT")
    out = subprocess.run(["objdump", "-D", "-b", "binary", "-m", "aarch64", f"--adjust-vma={BASE:#x}",
                          f"--start-address={a:#x}", f"--stop-address={nxt:#x}", f"{rdir}/Image"], capture_output=True, text=True).stdout
    return [l for l in out.splitlines() if l.strip().startswith("ffff")]


def mine_dis(fn):
    for o in OBJS:
        out = subprocess.run(["objdump", "-d", "--no-show-raw-insn", f"--disassemble={fn}", f"{tree}/{o}"], capture_output=True, text=True).stdout
        if f"<{fn}>:" in out:
            return out.split(f"<{fn}>:", 1)[1].split("\n\n", 1)[0].splitlines()
    return None


def imms(lines):
    return sorted({int(m.group(2)) for l in lines for m in imm_re.finditer(l)})


for fn in fns:
    r, m = img_dis(fn), mine_dis(fn)
    if r is None or m is None:
        print(f"{fn}: missing ({'router' if r is None else 'mine'})")
        continue
    ri, mi = imms(r), imms(m)
    if ri == mi:
        print(f"{fn}: SAME {ri}")
    else:
        print(f"{fn}: router {ri}\n{' ' * len(fn)}  mine   {mi}")
