# Kernel modules for ZLT X28 / X28 PRO 5G routers (BBR, fq, CAKE, TPROXY)

[فارسی](README.fa.md)

![kernel](https://img.shields.io/badge/kernel-4.19.205-blue) ![SoC](https://img.shields.io/badge/SoC-MediaTek%20MT6890-orange) ![firmware](https://img.shields.io/badge/firmware-OpenWrt%2019.07%20vendor-green) ![license](https://img.shields.io/badge/license-GPL--2.0-lightgrey)

The ZLT X28 and X28 PRO run a vendor OpenWrt 19.07 with a MediaTek kernel that has no BBR, no `fq`,
no CAKE and no TPROXY, and the vendor publishes no kernel source or SDK. This repository has those five
modules, built so the stock kernel accepts them, plus the scripts that load them at boot and use them:

| Module | What it does | Loaded by |
|---|---|---|
| `tcp_bbr.ko` | BBR TCP congestion control | `router/init.d/bbr` |
| `sch_fq.ko` | `fq` qdisc, the pacing queue BBR is meant to run on (never caps bandwidth) | `router/init.d/bbr` |
| `sch_cake.ko` | CAKE smart queue management for the LTE/5G link (optional, off by default) | `router/sqm-cake.sh` |
| `nf_tproxy_ipv4.ko` | IPv4 transparent-proxy socket lookup | `router/sing-box-redirect.sh` |
| `xt_TPROXY.ko` | iptables `TPROXY` target (IPv4) | `router/sing-box-redirect.sh` |

`iptables-extensions/` has the matching userspace plugins `libxt_TPROXY.so` and `libxt_socket.so`.

Everything here has been running on two routers since 31 October 2026, through reboots, with no kernel
errors.

## Will it work on my router?

The modules only load into the exact kernel they were built for:

```sh
uname -r     # 4.19.205
uname -v     # #0 SMP Fri Dec 22 12:10:12 UTC 2023
cat /etc/openwrt_release | grep TARGET    # mt6890/evb6890v1_64_cpe_nand
```

If those match, the prebuilt modules fit. The kernel is built with `MODVERSIONS`, so a module built for a
different kernel is normally refused by `insmod` ("disagrees about version of symbol") instead of
crashing. To be sure, run `tools/extract-symvers.sh` against your router: it reads the kernel's symbol
table (read-only) and tells you whether it is identical to the one these modules were built against.

**No warranty.** These are kernel modules for a closed vendor kernel. Test with `insmod` from `/tmp`
first (a reboot removes them) before you make anything start at boot.

## Install

The routers have a persistent UBI volume at `/data` that survives firmware settings resets; everything
goes there. Replace `192.168.0.1` with your router.

### BBR + fq

```sh
ssh root@192.168.0.1 'mkdir -p /data/bbr'
scp modules/tcp_bbr.ko modules/sch_fq.ko root@192.168.0.1:/data/bbr/
scp router/init.d/bbr root@192.168.0.1:/etc/init.d/bbr
scp router/hotplug.d/iface/20-bbr-fq root@192.168.0.1:/etc/hotplug.d/iface/20-bbr-fq
ssh root@192.168.0.1 'chmod +x /etc/init.d/bbr; /etc/init.d/bbr enable; /etc/init.d/bbr start; /etc/init.d/bbr status'
```

`init.d/bbr` (START=19) loads both modules, sets `net.ipv4.tcp_congestion_control=bbr` and
`net.core.default_qdisc=fq`, and puts `fq` on `ccmni1` (the modem), `br0` and `br1`. The bridges and the
modem interface appear after the script runs at boot, so it retries for two minutes, and the hotplug
hook re-applies `fq` when an interface comes up again. Change `FQ_DEVS` if your interfaces differ.
`/etc/init.d/bbr stop` goes back to cubic + fq_codel and unloads the modules.

BBR only changes how the router's own TCP connections send (proxies such as sing-box running on the
router, downloads it makes). Measured on Irancell LTE: direct upload through the router went from
580 KB/s to 1.3 MB/s, because the link loses upload packets and cubic kept collapsing its window.

### TPROXY (transparent proxy for UDP)

```sh
ssh root@192.168.0.1 'mkdir -p /data/tproxy'
scp modules/nf_tproxy_ipv4.ko modules/xt_TPROXY.ko root@192.168.0.1:/data/tproxy/
scp iptables-extensions/libxt_TPROXY.so iptables-extensions/libxt_socket.so root@192.168.0.1:/usr/lib/iptables/
ssh root@192.168.0.1 'cd /data/tproxy; insmod nf_defrag_ipv4 2>/dev/null; insmod ./nf_tproxy_ipv4.ko; insmod ./xt_TPROXY.ko; iptables -t mangle -j TPROXY -h | tail -n 6'
```

