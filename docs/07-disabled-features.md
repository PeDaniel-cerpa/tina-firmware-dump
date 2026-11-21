# 07 - Disabled features found in the firmware

[Español](07-opciones-desactivadas.es.md) · [Back](../README.md)

**Keywords:** disabled features, hidden options, adb missing, telnetd disabled, S50telnet, S40network, S50adb, hostapd, wpa_supplicant, udhcpd, UCI config, device.xml, config_devmng.xml, DTB status disabled, debug flags, factory test panel

Analysis of the dumped M750 rootfs (`mtdblock2`, extracted to `m750root`) plus the TF811/backup variants. **Nothing was modified** in the firmware to produce this report.

---

## 1. Executive summary

| Question | Answer |
|---|---|
| Is there UCI configuration (`/etc/config/*`) to toggle? | **No.** `/etc/config` does not exist in this firmware. |
| Are services deliberately disabled? | **Yes**, three init scripts start with a bare `exit`. |
| Are the corresponding binaries present? | **Partly.** Some are, some are missing. |
| Can the shell/root access be enabled? | **Already done** via `/mnt/extsd/debug1` (see doc 02). |
| Can ADB be enabled? | **Not without adding `adbd`** — the binary is absent. |
| Can SSH be enabled? | **No**, neither `sshd` nor `dropbear` exists. |
| Is WiFi usable? | Binaries and configs exist, but the launch commands are commented out. |
| Is there a firewall to open? | **No.** No `iptables`, `firewall` config or DROP rules exist. |
| Are hardware features disabled? | **Yes**, the DTB has 48 nodes with `status = "disabled"`. |

Important: `/etc/init.d/rc.final:15-34` runs **every** `/etc/init.d/S??*` script regardless of `/etc/rc.d` symlinks. So a script not being linked in `rc.d` does **not** mean it is skipped.

---

## 2. Init scripts disabled with `exit`

| Script | Line | Code | What it would do if enabled |
|---|---:|---|---|
| `etc/init.d/S40network` | 5 | `exit` | `ifup -a`, `ifconfig eth0`, `udhcpc -b -R &` |
| `etc/init.d/S50telnet` | 5 | `exit` | `start-stop-daemon ... -x /usr/sbin/telnetd -- -F` |
| `etc/init.d/S50wifidaemon` | 5 | `exit` | `wifi_daemon`, `wifi -o sta` |
| `etc/init.d/S50adb` (backup variant only) | 2 | `exit` | `setusbconfig adb`, `adbd > /dev/null &` |

Also disabled but non-functional even if enabled:

| Item | Location | Problem |
|---|---|---|
| `webapp` | `S01app:93` (commented) | Binary absent |
| `log_guardian` | `S01app:94` (commented) | Binary absent |
| `hwclock -s` + date fix | `S01app:96-100` (commented) | DTB has RTC disabled |
| `usb_host` OTG role | `S00mpp:12` (commented) | Would break USB gadget/ADB |
| ACC-DET GPIO 239 | `S00mpp:19-20` (commented) | Hardware-specific |
| Front/AHD sensors | `S00mpp:7-8` | `FRONTSENSOR="none.ko"`, `AHDSENSOR="none.ko"` |
| Legacy WiFi modules | `rc.final:4-9`, `rc.modules:10-12` | `.ko` files absent |
| Serial console | `etc/inittab:31` | `#ttyS0::respawn:/sbin/getty ...` commented; bootargs has `console=` empty |
| Generic USB/SD auto-mount | `usr/bin/hotplug.sh:2,41` | Whole block wrapped in `: <<'COMMENTBLOCK'` |

---

## 3. Binaries present vs. missing

### Present (can be launched)

```text
/bin/busybox                 v1.27.2, 87 symlinks
/sbin/ifconfig, route, udhcpc, getty, insmod, hwclock, syslogd
/usr/sbin/hostapd            WiFi AP
/usr/sbin/wpa_supplicant     WiFi STA / P2P
/usr/sbin/wpa_cli            wpa_supplicant control
/usr/sbin/udhcpd             DHCP server
/usr/sbin/crond              cron (BusyBox)
/sbin/netifd, /sbin/ubusd    OpenWrt components, but without UCI
/usr/bin/setusbconfig        USB gadget: adb / mtp / uvc / uac1 / mass_storage / none
/usr/bin/sdvcam              main camera app, contains many hidden test strings
/lib/modules/4.9.191/8733bs.ko   real WiFi driver
```

BusyBox applets compiled but without a symlink: `ip`, `tftp`. Invoke as `/bin/busybox ip addr`.

### Missing (cannot be activated without supplying them)

