"""The router's own modules are stripped of static symbols, so compare whole modules: the set of
register-relative memory-operand immediates in all of the router .ko's code vs my build of the same
module's object. usage: cmpmod.py <tree> <router_mods_dir>"""
import re
import subprocess
import sys

tree, mods = sys.argv[1], sys.argv[2]
imm_re = re.compile(r"\[(x(?:[0-9]|1[0-9]|2[0-8])|w[0-9]+), #(-?\d+)\]")
MODS = {
    "xt_mark": "net/netfilter/xt_mark.o",
    "xt_tcpudp": "net/netfilter/xt_tcpudp.o",
    "xt_owner": "net/netfilter/xt_owner.o",
    "xt_CLASSIFY": "net/netfilter/xt_CLASSIFY.o",
    "xt_REDIRECT": "net/netfilter/xt_REDIRECT.o",
    "xt_addrtype": "net/netfilter/xt_addrtype.o",
    "xt_TCPMSS": "net/netfilter/xt_TCPMSS.o",
    "xt_connmark": "net/netfilter/xt_connmark.o",
    "act_connmark": "net/sched/act_connmark.o",
    "nf_defrag_ipv4": "net/ipv4/netfilter/nf_defrag_ipv4.o",
    "sch_tbf": "net/sched/sch_tbf.o",
    "sch_hfsc": "net/sched/sch_hfsc.o",
}


def imms(path):
    out = subprocess.run(["objdump", "-d", "--no-show-raw-insn", "-j", ".text", path], capture_output=True, text=True).stdout
    return {int(m.group(2)) for l in out.splitlines() for m in imm_re.finditer(l)}


for name, obj in MODS.items():
    r, m = imms(f"{mods}/{name}.ko"), imms(f"{tree}/{obj}")
    tag = "SAME" if r == m else "DIFF"
    extra = "" if r == m else f"  router-only={sorted(r - m)} mine-only={sorted(m - r)}"
    print(f"  {name:16s} {tag} ({len(r)} vs {len(m)} offsets){extra}")