`nf_defrag_ipv4` and `x_tables` are the router's own modules. The two plugins come from the official
OpenWrt 19.07.10 package `iptables-mod-tproxy_1.8.3-1_aarch64_generic.ipk` (the router has iptables
1.8.3) and are only included for convenience.

### sing-box without TUN (`router/sing-box-redirect.sh`)

This is what the TPROXY modules are for. Instead of a TUN interface, LAN traffic reaches
[sing-box](https://sing-box.sagernet.org/) through iptables, which costs much less CPU (about 2.5x less
per MB on these routers) and memory:

- **TCP**: `nat` chain `SB_TCP` → `REDIRECT` to a sing-box `redirect` inbound on port 12345.
- **UDP**: `mangle` chain `SB_UDP` → `TPROXY` to a sing-box `tproxy` inbound on port 12346, mark `0x1`,
  `ip rule` pref 8900 → table 101 (`local 0.0.0.0/0 dev lo`).
- **The router's own DNS** (dnsmasq's upstream queries): marked in `mangle OUTPUT` (chain `SB_DNS`),
  re-routed to `lo` and caught by TPROXY, so sing-box's DNS rules still apply. Only added when
  `config.json` has no `tun` inbound.
- Not redirected: private, reserved and multicast destinations, the router's own addresses, sing-box's
  own sockets (`route.default_mark: 255` in sing-box) and anything marked `0x10000` (an optional
  bypass, e.g. P2P from some LAN hosts).
- After sing-box (re)starts, dnsmasq's cache is cleared once: while sing-box is down, dnsmasq asks the
  ISP directly and would otherwise keep the ISP's filtered answers.

The sing-box side needs these inbounds:

```json
{ "type": "redirect", "tag": "redir-in",  "listen": "0.0.0.0", "listen_port": 12345 },
{ "type": "tproxy",   "tag": "tproxy-in", "listen": "0.0.0.0", "listen_port": 12346, "network": "udp" }
```

and `"route": { "default_mark": 255, ... }` plus a `hijack-dns` rule for DNS. Hook the script into the
service: `router/init.d/sing-box` is the init script used here (procd, `GOMEMLIMIT=50MiB GOGC=25`), whose
`service_started` / `service_stopped` call `sing-box-redirect.sh apply` / `remove`. Add
`router/firewall.user.snippet` to `/etc/firewall.user` so the rules come back after a firewall reload.
`router/check_router.sh` checks all of it after a reboot: `ssh root@192.168.0.1 'sh -s' < router/check_router.sh`.

### CAKE (optional)

```sh
ssh root@192.168.0.1 'mkdir -p /data/kmods'
scp modules/sch_cake.ko root@192.168.0.1:/data/kmods/
scp router/sqm-cake.sh root@192.168.0.1:/etc/sqm-cake.sh
scp router/init.d/sqm root@192.168.0.1:/etc/init.d/sqm
scp router/hotplug.d/iface/30-sqm root@192.168.0.1:/etc/hotplug.d/iface/30-sqm
ssh root@192.168.0.1 'chmod +x /etc/sqm-cake.sh /etc/init.d/sqm; printf "UP=24000\nDOWN=60000\n" > /etc/sqm-cake.conf; /etc/init.d/sqm start; /etc/init.d/sqm status'
```

