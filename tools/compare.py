"""Compare my build with the router kernel.

usage: compare.py <tree> <my_crcs.txt> <router.crcs> <router_dis_dir>
1. symbol versions: my __crc_ values vs the router's exported table
2. struct offsets: the memory-operand immediates each TCP function uses, mine vs the router's
"""
import re
import subprocess
import sys

tree, mine_f, router_f, disdir = sys.argv[1:5]

mine = {}
for l in open(mine_f):
    c, s = l.split()
    mine[s] = int(c, 16)
router = {}
for l in open(router_f):
    c, s = l.split()
    router[s] = int(c, 16)

common = sorted(set(mine) & set(router))
ok = [s for s in common if mine[s] == router[s]]
bad = [s for s in common if mine[s] != router[s]]
print(f"symbol versions compared: {len(common)}  match: {len(ok)}  mismatch: {len(bad)}")
print("BBR needs:")
for s in ("module_layout", "tcp_register_congestion_control", "tcp_unregister_congestion_control", "minmax_running_max", "prandom_u32", "__stack_chk_fail", "__stack_chk_guard", "printk"):
    m, r = mine.get(s), router.get(s)
    fm = hex(m) if m is not None else "-"
    fr = hex(r) if r is not None else "-"
    print(f"  {s:36s} mine={fm:>12} router={fr:>12}  {'OK' if m == r and m is not None else ('n/a' if m is None or r is None else 'DIFF')}")
print("other mismatches:", " ".join(bad[:60]))

# struct offsets per function
FUNCS = {
    "tcp_slow_start": "net/ipv4/tcp_cong.o",
    "tcp_cong_avoid_ai": "net/ipv4/tcp_cong.o",
    "tcp_reno_cong_avoid": "net/ipv4/tcp_cong.o",
    "tcp_init_congestion_control": "net/ipv4/tcp_cong.o",
    "tcp_register_congestion_control": "net/ipv4/tcp_cong.o",
    "tcp_update_pacing_rate": "net/ipv4/tcp_input.o",
    "tcp_rate_gen": "net/ipv4/tcp_rate.o",
    "minmax_running_max": "lib/win_minmax.o",
}
imm_re = re.compile(r"\[(?:x|w|sp)[0-9]*, #(-?\d+)\]")


def imms(lines):
    s = set()
    for l in lines:
        for m in imm_re.finditer(l):
            v = int(m.group(1))
            if v >= 32:  # skip stack-frame slots
                s.add(v)
    return s


print("\nstruct offsets used by each function (immediates >= 32), router vs mine:")
for fn, obj in FUNCS.items():
    try:
        rl = open(f"{disdir}/dis_{fn}.txt").read().splitlines()
    except FileNotFoundError:
        print(f"  {fn}: no router disassembly")
        continue
    out = subprocess.run(["objdump", "-d", "--no-show-raw-insn", f"--disassemble={fn}", f"{tree}/{obj}"], capture_output=True, text=True).stdout
    body = out.split(f"<{fn}>:", 1)[-1].split("\n\n", 1)[0].splitlines()
    r, m = imms(rl), imms(body)
    status = "SAME" if r == m else "DIFFERENT"
    print(f"  {fn:28s} {status}  router-only={sorted(r - m)} mine-only={sorted(m - r)}")

# the offsets table from offs.o
out = subprocess.run(["objdump", "-s", "-j", ".rodata", f"{tree}/net/ipv4/offs.o"], capture_output=True, text=True).stdout
print("\noffs.o rodata present:", "Contents" in out)
