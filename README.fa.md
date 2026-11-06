<div dir="rtl">

# ماژول‌های کرنل برای مودم‌های ۵G مدل ZLT X28 و X28 PRO

### BBR، fq، CAKE و TPROXY

[English](README.md)

![kernel](https://img.shields.io/badge/kernel-4.19.205-blue) ![SoC](https://img.shields.io/badge/SoC-MediaTek%20MT6890-orange) ![firmware](https://img.shields.io/badge/firmware-OpenWrt%2019.07%20vendor-green) ![license](https://img.shields.io/badge/license-GPL--2.0-lightgrey)

مودم‌های ۵G مدل ZLT X28 و X28 PRO یه OpenWrt 19.07 سفارشی
دارن با کرنل مدیاتک که BBR، صف `fq`، CAKE و TPROXY نداره. سازنده هم سورس کرنل یا SDK منتشر نکرده.
این مخزن این پنج ماژول رو داره، طوری ساخته‌شده که کرنل اصلی خود مودم قبولشون کنه، به‌علاوهٔ
اسکریپت‌هایی که موقع بوت لودشون می‌کنن و ازشون استفاده می‌کنن:

| ماژول | کارش | چی لودش می‌کنه |
|---|---|---|
| `tcp_bbr.ko` | الگوریتم کنترل ازدحام BBR برای TCP | `router/init.d/bbr` |
| `sch_fq.ko` | صف `fq`، صفی که BBR برای تنظیم سرعت ارسال روش طراحی شده (سرعت رو محدود نمی‌کنه) | `router/init.d/bbr` |
| `sch_cake.ko` | مدیریت صف CAKE برای لینک LTE/5G (اختیاری، پیش‌فرض خاموش) | `router/sqm-cake.sh` |
| `nf_tproxy_ipv4.ko` | پیدا کردن سوکت برای پروکسی شفاف IPv4 | `router/sing-box-redirect.sh` |
| `xt_TPROXY.ko` | تارگت `TPROXY` در iptables (IPv4) | `router/sing-box-redirect.sh` |

پلاگین‌های سمت iptables هم (`libxt_TPROXY.so` و `libxt_socket.so`) توی پوشهٔ `iptables-extensions/` هستن.

همهٔ این‌ها از ۳۱ اکتبر ۲۰۲۶ روی دو مودم، با چند بار ریبوت، بدون هیچ خطای کرنلی کار می‌کنن.

## روی مودم من کار می‌کنه؟

ماژول‌ها فقط روی دقیقاً همون کرنلی لود می‌شن که براش ساخته شدن. روی مودم این‌ها رو بزن:

<div dir="ltr">

```sh
uname -r     # 4.19.205
uname -v     # #0 SMP Fri Dec 22 12:10:12 UTC 2023
cat /etc/openwrt_release | grep TARGET    # mt6890/evb6890v1_64_cpe_nand
```

</div>

اگه این‌ها یکی بود، ماژول‌های آماده به مودمت می‌خورن. کرنل با `MODVERSIONS` ساخته شده، پس ماژولی که
برای یه کرنل دیگه ساخته شده معمولاً موقع `insmod` رد می‌شه («disagrees about version of symbol»)، نه
این‌که مودم رو کرش کنه. برای اطمینان کامل، `tools/extract-symvers.sh` رو روی مودمت اجرا کن. این اسکریپت
فقط جدول نمادهای کرنل رو می‌خونه و چیزی روی مودم نمی‌نویسه، و می‌گه با جدولی که این ماژول‌ها باهاش
ساخته شدن یکیه یا نه.

**هیچ ضمانتی نیست.** این‌ها ماژول کرنل برای یه کرنل بسته‌ی سازنده‌ان. اول از `/tmp` با `insmod` تستشون
کن (با ریبوت پاک می‌شن)، بعد کاری کن که موقع بوت خودکار اجرا بشن.

## نصب

مودم یه پارتیشن دائمی در `/data` داره که با ریست تنظیمات پاک نمی‌شه. همه‌چی می‌ره اون‌جا. به جای
`192.168.0.1` آدرس مودم خودت رو بذار. دستورها رو از کامپیوتری بزن که این مخزن رو روش دانلود کردی.

### BBR و fq

<div dir="ltr">

```sh
ssh root@192.168.0.1 'mkdir -p /data/bbr'
scp modules/tcp_bbr.ko modules/sch_fq.ko root@192.168.0.1:/data/bbr/
scp router/init.d/bbr root@192.168.0.1:/etc/init.d/bbr
scp router/hotplug.d/iface/20-bbr-fq root@192.168.0.1:/etc/hotplug.d/iface/20-bbr-fq
ssh root@192.168.0.1 'chmod +x /etc/init.d/bbr; /etc/init.d/bbr enable; /etc/init.d/bbr start; /etc/init.d/bbr status'
```

</div>

اسکریپت `init.d/bbr` (با START=19) هر دو ماژول رو لود می‌کنه، `tcp_congestion_control` رو روی `bbr` و
`default_qdisc` رو روی `fq` می‌ذاره و `fq` رو روی `ccmni1` (مودم)، `br0` و `br1` می‌ذاره. چون بریج‌ها و
رابط مودم بعد از اجرای این اسکریپت ساخته می‌شن، تا دو دقیقه دوباره تلاش می‌کنه، و هوک hotplug هم هر
وقت رابطی دوباره بالا اومد `fq` رو برمی‌گردونه. اگه اسم رابط‌هات فرق داره، `FQ_DEVS` رو عوض کن.
`/etc/init.d/bbr stop` همه‌چی رو به cubic و fq_codel برمی‌گردونه و ماژول‌ها رو خارج می‌کنه.

BBR فقط روی اتصال‌های TCP ای اثر داره که خود مودم می‌سازه، مثل پروکسی‌هایی که روی مودم اجرا می‌شن
(sing-box) یا دانلودهای خود مودم. روی LTE ایرانسل، آپلود مستقیم از ۵۸۰ کیلوبایت به ۱.۳ مگابایت بر ثانیه
رسید، چون این لینک بسته‌های آپلود رو گم می‌کنه و cubic مدام پنجره‌ش رو نصف می‌کرد.

### TPROXY (پروکسی شفاف برای UDP)

<div dir="ltr">

```sh
ssh root@192.168.0.1 'mkdir -p /data/tproxy'
scp modules/nf_tproxy_ipv4.ko modules/xt_TPROXY.ko root@192.168.0.1:/data/tproxy/
scp iptables-extensions/libxt_TPROXY.so iptables-extensions/libxt_socket.so root@192.168.0.1:/usr/lib/iptables/
ssh root@192.168.0.1 'cd /data/tproxy; insmod nf_defrag_ipv4 2>/dev/null; insmod ./nf_tproxy_ipv4.ko; insmod ./xt_TPROXY.ko; iptables -t mangle -j TPROXY -h | tail -n 6'
```

</div>

`nf_defrag_ipv4` و `x_tables` ماژول‌های خود مودم‌ان. دو پلاگین iptables از بستهٔ رسمی OpenWrt 19.07.10
(`iptables-mod-tproxy_1.8.3-1_aarch64_generic.ipk`) برداشته شدن، چون iptables مودم نسخهٔ 1.8.3 ـه.

### sing-box بدون TUN (`router/sing-box-redirect.sh`)

TPROXY برای همین ساخته شد. به جای رابط TUN، ترافیک شبکهٔ خونه از طریق iptables به
[sing-box](https://sing-box.sagernet.org/) می‌رسه. روی این مودم‌ها این کار CPU رو حدود ۲.۵ برابر کمتر
مصرف می‌کنه و حافظهٔ کمتری هم می‌خواد:

- **TCP**: زنجیرهٔ `SB_TCP` در جدول `nat` با `REDIRECT` به ورودی `redirect` ـه sing-box روی پورت 12345.
- **UDP**: زنجیرهٔ `SB_UDP` در جدول `mangle` با `TPROXY` به ورودی `tproxy` ـه sing-box روی پورت 12346،
  با مارک `0x1` و `ip rule` با اولویت 8900 به جدول 101 (`local 0.0.0.0/0 dev lo`).
- **DNS خود مودم** (درخواست‌هایی که dnsmasq به سرور اپراتور می‌فرسته): در `mangle OUTPUT` (زنجیرهٔ
  `SB_DNS`) مارک می‌خوره، به `lo` برمی‌گرده و TPROXY می‌گیردش. این‌طوری قانون‌های DNS ـه sing-box روی
  اون‌ها هم اعمال می‌شه. فقط وقتی اضافه می‌شه که `config.json` ورودی `tun` نداشته باشه.
- منتقل نمی‌شن: مقصدهای خصوصی، رزرو و مالتی‌کست، آدرس‌های خود مودم، سوکت‌های خود sing-box
  (`route.default_mark: 255`) و هر چیزی که مارک `0x10000` داره (یه استثنای اختیاری، مثلاً برای تورنت
  بعضی دستگاه‌ها).
- بعد از هر بار روشن شدن sing-box، کش dnsmasq یک بار خالی می‌شه. چون وقتی sing-box خاموشه، dnsmasq
  مستقیم از اپراتور می‌پرسه و بدون این کار جواب‌های فیلترشده (10.10.34.x) توی کشش می‌مونن.

sing-box این ورودی‌ها رو لازم داره:

<div dir="ltr">

```json
{ "type": "redirect", "tag": "redir-in",  "listen": "0.0.0.0", "listen_port": 12345 },
{ "type": "tproxy",   "tag": "tproxy-in", "listen": "0.0.0.0", "listen_port": 12346, "network": "udp" }
```

</div>

به‌علاوهٔ `"route": { "default_mark": 255, ... }` و یه قانون `hijack-dns` برای DNS. اسکریپت رو به
سرویس وصل کن: `router/init.d/sing-box` همون اسکریپت init ـیه که این‌جا استفاده می‌شه (procd، با
`GOMEMLIMIT=50MiB GOGC=25`) و `service_started` و `service_stopped` ـش به‌ترتیب
`sing-box-redirect.sh apply` و `remove` رو صدا می‌زنن. محتوای `router/firewall.user.snippet` رو هم به
`/etc/firewall.user` اضافه کن تا بعد از ریلود فایروال قانون‌ها برگردن. برای چک کردن همه‌چی بعد از ریبوت:

<div dir="ltr">

```sh
ssh root@192.168.0.1 'sh -s' < router/check_router.sh
```

</div>

### CAKE (اختیاری)

<div dir="ltr">

```sh
ssh root@192.168.0.1 'mkdir -p /data/kmods'
scp modules/sch_cake.ko root@192.168.0.1:/data/kmods/
scp router/sqm-cake.sh root@192.168.0.1:/etc/sqm-cake.sh
scp router/init.d/sqm root@192.168.0.1:/etc/init.d/sqm
scp router/hotplug.d/iface/30-sqm root@192.168.0.1:/etc/hotplug.d/iface/30-sqm
ssh root@192.168.0.1 'chmod +x /etc/sqm-cake.sh /etc/init.d/sqm; printf "UP=24000\nDOWN=60000\n" > /etc/sqm-cake.conf; /etc/init.d/sqm start; /etc/init.d/sqm status'
```

</div>

`UP` و `DOWN` (به کیلوبیت بر ثانیه) رو حدود ۸۵٪ سرعت واقعی لینکت بذار. `0` یعنی اون جهت محدود نشه.
محدودسازی دانلود با `ifb0` (ماژول `ifb` خود مودم) انجام می‌شه. CAKE ذاتاً سرعت رو محدود می‌کنه، پس
فقط وقتی فعالش کن (`/etc/init.d/sqm enable`) که تأخیر زیر بار (bufferbloat) برات مهم‌تر از سرعت باشه.

## ماژول‌ها چطور ساخته شدن

سورس کرنل سازنده در دسترس نیست. برای همین ماژول‌ها از کرنل مشترک اندروید گوگل ساخته شدن و با کرنل
باینری مودم جور شدن:

۱. **سورس**: کرنل مشترک اندروید با تگ `ASB-2021-09-05_4.19-stable` (نسخهٔ 4.19.206). پچ 4.19.205 به
206 هیچ کدی از TCP، سوکت، صف‌ها یا ماژول‌ها رو عوض نمی‌کنه، پس `SUBLEVEL` روی 205 گذاشته شد
(`patches/0001`) تا رشتهٔ نسخه دقیقاً `4.19.205 SMP mod_unload modversions aarch64` بشه.

۲. **تنظیمات**: همون `/proc/config.gz` خود مودم (`build/router-config`)، با پنج گزینهٔ لازم روی `=m`.

۳. **نسخهٔ نمادها**: کرنل با `MODVERSIONS` ساخته شده، یعنی هر تابعی که ماژول از کرنل می‌گیره یه CRC
داره که باید با CRC کرنل یکی باشه. CRC ـه کرنلی که دوباره ساخته بشی با مال مدیاتک جور نیست، چون
ساختارهاشون فرق داره. برای همین CRC ها مستقیم از فایل کرنل خود مودم خونده شدن:
`tools/bootimg_kernel.py` کرنل رو از پارتیشن `boot_a` بیرون می‌کشه و `tools/ksymtab.py` جدول‌های
`__ksymtab` و `__kcrctab` ـش رو به `build/router.symvers` تبدیل می‌کنه. CRC های ماژول‌های خود مودم
(`x_tables`، `nf_defrag_ipv4`، `nf_conntrack`) هم در `build/router-modules.symvers` هستن. ماژول‌ها به‌صورت
ماژول خارجی (`M=`) با این جدول ساخته می‌شن، پس CRC های خود مودم داخلشون نوشته می‌شه.

۴. **چیدمان ساختارها**: یکی بودن CRC فقط یعنی اسم‌ها جورن. خطر واقعی ساختاری‌یه که فیلدهاش توی کرنل
مدیاتک جای دیگه‌ای باشن. برای هر تابع کرنل که ماژول‌ها بهش وابسته‌ان، آفست‌های حافظه‌ای که توی
دیس‌اسمبلی کرنل مودم استفاده شده با همون تابع در این بیلد مقایسه شد (`tools/compare.py`،
`cmpfn.py`، `cmpmod.py`، `devoffs.py`؛ دیس‌اسمبلی مودم در `verification/disassembly/`):
   - `tcp_sock`، `sock`، `inet_connection_sock`، `minmax`، `rate_sample`، `tcp_congestion_ops` (۱۵۲ بایت)
     و `struct module` (۸۹۶ بایت، init و exit در 0x170 و 0x318) دقیقاً یکی‌ان، پس BBR هیچ تغییری نخواست.
   - `struct net_device` **یکی نیست**: مدیاتک فیلد اضافه کرده، پس `netdev_ops` ۱۶ بایت و `ip_ptr` ۴۸
     بایت (در 760) دیرتر از لینوکس استاندارد 4.19 قرار گرفته‌ان. `patches/0002` دو آرایهٔ پرکننده اضافه
     می‌کنه تا همهٔ آفست‌هایی که ماژول‌ها استفاده می‌کنن جور بشن. بعدش دوباره با `devoffs.py`
     (`__dev_set_mtu`، `dev_get_flags`، `inet_select_addr` و... همه SAME)، توابع صف
     (`qdisc_reset`، `qdisc_watchdog_schedule_ns` و... SAME) و مقایسهٔ ماژول به ماژول با `sch_tbf.ko`،
     `sch_hfsc.ko` و `xt_*.ko` ـه خود مودم چک شد.

۵. **تابع‌های ناموجود**: کرنل سازنده بدون TPROXY ساخته شده و تابع `udp4_lib_lookup` رو صادر نمی‌کنه.
`patches/0003` همون کاری رو که این تابع در داخل انجام می‌ده مستقیم انجام می‌ده (`__udp4_lib_lookup` +
`refcount_inc_not_zero`). `patches/0004` بخش IPv6 ـه `xt_TPROXY` رو حذف می‌کنه، چون `nf_tproxy_ipv6`
روی مودم نیست.

۶. **بررسی نهایی**: `tools/verify_ko.py` تک‌تک ورودی‌های جدول `__versions` هر ماژول رو با CRC های مودم
مقایسه می‌کنه. همه جورن (BBR مثلاً ۱۰ تابع وارد می‌کنه که CRC همه‌شون مال خود مودمه).

## خودت بسازش

روی یه لینوکس arm64 (این‌جا Raspberry Pi 5 با Debian 12 و gcc 12.2 استفاده شد)، یا روی x86_64 با
کامپایلر متقاطع `aarch64-linux-gnu-`:

<div dir="ltr">

```sh
sudo apt install build-essential bc bison flex libssl-dev python3 curl     # Debian/Ubuntu
./build/build.sh                                       # native arm64
CROSS_COMPILE=aarch64-linux-gnu- ./build/build.sh      # cross
```

</div>

اسکریپت سورس کرنل رو دانلود می‌کنه (حدود ۱۶۰ مگابایت؛ با `TARBALL=` می‌تونی یه فایل دانلودشده بهش
بدی)، پچ‌های `patches/` رو می‌زنه، `modules_prepare` رو با تنظیمات مودم اجرا می‌کنه، سه پوشهٔ ماژول
خارجی رو می‌سازه و نسخهٔ همهٔ نمادهای واردشده رو با مودم مقایسه می‌کنه. خروجی در
`~/zlt-x28-build/out` ـه (با `WORK=` عوضش کن). روی Pi 5، بعد از دانلود سورس، حدود ۲ دقیقه طول می‌کشه.

کد خروجی (`.text`، `.rodata`، `.data`) دقیقاً با ماژول‌های آمادهٔ `modules/` یکیه. فقط یه نکته:
`xt_TPROXY.ko` سه تابع از `nf_tproxy_ipv4.ko` وارد می‌کنه و نشون نسخهٔ بین این دو با جفت آماده فرق
داره. پس `xt_TPROXY.ko` و `nf_tproxy_ipv4.ko` رو همیشه از یه مجموعه لود کن: یا هر دو آماده، یا هر دو
ساخته‌شده توسط خودت.

### فریمور متفاوت

اگه مودمت کرنل دیگه‌ای داره، جدول نمادهاش رو بیرون بکش و دوباره بساز:

<div dir="ltr">

```sh
./tools/extract-symvers.sh root@192.168.0.1 mykernel     # read-only: copies boot_a and /proc/kallsyms
cp mykernel/router.symvers build/router.symvers
./build/build.sh
```

</div>

اون‌وقت `router-modules.symvers` هم باید از `x_tables.ko`، `nf_defrag_ipv4.ko` و `nf_conntrack.ko` ـه
مودم خودت ساخته بشه (`nm <module>.ko | grep __crc_`). فریمور دیگه ممکنه چیدمان ساختارها رو هم عوض کرده
باشه. قبل از اعتماد به نتیجه، مقایسه‌های مرحلهٔ ۴ رو روی کرنل خودت تکرار کن. (`ksymtab.py` فرض می‌کنه
آدرس پایهٔ کرنل `0xffffff8008080000` ـه، یعنی اولین خط `/proc/kallsyms`.)

## ساختار مخزن

<div dir="ltr">

```
modules/               prebuilt .ko files (+ SHA256SUMS), exactly what runs on the routers
iptables-extensions/   libxt_TPROXY.so, libxt_socket.so from OpenWrt 19.07.10
patches/               the four source changes against ASB-2021-09-05_4.19-stable
build/                 build.sh, router-config, router.symvers, router-modules.symvers
tools/                 symbol extraction, CRC check and struct layout comparison tools
verification/          router kernel disassembly used for the layout checks
router/                init scripts, hotplug hooks, sing-box redirect/TPROXY script, CAKE script, checklist
```

</div>

## مجوز

GPL-2.0، مثل خود کرنل لینوکس که ماژول‌ها و پچ‌ها ازش اومدن (فایل `LICENSE`). پلاگین‌های iptables
فایل‌های باینری GPL-2.0 از پروژهٔ OpenWrt ـن.

</div>
