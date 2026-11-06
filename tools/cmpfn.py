"""Compare the struct offsets a function uses, router build vs my build.

Router side: either one of the router's own .ko files, or the kernel Image (function found via kallsyms).
Mine: an object from the android-4.19 tree. Offsets = immediates of register-relative memory operands,
excluding stack frames (sp/x29). Different compilers may load a bitfield with a different width, so
a lone pair like 1616 vs 1623 (same 8-byte word) is reported but is not a layout difference.

usage: cmpfn.py <tree> <router_dir>   (router_dir has Image, kallsyms, mods/*.ko)
"""
import re
import subprocess
import sys

tree, rdir = sys.argv[1], sys.argv[2]
BASE = 0xFFFFFF8008080000
imm_re = re.compile(r"\[(x(?:[0-9]|1[0-9]|2[0-8])|w[0-9]+), #(-?\d+)\]")

# (function, router source: "ko:<name>" or "img", my object)
PAIRS = [
    ("mark_tg", "ko:xt_mark", "net/netfilter/xt_mark.o"),
    ("mark_mt", "ko:xt_mark", "net/netfilter/xt_mark.o"),
    ("tcp_mt", "ko:xt_tcpudp", "net/netfilter/xt_tcpudp.o"),
    ("udp_mt", "ko:xt_tcpudp", "net/netfilter/xt_tcpudp.o"),
    ("owner_mt", "ko:xt_owner", "net/netfilter/xt_owner.o"),
    ("classify_tg", "ko:xt_CLASSIFY", "net/netfilter/xt_CLASSIFY.o"),
    ("redirect_tg4", "ko:xt_REDIRECT", "net/netfilter/xt_REDIRECT.o"),
    ("addrtype_mt_v1", "ko:xt_addrtype", "net/netfilter/xt_addrtype.o"),
    ("tcpmss_tg4", "ko:xt_TCPMSS", "net/netfilter/xt_TCPMSS.o"),
    ("connmark_tg", "ko:xt_connmark", "net/netfilter/xt_connmark.o"),
    ("connmark_mt", "ko:xt_connmark", "net/netfilter/xt_connmark.o"),
    ("tcf_connmark_act", "ko:act_connmark", "net/sched/act_connmark.o"),
    ("ipv4_conntrack_defrag", "ko:nf_defrag_ipv4", "net/ipv4/netfilter/nf_defrag_ipv4.o"),
    ("xt_register_target", "ko:x_tables", "net/netfilter/x_tables.o"),
    ("xt_check_target", "ko:x_tables", "net/netfilter/x_tables.o"),
    ("xt_find_target", "ko:x_tables", "net/netfilter/x_tables.o"),
    ("inet_select_addr", "img", "net/ipv4/devinet.o"),
    ("dev_get_by_index_rcu", "img", "net/core/dev.o"),
    ("__dev_get_by_index", "img", "net/core/dev.o"),
    ("skb_set_owner_w", "img", "net/core/sock.o"),
    ("sock_edemux", "img", "net/core/sock.o"),
    ("__udp4_lib_lookup", "img", "net/ipv4/udp.o"),
    ("__inet_lookup_listener", "img", "net/ipv4/inet_hashtables.o"),
    ("__inet_lookup_established", "img", "net/ipv4/inet_hashtables.o"),
    ("inet_twsk_deschedule_put", "img", "net/ipv4/inet_timewait_sock.o"),
]

syms = []
for line in open(f"{rdir}/kallsyms"):
    a, t, n = line.split()[:3]
    syms.append((int(a, 16), t, n))
syms.sort()
addr = {n: a for a, t, n in syms}


def img_dis(fn):
    a = addr.get(fn)
    if a is None:
        return None
    nxt = next(x for x, t, n in syms if x > a and t in "tT")
    out = subprocess.run(["objdump", "-D", "-b", "binary", "-m", "aarch64", f"--adjust-vma={BASE:#x}",
                          f"--start-address={a:#x}", f"--stop-address={nxt:#x}", f"{rdir}/Image"],
                         capture_output=True, text=True).stdout
    return [l for l in out.splitlines() if l.strip().startswith("ffff")]


def elf_dis(path, fn):
    out = subprocess.run(["objdump", "-d", "--no-show-raw-insn", f"--disassemble={fn}", path], capture_output=True, text=True).stdout
    if f"<{fn}>:" not in out:
        return None
    return out.split(f"<{fn}>:", 1)[1].split("\n\n", 1)[0].splitlines()


def imms(lines):
    return {int(m.group(2)) for l in lines for m in imm_re.finditer(l)}


same = diff = missing = 0
for fn, src, obj in PAIRS:
    r = img_dis(fn) if src == "img" else elf_dis(f"{rdir}/mods/{src[3:]}.ko", fn)
    m = elf_dis(f"{tree}/{obj}", fn)
    if r is None or m is None:
        print(f"  {fn:28s} missing ({'router' if r is None else 'mine'})")
        missing += 1
        continue
    ri, mi = imms(r), imms(m)
    if ri == mi:
        same += 1
        print(f"  {fn:28s} SAME ({len(ri)} offsets)")
    else:
        diff += 1
        print(f"  {fn:28s} DIFF router-only={sorted(ri - mi)} mine-only={sorted(mi - ri)}")
print(f"same={same} diff={diff} missing={missing}")