Set `UP`/`DOWN` (kbit/s) to about 85% of what your link really does; `0` turns shaping off in that
direction. Download shaping uses `ifb0` (the router's own `ifb` module). CAKE caps your speed by design,
so only enable it (`/etc/init.d/sqm enable`) if bufferbloat bothers you more than the lost throughput.

## How the modules were built

There is no vendor kernel source, so the modules are built from Google's Android common kernel and made
to match the binary kernel:

1. **Source**: Android common kernel tag `ASB-2021-09-05_4.19-stable` (4.19.206). The 4.19.205 → 206 patch
   touches no TCP, socket, qdisc or module code, so `SUBLEVEL` is set to 205 (`patches/0001`) to give the
   exact version string `4.19.205 SMP mod_unload modversions aarch64`.
2. **Config**: the router's own `/proc/config.gz` (`build/router-config`), with the five options switched
   to `=m`.
3. **Symbol versions**: the kernel uses `MODVERSIONS`, so every symbol a module imports carries a CRC that
   must match the kernel's. The CRCs of a rebuilt kernel don't match MediaTek's (their structs differ), so
   they are read straight out of the router's kernel image instead: `tools/bootimg_kernel.py` pulls the
   kernel out of the `boot_a` partition and `tools/ksymtab.py` decodes its `__ksymtab` / `__kcrctab`
   tables into `build/router.symvers`. The CRCs exported by the router's own `x_tables`,
   `nf_defrag_ipv4` and `nf_conntrack` modules are in `build/router-modules.symvers`. The modules are
   built as external modules (`M=`) against a `Module.symvers` made of both, so modpost stamps the
   router's CRCs into them.
4. **Struct layouts**: matching CRCs only prove the names match. The real risk is a struct whose fields sit
   at different offsets in MediaTek's kernel. For every kernel function the modules depend on, the
   memory offsets used in the router's disassembly were compared with the same function in this build
   (`tools/compare.py`, `cmpfn.py`, `cmpmod.py`, `devoffs.py`; router disassembly in
   `verification/disassembly/`):
   - `tcp_sock`, `sock`, `inet_connection_sock`, `minmax`, `rate_sample`, `tcp_congestion_ops` (152 bytes)
     and `struct module` (896 bytes, init/exit at 0x170/0x318) are identical, so BBR needed no change.
   - `struct net_device` is **not**: MediaTek added fields, so `netdev_ops` sits 16 bytes later and
     `ip_ptr` 48 bytes later (at 760) than in vanilla 4.19. `patches/0002` adds two padding arrays so
     every offset the modules use matches. Checked afterwards with `devoffs.py` (`__dev_set_mtu`,
     `dev_get_flags`, `inet_select_addr` ... SAME), the qdisc helpers (`qdisc_reset`,
     `qdisc_watchdog_schedule_ns` ... SAME) and, module against module, the router's own `sch_tbf.ko`,
     `sch_hfsc.ko` and `xt_*.ko`.
5. **Missing exports**: the vendor kernel is built without TPROXY, so it doesn't export
   `udp4_lib_lookup`. `patches/0003` does what that function does internally (`__udp4_lib_lookup` +
   `refcount_inc_not_zero`). `patches/0004` drops the IPv6 half of `xt_TPROXY`, because there is no
   `nf_tproxy_ipv6` on the router.
6. **Check**: `tools/verify_ko.py` compares every entry in each module's `__versions` table with the
   router's CRCs. All imports match (BBR imports 10 symbols, all with the router's CRCs).

## Build it yourself

On an arm64 Linux machine (a Raspberry Pi 5 with Debian 12 and gcc 12.2 was used), or on x86_64 with an
`aarch64-linux-gnu-` cross compiler:

```sh
sudo apt install build-essential bc bison flex libssl-dev python3 curl     # Debian/Ubuntu
./build/build.sh                                       # native arm64
CROSS_COMPILE=aarch64-linux-gnu- ./build/build.sh      # cross
```

It downloads the kernel tarball (about 160 MB; pass `TARBALL=` to reuse one), applies `patches/`, runs
`modules_prepare` with the router config, builds the three external module directories and checks every
imported symbol version against the router. Output goes to `~/zlt-x28-build/out` (`WORK=` to change).
About 2 minutes on a Pi 5 once the tarball is downloaded.

The result has the same code (`.text`, `.rodata`, `.data`) as the prebuilt modules in `modules/`. One
detail: `xt_TPROXY.ko` imports three functions from `nf_tproxy_ipv4.ko`, and the version stamps between
those two differ from the prebuilt pair. Always load `xt_TPROXY.ko` and `nf_tproxy_ipv4.ko` from the same
set, both prebuilt or both rebuilt.

### A different firmware

If your router runs another kernel build, extract its symbol table and rebuild:

```sh
./tools/extract-symvers.sh root@192.168.0.1 mykernel     # read-only: copies boot_a and /proc/kallsyms
cp mykernel/router.symvers build/router.symvers
./build/build.sh
```

`router-modules.symvers` then also has to come from your router's `x_tables.ko`, `nf_defrag_ipv4.ko` and
`nf_conntrack.ko` (`nm <module>.ko | grep __crc_`). A different firmware may also change struct layouts;
re-run the comparisons in step 4 against your kernel before trusting the result (`ksymtab.py` assumes
the kernel's base address `0xffffff8008080000`, the first line of `/proc/kallsyms`).

## Repository layout

```
modules/               prebuilt .ko files (+ SHA256SUMS), exactly what runs on the routers
iptables-extensions/   libxt_TPROXY.so, libxt_socket.so from OpenWrt 19.07.10
patches/               the four source changes against ASB-2021-09-05_4.19-stable
build/                 build.sh, router-config, router.symvers, router-modules.symvers
tools/                 symbol extraction, CRC check and struct layout comparison tools
verification/          router kernel disassembly used for the layout checks
router/                init scripts, hotplug hooks, sing-box redirect/TPROXY script, CAKE script, checklist
```

## License

GPL-2.0, like the Linux kernel the modules and patches come from (see `LICENSE`). The iptables plugins
are GPL-2.0 binaries from the OpenWrt project.
