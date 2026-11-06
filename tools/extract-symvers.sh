#!/bin/sh
# Read the exported-symbol versions (Module.symvers) of YOUR router's kernel, for building modules
# against a firmware other than the one build/router.symvers was taken from.
#
#   ./tools/extract-symvers.sh root@192.168.0.1 outdir
#
# Needs ssh access to the router and python3 on this machine. Read-only on the router: it copies the
# boot partition and /proc/kallsyms, nothing is written there.
set -e
ROUTER=$1; OUT=${2:-router-symvers}
[ -n "$ROUTER" ] || { echo "usage: $0 root@<router-ip> [outdir]"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
# the A/B boot partitions; the running kernel is in the active one, both are normally identical
MTD=$(ssh "$ROUTER" 'grep -E "\"boot_[ab]\"" /proc/mtd' | head -n 1 | cut -d: -f1)
echo ">> boot partition: $MTD"
ssh "$ROUTER" "cat /dev/mtdblock${MTD#mtd}" > "$OUT/boot.img"
# kernel symbol addresses (needs root; kptr_restrict 2 would hide them)
ssh "$ROUTER" 'cat /proc/kallsyms' > "$OUT/kallsyms"
grep -q '^0000000000000000' "$OUT/kallsyms" && { echo "!! kallsyms addresses are hidden: run echo 1 > /proc/sys/kernel/kptr_restrict on the router"; exit 1; }
python3 -I "$HERE/bootimg_kernel.py" "$OUT/boot.img" "$OUT"
python3 -I "$HERE/ksymtab.py" "$OUT/Image" "$OUT/kallsyms" "$OUT/router"
echo ">> $OUT/router.symvers ready; compare it with build/router.symvers:"
cmp -s "$OUT/router.symvers" "$HERE/../build/router.symvers" && echo "   identical: the prebuilt modules match this kernel" || echo "   DIFFERENT kernel: rebuild with this symvers (and re-check struct layouts, see README)"