```text
sshd, dropbear      -> no SSH at all
telnetd             -> S50telnet cannot work as-is
adbd                -> ADB impossible despite device.xml adbEnable="1"
ftpd, tftpd, httpd  -> no file/HTTP server in rootfs
nc, wget, ftpget    -> only in our external busybox_net on the SD
socat               -> only on the SD
iptables, ebtables  -> no firewall userspace
dbus-daemon         -> S50dbus exists but cannot start
wifi, wifi_daemon   -> S50wifidaemon cannot start
webapp, log_guardian, ota_update, healthd, klogd
xradio_*.ko, bcmdhd.ko, 8723ds.ko, sunxi_usb_udc.ko, sunxi_usbc.ko
```

Our external helper `files/busybox_net` adds: `telnetd`, `telnet`, `nc`, `httpd`, `wget`, `ftpget`, `ftpput`, `ntpd`, `klogd`.

---

## 4. UI / XML flags

`data/res/config/device.xml`:

```text
8:  adbEnable="1"     <- ADB requested, but adbd is missing
25: flags="0"         <- generic flag off
38: devGpsUart="dev/ttyS1"   <- missing leading slash AND UART1 is disabled in DTB
41: gpsSearch="0"     <- GPS off
42: radaSwitch="0"    <- radar off
```

`data/res/param/config_devmng.xml`:

```text
53: wifi_enable="1"
55: wifi_ssid_hide="0"
57: wifi_ap_ssid="M750-"
59: wifi_ap_password="12345678"
104: bFMSend="1"
105: bFMenable="0"       <- FM off (also disabled in DTB)
107: AUX_user="1"
108: AUX_enable="0"      <- AUX off
109: PBT_user="1"
110: PBT_enable="1"      <- Bluetooth classic on
111: ble_user="0"
112: ble_enable="0"      <- BLE off
155: admin_sys_psd="1333"   <- plaintext admin password
156: sys_psd="0000"
157: switch_sys_psd="0"     <- password protection off
```

`data/res/layout/home.xml:407-409`: a `test_board` UI group is commented out (hidden factory/test panel).

`usr/bin/lt_image.sh:38-49`: OTA preparation deliberately deletes `wpa_supplicant`, `udhcpd`, `hostapd`, `ping`, `ip`, `ifconfig`, `udhcpc` from the upgrade root.

---

## 5. WiFi: ready but not launched

| File | State |
|---|---|
| `etc/firmware/sta_ctrl.sh` | `wpa_supplicant` and `udhcpc` commands commented in every chip case |
| `etc/firmware/direct_ctrl.sh` | P2P setup commented in every chip case |
| `etc/firmware/ap_ctrl.sh` | Prepares `/var/run/hostapd`, but never runs `hostapd` |
| `etc/udhcpd.conf` | AP DHCP pool `192.168.10.250-254`, interface `wlan0` |
| `etc/firmware/p2p_udhcpd.conf` | P2P pool `192.168.50.20-254`, interface `p2p0` |
| `etc/wpa_supplicant.conf` | Contains test credentials `AWTest` / `1qaz@WSX` |
| `etc/firmware/ipscan.sh` | Scans `192.168.10.250-254`; called in the backup variant, **not** in M750 |

Only `8733bs.ko` is actually present. The scripts reference `8723ds.ko`, `bcmdhd.ko` and `xradio_*.ko`, which are absent.

---

## 6. Hardware disabled in the DTB

`dtc -I dtb -O dts dtb_descomprimido.bin` reports **48 nodes** with `status = "disabled"`. Notable ones:

```text
uart1@2500400      -> GPS / secondary serial
spi-nand@0, spi1..3, spif0 -> SPI / NAND
twi0, twi1          -> I2C
fmsend              -> FM radio
rtc@7090000         -> no battery-backed clock
da380, es8388       -> audio codecs
dmic_*, daudio0_*   -> digital audio
gmac0               -> Ethernet
sensor0, sensor1, csi2, vinc00..vinc33  -> cameras
actuator0, flash0   -> camera focus/flash
e907_rproc          -> coprocessor
```

USB is **not** disabled: `udc-controller@0x4100000` is `status = "okay"`.

Runtime bootargs also disable visibility:

```text
console=            loglevel=0
```

The DTS has a different string (`console=ttyS0`, `loglevel=8`) but the runtime command line wins.

---

## 7. What can be activated without reflashing

All of these are possible through the SD hook (`/mnt/extsd/debug1`) or by writing to the overlay `/overlay/upper`. They are **temporary unless persisted in the overlay**.

