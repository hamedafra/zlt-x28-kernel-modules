#!/bin/sh
# Build tcp_bbr, sch_fq, sch_cake, xt_TPROXY and nf_tproxy_ipv4 for the ZLT X28 / X28 PRO kernel
# (MediaTek MT6890, Linux 4.19.205, vendor OpenWrt 19.07 firmware).
#
#   native arm64 host (tested: Raspberry Pi 5, Debian 12, gcc 12.2):  ./build/build.sh
#   x86_64 host with a cross compiler:      CROSS_COMPILE=aarch64-linux-gnu- ./build/build.sh
#
# Environment: WORK     work directory (default ~/zlt-x28-build, needs about 2 GB)
#              TARBALL  an already downloaded source tarball (skips the 160 MB download)
#              JOBS     parallel jobs (default: number of CPUs)
# Result: $WORK/out/*.ko, each checked against the router's symbol versions.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
WORK=${WORK:-$HOME/zlt-x28-build}
JOBS=${JOBS:-$(nproc)}
TAG=ASB-2021-09-05_4.19-stable
URL=https://android.googlesource.com/kernel/common/+archive/refs/tags/$TAG.tar.gz
TREE=$WORK/linux
MAKE="make ARCH=arm64 ${CROSS_COMPILE:+CROSS_COMPILE=$CROSS_COMPILE}"
OBJDUMP=${CROSS_COMPILE}objdump

mkdir -p "$WORK"
TARBALL=${TARBALL:-$WORK/$TAG.tar.gz}
if [ ! -f "$TARBALL" ]; then
	echo ">> downloading Android common kernel $TAG (about 160 MB)"
	curl -fL -o "$TARBALL" "$URL"
fi
if [ ! -f "$TREE/Makefile" ]; then
	echo ">> unpacking and applying patches/"
	mkdir -p "$TREE"
	tar xzf "$TARBALL" -C "$TREE"
	for p in "$ROOT"/patches/*.patch; do echo "   $(basename "$p")"; patch -s -d "$TREE" -p1 < "$p"; done
fi

cd "$TREE"
cp "$HERE/router-config" .config        # the router's own /proc/config.gz
touch .scmversion                        # keep the version string exactly 4.19.205
./scripts/config --module TCP_CONG_BBR --module NET_SCH_FQ --module NET_SCH_CAKE \
	--module NETFILTER_XT_TARGET_TPROXY --module NF_TPROXY_IPV4
$MAKE olddefconfig >/dev/null
echo ">> make modules_prepare"
$MAKE -j"$JOBS" modules_prepare >"$WORK/prepare.log" 2>&1 || { tail -n 30 "$WORK/prepare.log"; exit 1; }

# Symbol versions (CRCs) of the router kernel, read out of its kernel image with tools/ksymtab.py, plus
# those exported by the router's own x_tables / nf_defrag_ipv4 / nf_conntrack modules. modpost copies
# them into our modules, so the router's MODVERSIONS check accepts them.
cat "$HERE/router.symvers" "$HERE/router-modules.symvers" > Module.symvers

ext() {	# ext <name> <source...>: build the sources as one external module directory $WORK/<name>
	name=$1; shift
	d=$WORK/$name; objs=""
	rm -rf "$d"; mkdir -p "$d"
	for s in "$@"; do cp "$s" "$d/"; objs="$objs $(basename "$s" .c).o"; done
	echo "obj-m :=$objs" > "$d/Kbuild"
	echo ">> building$objs"
	$MAKE -C "$TREE" M="$d" modules >"$WORK/$name.log" 2>&1 || { tail -n 30 "$WORK/$name.log"; exit 1; }
}
ext bbr    net/ipv4/tcp_bbr.c
ext sched  net/sched/sch_fq.c net/sched/sch_cake.c
ext tproxy net/ipv4/netfilter/nf_tproxy_ipv4.c net/netfilter/xt_TPROXY.c

OUT=$WORK/out
rm -rf "$OUT"; mkdir -p "$OUT"
cp "$WORK"/bbr/*.ko "$WORK"/sched/*.ko "$WORK"/tproxy/*.ko "$OUT/"

echo ">> checking every imported symbol version against the router"
awk '{print $1, $2}' "$HERE/router.symvers" "$HERE/router-modules.symvers" "$WORK/tproxy/Module.symvers" > "$WORK/router-all.crcs"
fail=0
for k in "$OUT"/*.ko; do
	vm=$(strings "$k" | sed -n 's/^vermagic=//p')
	res=$(OBJDUMP=$OBJDUMP python3 "$ROOT/tools/verify_ko.py" "$k" "$WORK/router-all.crcs" | tail -n 1)
	printf '   %-20s %-44s %s\n' "$(basename "$k")" "$vm" "$res"
	case "$res" in *"problems: 0") ;; *) fail=1 ;; esac
done
[ $fail = 0 ] || { echo "!! some modules import symbols the router kernel does not have (see above)"; exit 1; }
echo ">> done: $OUT"
