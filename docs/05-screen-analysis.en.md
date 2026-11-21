# 05 - Analysis of the two screens

[Español](05-analisis-pantallas.md) · [Back](../README.en.md)

The procedure was applied to **two different physical screens**. This document records the real differences found in the dumps and helps avoid mixing firmwares.

---

## Comparison summary

| Item | Screen 1 - TF811 | Screen 2 - M750 |
|---|---|---|
| WiFi SSID | `TF811-xxxx` | `M750-xxxx` |
| Bluetooth | `TF811BT_` | `M750BT_` |
| Software (config_devmng.xml) | `TF811 2026-08-01 8733` | `M750 2026-08-15` |
| Build ID | `tina.zengfu.20260302.022659` | `tina.zhangxiangpu.20260815.011909` |
| Target | `v837s-perf1/generic v2.1` | `v853-perf1/generic v2.1` |
| U-Boot | `2018.07-g49ba65b-dirty (01/14/2026)` | `2018.07-g7572878-dirty (06/15/2026)` |
| DRAM | 64 MB (`dramfreq=528`) | 128 MB (`dramfreq=648`) |
| LCD panel | `R0H 854x480` | `RX 854x480` |
| Camera sensor / IQ | `Nx 2025-02-27` | `Nx 2025-07-04` |
| Hardware string | `SW;V533;DC01;DC01;00;cdr;01;01` | (empty) |
| Resolution (device.xml) | 854x480 | 854x480 |
| `adbEnable` | 1 | 1 |
| Kernel | 4.9.191 | 4.9.191 |
| Tina / OpenWrt | 4.0.0 Neptune (`5C1C9C53`) | 4.0.0 Neptune (`5C1C9C53`) |
| WiFi | rtl8733bs / rtl8821cs | rtl8733bs / rtl8821cs |
| `bootreason` | (not present) | `usb` |

Both share the software family, kernel, resolution and WiFi drivers. **But they are not the same hardware.**

---

## MTD partitions

| Partition | TF811 | M750 | Name |
|---|---|---|---|
| mtd0 | 393,216 B | 393,216 B | uboot |
| mtd1 | 2,228,224 B | 2,293,760 B | boot |
| mtd2 | 13,369,344 B | 13,303,808 B | rootfs |
| mtd3 | 327,680 B | 327,680 B | rootfs_data |
| mtd4 | 131,072 B | 131,072 B | env |
| mtd5 | 131,072 B | 131,072 B | bootlogo |
| mtd6 | 65,536 B | 65,536 B | private |
| mtd7 | 131,072 B | 131,072 B | UDISK |

Total: 16 MB in both. M750's `boot` is 64 KB larger and `rootfs` 64 KB smaller.

---

## Device identity files

Three device-specific files appeared on the M750 SD, also duplicated in the overlay (`overlay/upper/etc/` and `overlay/upper/mnt/extsd/`):

```text
id.txt      60811d4b00c4057000004c4000000000
config.txt  spanish:0,0:0,0,0,0:0,0,0,0:0,0,0,0:0,0:20260101_120101:1:0:1:0:0:0:1:1:35:20:0:95:0:0:1:0:1
tyre.txt    19:21:67:70:E1A0002B7713:E1A0007BD68C
```

- `id.txt`: unique 32-character hexadecimal ID.
- `config.txt`: customer configuration (Spanish in this case) with date `20260101_120101`.
- `tyre.txt`: two long codes (`E1A0002B7713`, `E1A0007BD68C`), likely sensor/TPMS identifiers.

These files are how the firmware stores customer configuration on the SD. **They are useful to tell screens apart** if you have several using the same `debug1`.

---

## Overlay contents (M750)

```text
data/param.bin
etc/zlink.txt
etc/rtl8733bs.txt
etc/blink/sc_db.db
etc/blink/.btlicense
etc/blink/bt_conf.ini
etc/config.txt
etc/tyre.txt
etc/firmware/p2pmac.sh
etc/firmware/ipscan.sh
etc/firmware/ap_ctrl.sh
etc/firmware/apmac.sh
etc/firmware/sta_ctrl.sh
etc/firmware/direct_ctrl.sh
etc/firmware/checkip.sh
etc/random-seed
mnt/extsd/hitlittlev1.0.exe
mnt/extsd/config.txt
mnt/extsd/tyre.txt
usr/lib/eyesee-mpp/libcrypto.so
usr/lib/eyesee-mpp/libssl.so
usr/bin/chroot_ota.sh
usr/bin/lt_image.sh
usr/bin/memtool
```

The scripts in `etc/firmware/` manage the WiFi modes (AP, station, direct, MAC, etc.). They are a good starting point if you want to understand how the device network is configured.

---

## Which is "better"

**The M750 (screen 2) is superior in specifications:**

| Criterion | Winner |
|---|---|
| `v853` chip (newer, with NPU) vs `v837s` | M750 |
| 128 MB RAM vs 64 MB | M750 |
| DRAM 648 MHz vs 528 MHz | M750 |
| U-Boot Jun 2026 vs Jan 2026 | M750 |
| Build Aug 2026 vs Mar 2026 | M750 |
| Camera calibration 2025-07 vs 2025-02 | M750 |
| Kernel, Tina, resolution, WiFi | Tie |
| Visual quality of `R0H` vs `RX` panel | Cannot be determined without seeing them |

---

## Critical warning: not interchangeable

Although they share kernel 4.9.191 and 854x480 resolution, **do not flash one screen's firmware onto the other**:

- Different SoC (`v837s` vs `v853`) -> different DTB and `sys_config.fex`
- Different RAM size (64 vs 128 MB) -> different memory configuration
- Different panel (`R0H` vs `RX`) -> different initialization and display calibration
- Different camera calibration (`Nx 2025-02-27` vs `Nx 2025-07-04`)

The **dump method is common** to both; the resulting images **are not**.

---

## Recommended dump organization

```text
firmware_dumps/
├── TF811/
│   ├── podofo_full.bin
│   ├── info.txt
│   ├── mtdblock0.bin ... mtdblock7.bin
│   ├── etc/
│   ├── overlay/
│   └── data/
└── M750/
    ├── info.txt
    ├── mtdblock0.bin ... mtdblock7.bin
    ├── etc/
    ├── overlay/
    └── data/
```

Always keep `info.txt` next to the `mtdblock*.bin` files: it is the only way to know which specific device a dump came from if they get mixed up.
