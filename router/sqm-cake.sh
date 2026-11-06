#!/bin/sh
# Smart queue management for the LTE WAN with CAKE. (fq for BBR pacing lives in /etc/init.d/bbr.)
# Modules sch_cake/sch_fq come from https://github.com/hamedafra/zlt-x28-kernel-modules and live in /data/kmods.
#
#   /etc/sqm-cake.sh apply|remove|status
#
# Settings: /etc/sqm-cake.conf (UP/DOWN in kbit, about 85% of what the link really does; measured
# on two LTE links: 24000-29000/58000-72000 and 14500/48000 kbit). 0 = no shaping in that direction.

WAN=ccmni1
IFB=ifb0
UP=12000
DOWN=40000
RTT=150ms
MODDIR=/data/kmods
[ -f /etc/sqm-cake.conf ] && . /etc/sqm-cake.conf

load_modules() {
	for m in sch_cake; do
		grep -q "^$m " /proc/modules || insmod "$MODDIR/$m.ko" || return 1
	done
	grep -q "^ifb " /proc/modules || insmod ifb numifbs=1 2>/dev/null || insmod /lib/modules/$(uname -r)/ifb.ko numifbs=1
}

apply() {
	load_modules || { echo "sqm: modules missing"; return 1; }
	[ -d /sys/class/net/$WAN ] || { echo "sqm: $WAN not present yet"; return 0; }
	# UP=0 / DOWN=0 means no shaping in that direction
	if [ "${UP:-0}" -gt 0 ]; then
		# upload: shape what leaves the modem
		tc qdisc replace dev $WAN root cake bandwidth ${UP}kbit rtt $RTT nat triple-isolate diffserv3 ack-filter
	else
		tc qdisc del dev $WAN root 2>/dev/null
	fi
	if [ "${DOWN:-0}" -gt 0 ]; then
		# download: mirror ingress of the modem into ifb0 and shape there
		ip link set $IFB up 2>/dev/null
		tc qdisc replace dev $WAN handle ffff: ingress
		tc filter del dev $WAN parent ffff: 2>/dev/null
		tc filter add dev $WAN parent ffff: matchall action mirred egress redirect dev $IFB
		tc qdisc replace dev $IFB root cake bandwidth ${DOWN}kbit rtt $RTT nat triple-isolate diffserv3 ingress
	else
		tc qdisc del dev $WAN ingress 2>/dev/null
		tc qdisc del dev $IFB root 2>/dev/null
		ip link set $IFB down 2>/dev/null
	fi
}

remove() {
	tc qdisc del dev $WAN root 2>/dev/null
	tc qdisc del dev $WAN ingress 2>/dev/null
	tc qdisc del dev $IFB root 2>/dev/null
	ip link set $IFB down 2>/dev/null
}

status() {
	for d in $WAN $IFB; do
		[ -d /sys/class/net/$d ] && tc -s qdisc show dev $d | grep -E "^qdisc|Sent|dropped" | sed "s/^/$d: /" | head -3
	done
}

case "$1" in
	apply) apply ;;
	remove) remove ;;
	status) status ;;
	*) echo "usage: $0 apply|remove|status"; exit 1 ;;
esac
