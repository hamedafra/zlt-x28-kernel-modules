#!/bin/sh
# LAN traffic reaches sing-box without the TUN:
#   TCP  -> iptables REDIRECT (nat)   to the "redirect" inbound, port 12345
#   UDP  -> iptables TPROXY (mangle)  to the "tproxy" inbound,   port 12346, mark 0x1 -> table 101 (local)
# Once config.json has no tun inbound, the router's own DNS (dnsmasq upstream, port 53) is also sent to the
# tproxy inbound through OUTPUT marking, so sing-box keeps hijacking DNS. sing-box's own sockets carry
# route.default_mark 0xff and are left alone.
#
#   /etc/sing-box-redirect.sh apply    add everything (run by /etc/init.d/sing-box and firewall.user)
#   /etc/sing-box-redirect.sh remove   remove everything; without the TUN, LAN traffic then goes direct
#
# Kernel modules xt_TPROXY/nf_tproxy_ipv4 come from https://github.com/hamedafra/zlt-x28-kernel-modules and live
# in /data/tproxy. Not redirected: LAN/reserved/multicast destinations, the router's own addresses, and
# connections marked 0x10000 by an optional bypass rule (e.g. P2P from some LAN hosts; they go straight out).

TCP_PORT=12345
UDP_PORT=12346
TCHAIN=SB_TCP
UCHAIN=SB_UDP
DCHAIN=SB_DNS
MARK=0x1/0x1
SBMARK=0xff/0xff
TABLE=101
PREF=8900
MODDIR=/data/tproxy
CONFIG=/data/sing-box/config.json
RESERVED="0.0.0.0/8 10.0.0.0/8 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4"

load_modules() {
	for m in nf_defrag_ipv4 nf_tproxy_ipv4 xt_TPROXY; do
		grep -q "^$m " /proc/modules && continue
		if [ -f "$MODDIR/$m.ko" ]; then insmod "$MODDIR/$m.ko"; else insmod "$m" 2>/dev/null || modprobe "$m"; fi
	done
}

tun_present() {
	grep -q '"type": *"tun"' "$CONFIG"
}

remove() {
	while iptables -t nat -D PREROUTING -i br0 -p tcp -j $TCHAIN 2>/dev/null; do :; done
	iptables -t nat -F $TCHAIN 2>/dev/null; iptables -t nat -X $TCHAIN 2>/dev/null
	while iptables -t mangle -D PREROUTING -i br0 -p udp -j $UCHAIN 2>/dev/null; do :; done
	while iptables -t mangle -D PREROUTING -i lo -p udp --dport 53 -m mark --mark $MARK -j TPROXY --on-port $UDP_PORT --on-ip 0.0.0.0 --tproxy-mark $MARK 2>/dev/null; do :; done
	iptables -t mangle -F $UCHAIN 2>/dev/null; iptables -t mangle -X $UCHAIN 2>/dev/null
	while iptables -t mangle -D OUTPUT -p udp --dport 53 -j $DCHAIN 2>/dev/null; do :; done
	iptables -t mangle -F $DCHAIN 2>/dev/null; iptables -t mangle -X $DCHAIN 2>/dev/null
	while ip rule del pref $PREF 2>/dev/null; do :; done
	ip route flush table $TABLE 2>/dev/null
}

apply_tcp() {
	iptables -t nat -N $TCHAIN 2>/dev/null
	iptables -t nat -F $TCHAIN
	for net in $RESERVED; do iptables -t nat -A $TCHAIN -d $net -j RETURN; done
	iptables -t nat -A $TCHAIN -m addrtype --dst-type LOCAL -j RETURN
	iptables -t nat -A $TCHAIN -m mark --mark 0x10000/0x10000 -j RETURN
	iptables -t nat -A $TCHAIN -p tcp -j REDIRECT --to-ports $TCP_PORT
	iptables -t nat -C PREROUTING -i br0 -p tcp -j $TCHAIN 2>/dev/null ||
		iptables -t nat -I PREROUTING 1 -i br0 -p tcp -j $TCHAIN
}

apply_udp() {
	load_modules || return 1
	ip rule list | grep -q "^$PREF:" || ip rule add fwmark $MARK lookup $TABLE pref $PREF
	ip route replace local 0.0.0.0/0 dev lo table $TABLE
	iptables -t mangle -N $UCHAIN 2>/dev/null
	iptables -t mangle -F $UCHAIN
	for net in $RESERVED; do iptables -t mangle -A $UCHAIN -d $net -j RETURN; done
	iptables -t mangle -A $UCHAIN -m addrtype --dst-type LOCAL -j RETURN
	iptables -t mangle -A $UCHAIN -m mark --mark 0x10000/0x10000 -j RETURN
	iptables -t mangle -A $UCHAIN -p udp -j TPROXY --on-port $UDP_PORT --on-ip 0.0.0.0 --tproxy-mark $MARK
	# appended, so torrent-bypass's marking in PREROUTING runs first
	iptables -t mangle -C PREROUTING -i br0 -p udp -j $UCHAIN 2>/dev/null ||
		iptables -t mangle -A PREROUTING -i br0 -p udp -j $UCHAIN
}

apply_dns() {
	# router's own DNS queries: mark in OUTPUT -> rerouted to lo -> caught by TPROXY in PREROUTING
	iptables -t mangle -N $DCHAIN 2>/dev/null
	iptables -t mangle -F $DCHAIN
	iptables -t mangle -A $DCHAIN -m mark --mark $SBMARK -j RETURN
	# only truly local resolvers are skipped: the ISP's resolvers sit in 10/8 (10.255.255.254) and must be hijacked
	iptables -t mangle -A $DCHAIN -m addrtype --dst-type LOCAL -j RETURN
	for net in 127.0.0.0/8 192.168.0.0/16 172.16.0.0/12 10.0.50.0/24 224.0.0.0/4; do iptables -t mangle -A $DCHAIN -d $net -j RETURN; done
	iptables -t mangle -A $DCHAIN -j MARK --set-xmark $MARK
	iptables -t mangle -C OUTPUT -p udp --dport 53 -j $DCHAIN 2>/dev/null ||
		iptables -t mangle -A OUTPUT -p udp --dport 53 -j $DCHAIN
	iptables -t mangle -C PREROUTING -i lo -p udp --dport 53 -m mark --mark $MARK -j TPROXY --on-port $UDP_PORT --on-ip 0.0.0.0 --tproxy-mark $MARK 2>/dev/null ||
		iptables -t mangle -A PREROUTING -i lo -p udp --dport 53 -m mark --mark $MARK -j TPROXY --on-port $UDP_PORT --on-ip 0.0.0.0 --tproxy-mark $MARK
}

# While sing-box is down, dnsmasq asks the ISP directly and caches its filtered answers (10.10.34.x).
# Once sing-box is listening again, clear that cache once (runs in the background, waits up to 60 s).
flush_dns_cache_when_ready() {
	(
		i=0
		while [ $i -lt 60 ] && ! netstat -lun 2>/dev/null | grep -q ":$UDP_PORT "; do sleep 1; i=$((i+1)); done
		sleep 2
		killall -HUP dnsmasq 2>/dev/null && logger -t sing-box-redirect "dnsmasq cache cleared after sing-box start (waited ${i}s)"
	) </dev/null >/dev/null 2>&1 &
}

apply() {
	apply_tcp
	apply_udp
	tun_present || apply_dns
	flush_dns_cache_when_ready
}

case "$1" in
	apply) apply ;;
	remove) remove ;;
	*) echo "usage: $0 apply|remove"; exit 1 ;;
esac
