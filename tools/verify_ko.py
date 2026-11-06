"""Check a .ko's embedded symbol versions against the router kernel's exported table.

usage: verify_ko.py module.ko router.crcs
"""
import os
import re
import subprocess
import sys

ko, crcs = sys.argv[1], sys.argv[2]
out = subprocess.run([os.environ.get("OBJDUMP", "objdump"), "-s", "-j", "__versions", ko], capture_output=True, text=True).stdout
data = bytearray()
for l in out.splitlines():
    m = re.match(r"\s*[0-9a-f]+ ((?:[0-9a-f]{8} ?){1,4})", l)
    if m:
        for w in m.group(1).split():
            data += bytes.fromhex(w)
router = {}
for l in open(crcs):
    c, s = l.split()
    router[s] = int(c, 16)
bad = 0
for i in range(0, len(data), 64):
    crc = int.from_bytes(data[i:i + 8], "little")
    name = data[i + 8:i + 64].split(b"\0")[0].decode()
    r = router.get(name)
    ok = r == crc and crc != 0
    bad += not ok
    print(f"  0x{crc:08x} {name:40s} router={hex(r) if r is not None else '-':>12} {'OK' if ok else 'PROBLEM'}")
print("entries:", len(data) // 64, "problems:", bad)