```sh
# Remote shell / telnet (already in our debug1)
/mnt/extsd/busybox_net telnetd -p 2323 -l /bin/sh &

# HTTP server for the SD contents
/mnt/extsd/busybox_net httpd -h /mnt/extsd -p 8080 &

# Network tools not present in the rootfs
/mnt/extsd/busybox_net nc -l -p 5555 -e /bin/sh
/bin/busybox ip addr
/bin/busybox ip route

# NTP (device has no RTC)
/mnt/extsd/busybox_net ntpd -N -p 0.openwrt.pool.ntp.org &

# WiFi AP manual (requires 8733bs.ko to load)
cat > /tmp/hostapd.conf <<'EOF'
interface=wlan0
driver=nl80211
ssid=M750-TEST
hw_mode=g
channel=6
wpa=2
wpa_passphrase=12345678
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF
ifconfig wlan0 up
ifconfig wlan0 192.168.10.1 netmask 255.255.255.0
/usr/sbin/hostapd /tmp/hostapd.conf &
/usr/sbin/udhcpd /etc/udhcpd.conf &

# UI flags (may be reverted by sdvcam)
cp /data/res/config/device.xml /mnt/extsd/device.xml.bak
sed -i 's/gpsSearch="0"/gpsSearch="1"/' /data/res/config/device.xml
killall sdvcam; /usr/bin/sdvcam &
```

**Risks:** `telnetd -l /bin/sh` and `nc -e /bin/sh` give unauthenticated root. WiFi experiments can conflict with the product AP (`sdvcam` also manages `192.168.10.1`). GPS needs both the XML flag **and** UART1 enabled in the DTB, plus a valid path instead of `dev/ttyS1`. FM needs `fmsend` enabled in the DTB. BLE depends on `gocsdk` and real Bluetooth hardware.

---

## 8. What requires reflashing / rebuilding

- Permanent `adbd`, `telnetd`, `sshd`/`dropbear` inside rootfs.
- `dbus-daemon`, `wifi`/`wifi_daemon`, `webapp`, `log_guardian`, `ota_update`, `klogd`.
- `iptables` / firewall.
- Additional or missing `.ko` modules.
- Changing disabled DTB nodes (Ethernet, UART1, cameras, I2C, RTC, audio, e907).
- Changing bootargs (`console=`, `loglevel=`).

The base rootfs is a read-only squashfs (`mtdblock2`), so persistent changes go either to the jffs2 overlay (`/overlay/upper`, only ~320 KB) or to a rebuilt `mtdblock2` image (see doc 05).

---

## 9. Quick conclusion

The firmware is an **incomplete OpenWrt-like build**: it has OpenWrt init scripts but no UCI, no `procd`, no `validate_data`, no firewall and no `/sbin/wifi`. Most "disabled options" are therefore scripts that cannot work even if uncommented, because their binaries are missing.

The practical levers are:

1. The SD hook — already working, gives root on every boot.
2. The external `busybox_net` — adds all the missing network tools temporarily.
3. The overlay — for small persistent file replacements.
4. XML flags — only if the app accepts them and the hardware is actually enabled.
5. Rebuilding `mtdblock2` + DTB — for real feature changes.

---

## 10. Practical example: changing the AP SSID

The XML is only the default. The **actual SSID lives in `/data/param.bin`**, as fixed 64-byte string slots:

```text
offset 1880: Hunk125r          (device/BT name)
offset 1944: M750BT_           (BT prefix)
offset 2072: english           (language)
offset 2136: M750-60811d4b     <- FULL AP SSID (prefix + MAC suffix)
offset 2200: M750-             <- AP SSID prefix
offset 2264: 12345678          <- AP password
offset 2328: zlink             <- station SSID
```

That explains why the factory network appears as `M750-xxxx`: `sdvcam` takes the prefix at offset 2200 and appends the last bytes of the `wlan0` MAC (written to `/tmp/apmac.txt` by `etc/firmware/apmac.sh`).

To set an exact SSID such as `Hunk-125r`, patch **both** slots 2136 and 2200 and also the two XML keys (`wifi_ap_ssid`, `wifiApSsid`). Use [`files/debug1-wifi-ssid.sh`](../files/debug1-wifi-ssid.sh) with these files in the SD root:

```text
F:\debug1                     <- the SSID script renamed to debug1
F:\param_hunk.bin             <- patched param.bin
F:\config_devmng_hunk.xml     <- patched XML
```

The script saves `param.bin.bak` and `config_devmng.xml.bak` on the SD, copies the files to `/data` and `/overlay/upper/data`, dumps `/tmp/apmac.txt` into `firmware_dump/`, and creates `wifi_ssid.done`. Since `S01app` runs `debug1` **before** starting `sdvcam`, the app reads the new values at startup.

**Rollback:** restore the `.bak` files to their original names, delete `wifi_ssid.done` and boot once.
