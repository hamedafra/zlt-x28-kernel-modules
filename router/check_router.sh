#!/bin/sh
# Post-reboot checks (modules, BBR/fq, sing-box redirect/TPROXY rules, DNS):
#   ssh root@<router> 'sh -s' < check_router.sh
ok() { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; }
echo "uptime: $(cut -d. -f1 /proc/uptime)s  temp=$(($(cat /sys/class/thermal/thermal_zone0/temp)/1000))C  free=$(awk '/MemFree/{print int($2/1024)}' /proc/meminfo)MB  load=$(cut -d' ' -f1 /proc/loadavg)"
for m in tcp_bbr sch_fq xt_TPROXY nf_tproxy_ipv4; do grep -q "^$m " /proc/modules && ok "module $m loaded" || bad "module $m NOT loaded"; done
grep -q "^sch_cake " /proc/modules && bad "sch_cake loaded (should be off)" || ok "sch_cake not loaded (sqm off)"
[ "$(cat /proc/sys/net/ipv4/tcp_congestion_control)" = bbr ] && ok "congestion control bbr" || bad "congestion control $(cat /proc/sys/net/ipv4/tcp_congestion_control)"
[ "$(cat /proc/sys/net/core/default_qdisc)" = fq ] && ok "default qdisc fq" || bad "default qdisc $(cat /proc/sys/net/core/default_qdisc)"
for d in ccmni1 br0 br1; do tc qdisc show dev $d 2>/dev/null | grep -q "^qdisc fq " && ok "fq on $d" || bad "no fq on $d: $(tc qdisc show dev $d | head -1 | cut -c1-30)"; done
p=$(pidof sing-box); [ -n "$p" ] && ok "sing-box running (pid $p, rss $(awk '/VmRSS/{print int($2/1024)}' /proc/$p/status)MB)" || bad "sing-box NOT running"
ip link show tun0 >/dev/null 2>&1 && bad "tun0 exists" || ok "no tun0"
netstat -lnt 2>/dev/null | grep -q ":12345 " && ok "redirect inbound 12345 listening" || bad "12345 not listening"
netstat -lnu 2>/dev/null | grep -q ":12346 " && ok "tproxy inbound 12346 listening" || bad "12346 not listening"
for port in 3120 3128; do netstat -lnt 2>/dev/null | grep -q ":$port " && ok "proxy port $port listening" || bad "port $port not listening"; done
iptables -t nat -S PREROUTING | grep -q "SB_TCP" && ok "nat SB_TCP hooked" || bad "nat SB_TCP missing"
iptables -t mangle -S PREROUTING | grep -q "SB_UDP" && ok "mangle SB_UDP hooked" || bad "mangle SB_UDP missing"
iptables -t mangle -S PREROUTING | grep -q "TPROXY" && ok "lo DNS TPROXY rule" || bad "lo DNS TPROXY rule missing"
iptables -t mangle -S OUTPUT | grep -q "SB_DNS" && ok "mangle SB_DNS (router DNS reroute)" || bad "SB_DNS missing"
# optional P2P bypass (mark 0x10000), only if you use one
iptables -t mangle -S PREROUTING | grep -q "torrent_bypass" && ok "torrent_bypass hooked" || echo "  --   no torrent_bypass chain (optional)"
ip rule | grep -q "^8900:.*0x1/0x1 lookup 101" && ok "ip rule 8900 -> table 101" || bad "ip rule 8900 missing"
ip route show table 101 | grep -q "^local default dev lo" && ok "table 101 local route" || bad "table 101 route missing"
ip rule | grep -q "^8500:.*0x10000/0x10000 lookup main" && ok "bypass ip rule" || echo "  --   no bypass ip rule (optional)"
a=$(nslookup instagram.com 2>/dev/null | awk '/^Address 1/{print $3}'); case "$a" in 10.*|"") bad "router DNS instagram.com -> ${a:-none}";; *) ok "router DNS instagram.com -> $a";; esac
a=$(nslookup digikala.com 2>/dev/null | awk '/^Address 1/{print $3}'); [ -n "$a" ] && ok "router DNS digikala.com -> $a" || bad "router DNS digikala.com failed"
n=$(dmesg | grep -iE "oops|bug:|panic|call trace" | grep -vc "lock debugging due to kernel taint"); [ "$n" = 0 ] && ok "kernel log clean" || bad "kernel log has $n error lines"
