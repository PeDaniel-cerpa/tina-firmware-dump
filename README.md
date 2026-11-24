# Allwinner / Tina Linux Firmware Dump — root shell over IP without disassembly

[Español](README.es.md)

**Extract the complete firmware from an Allwinner CarPlay screen / Android head unit running Tina Linux (OpenWrt) — no teardown, no reflashing, no serial cable.**

A practical, hardware-tested guide that uses an existing boot hook in `/etc/init.d/S01app` to run a script from a microSD as root. The script dumps all MTD partitions, copies `/etc`, `/overlay` and `/data`, and starts a root telnet shell reachable over WiFi/Ethernet.

> **Verified on real hardware:** TF811 (v837s, 64 MB RAM) and M750 (128 MB RAM). Both produced a full 16 MB / 8-partition firmware dump plus configuration data.
>
> **Correction 2026-11-24:** the M750 physically contains a **V553** (`sun50i`/Cortex-A53 family); the `v853-perf1` string in the firmware is only the build target. The final recovery was done over UART with the board's own dump and ended in the home screen: [doc 18](docs/18-m750-uart-recovery.md).
>
> **Origin of the research:** the firmware analysed here was first obtained from an opened Podofo A4628 over UART/U-Boot before the no-teardown method was developed. That critical baseline is documented in [doc 11](docs/11-podofo-a4628-uart-dump.md).

---

## Keywords

`allwinner` `tina linux` `openwrt` `firmware dump` `firmware extraction` `firmware backup` `carplay screen` `carplay display` `android head unit` `car stereo` `root shell` `telnetd` `busybox` `mtd` `nand flash` `mtdblock` `embedded linux` `reverse engineering` `armv7` `armhf` `musl` `fat32` `superfloppy` `sd card` `adb alternative` `no teardown` `v853` `v837s` `v553` `v533` `sun8iw21p1` `sun50i` `TF811` `M750` `uboot` `squashfs` `overlayfs` `shell over IP` `Tera Term` `Podofo A4628` `UART` `ESP32-S3` `SPI NOR` `U-Boot console` `PhoenixCard` `sf probe` `fatload` `NOR recovery`

---

## What this repository solves

| Problem | Solution in this repo |
|---|---|
| No `sshd`, `dropbear` or `telnetd` in the firmware | Static BusyBox `telnetd` supplied from the SD |
| ADB disabled (`adbd` missing, `S50adb` exits) | Boot-time root hook instead of USB |
| Firmware mounts `/dev/mmcblk0`, not `mmcblk0p1` | FAT32 **superfloppy** SD (no MBR) |
| `socat` fails with `__*_time64: symbol not found` | Static ARM BusyBox, zero library dependencies |
| Windows denies raw disk writes | `FSCTL_DISMOUNT_VOLUME` before writing |
| WSL2 cannot reach `192.168.10.x` | Tera Term / native Windows `nc` |
| V853 PhoenixCard image burned into the M750 (physical V553) | Burns in Startup but never boots: wrong-SoC boot0; see doc 18 |

---

## Contents

| Document | Description |
|---|---|
| [01 - Research](docs/01-investigation.md) | What was found in the firmware and WHY this works |
| [02 - Full procedure](docs/02-procedure.md) | Step by step, from zero to dump on the PC |
| [03 - Files](docs/03-files.md) | The files used, what they do and where they came from |
| [04 - Troubleshooting](docs/04-troubleshooting.md) | Every failure encountered and how it was fixed |
| [05 - Screen comparison](docs/05-screen-analysis.md) | TF811 vs M750: differences and warnings |
| [06 - Modifying images](docs/06-modify-images.md) | Change the boot logo, backgrounds and icons |
| [07 - Disabled features](docs/07-disabled-features.md) | Disabled services, missing binaries, XML flags and DTB nodes |
| [08 - Change UI colours](docs/08-change-ui-colors.md) | Turn the green menu red, including `image.bin.lzma` and the GPS sequence |
| [09 - Permanent custom images](docs/09-permanent-custom-images.md) | Bake custom images into `mtdblock2` so no SD is needed |
| [10 - Overlay whiteouts after flash](docs/10-overlay-whiteouts-after-flash.md) | Fix missing images caused by overlayfs whiteouts after flashing |
| [11 - Podofo A4628 UART dump](docs/11-podofo-a4628-uart-dump.md) | Critical baseline: U-Boot + Linux console dump of the opened unit (16 MiB SPI NOR) |
| [12 - Offline DTB and flags audit](docs/12-offline-dtb-and-flags-audit.md) | All 48 disabled DTB nodes, UI switches and `config_devmng.xml` flags, analysed from the extracted firmware |
| [13 - Hidden UI options](docs/13-hidden-ui-options.md) | 30 commented settings items, hidden in-page controls, app flags and factory/debug overlay |
| [14 - Expected GPS module](docs/14-expected-gps-module.md) | NMEA 0183 UART GPS at 9600 baud on PE6/PE7; wiring and software blockers |
| [15 - Bluetooth GPS with ESP32](docs/15-bluetooth-gps-with-esp32.md) | Why SPP is not supported, and working ESP32 UART alternatives to ttyS0/ttyS1 |
| [16 - Maximum `hm_bg` size](docs/16-hm-bg-size-limits.md) | Loose JPEG vs packed BGRA entry, 1.27 MB free in mtdblock2, 320 KB overlay limit |
| [17 - Apply `Untitled-1.jpg` background](docs/17-apply-untitled-background.md) | Rebuild with the new 854x480 image, patched BGRA entry and ready SD folder |
| [18 - M750 recovery over UART](docs/18-m750-uart-recovery.md) | Real solved case: why PhoenixCard failed, how the NOR was flashed with `sf`, and how home came back |

---

## Quick start

### 1. Prepare the microSD

The card **cannot be MBR with a partition**. It must be **FAT32 superfloppy** (filesystem directly on the disk, no partition table). This is mandatory because the firmware mounts `/dev/mmcblk0` (whole disk), not `/dev/mmcblk0p1`.

```bash
# Linux (requires mkfs.fat and mtools)
./scripts/make_sd_image.sh firmware_dump.img
```

```powershell
# Windows (PowerShell as Administrator)
.\scripts\write_sd_windows.ps1 -ImagePath .\firmware_dump.img -DiskNumber 1 -DriveLetter F
```

Result:

```
F:\
├── debug1          <- script, executed as root at boot
└── busybox_net     <- static ARM BusyBox with telnetd
```

### 2. Boot the screen

1. Power off, insert the SD and power on.
2. Wait 30-40 seconds.
3. Connect the PC to the screen's WiFi (`TF811-xxxx` or `M750-xxxx`, password `12345678`).
4. Set a static IP on the PC: `192.168.10.250`, mask `255.255.255.0`, gateway `192.168.10.1`.

### 3. Connect and collect

```text
Tera Term -> New connection -> TCP/IP
Host: 192.168.10.1
Port: 23
```

No password is requested: it drops straight into a root prompt. If that IP is wrong, check `firmware_dump/info.txt` (section `ifconfig`).

After removing the SD:

```
F:\
├── debug1.log
└── firmware_dump\
    ├── info.txt
    ├── mtdblock0.bin ... mtdblock7.bin    <- THE COMPLETE FIRMWARE
    ├── etc\
    ├── overlay\
    └── data\
```

---

## Included files

| File | Size | Purpose |
|---|---|---|
| [`files/debug1`](files/debug1) | 2 KB | Main script: dumps MTD, copies config and starts telnetd |
| [`files/debug1-bootlogo.sh`](files/debug1-bootlogo.sh) | 4 KB | Same, plus flashes `bootlogo.bin` from the SD automatically |
| [`files/debug1-wifi-ssid.sh`](files/debug1-wifi-ssid.sh) | 4 KB | Changes the AP SSID from `param.bin` + XML from the SD |
| [`files/debug1-ui-red.sh`](files/debug1-ui-red.sh) | 3 KB | Applies the red UI theme from the SD |
| [`files/debug1-flash-rootfs.sh`](files/debug1-flash-rootfs.sh) | 3 KB | Flashes a rootfs with custom images and verifies MD5 |
| [`files/debug1-fix-overlay-whiteouts.sh`](files/debug1-fix-overlay-whiteouts.sh) | 2 KB | Removes overlayfs whiteouts that hide images after a flash |
| [`files/busybox_net`](files/busybox_net) | 1.1 MB | Static ARMv7 BusyBox 1.31 with `telnetd` applet |
| [`files/debug1-v1-socat.sh`](files/debug1-v1-socat.sh) | 2 KB | Original version (socat attempt, **does not work**: see doc 04) |
| [`files/socat`](files/socat) | 205 KB | Binary that failed due to musl time64 ABI (kept as reference) |
| [`files/README.txt`](files/README.txt) | 2.6 KB | Original instructions copied to the SD |
| [`files/esp32_uart_bridge.ino`](files/esp32_uart_bridge.ino) | 4 KB | Sanitized ESP32-S3 USB-UART bridge used for the Podofo dump (USB COM only) |
| [`files/debug1-audit-dtb.sh`](files/debug1-audit-dtb.sh) | 4 KB | Read-only audit of the DTB, flags, XML and services from the live screen |
| [`scripts/make_sd_image.sh`](scripts/make_sd_image.sh) | - | Creates the FAT32 superfloppy image |
| [`scripts/write_sd_windows.ps1`](scripts/write_sd_windows.ps1) | - | Writes the image to disk (Windows, self-elevating) |
| [`scripts/make_bootlogo.sh`](scripts/make_bootlogo.sh) | - | Converts your image into a valid 854x480 bootlogo |
| [`scripts/make_bootlogo_fill.sh`](scripts/make_bootlogo_fill.sh) | - | Crop-to-fill variant for wide images |
| [`scripts/recolor_ui.py`](scripts/recolor_ui.py) | - | Recolors the green UI resources (XML + images + `image.bin.lzma`) |

SHA256 checksums and upstream URLs: [docs/03-files.md](docs/03-files.md).

Real logs from a successful run are included in [`examples/`](examples/), useful for comparison if something goes wrong:

```text
examples/debug1-M750.log    <- script execution log
examples/info-M750.txt      <- CMDLINE, /proc/mtd, ifconfig, route, mounts
```

> Before publishing a fork, review `examples/info-M750.txt`: it contains device data (MAC, cmdline). Replace it with an anonymized version if needed.

---

## Warning

This method is **read-only and diagnostic**. It does not modify the device's flash.

The two models analyzed (**TF811** with target `v837s`/64 MB and **M750** with a **physical V553**/128 MB, even though the firmware says `v853`) **are not interchangeable**: different SoC, RAM, panel and camera calibration. Do not flash one device's firmware onto the other. See [docs/05-screen-analysis.md](docs/05-screen-analysis.md) and the real recovery in [doc 18](docs/18-m750-uart-recovery.md).

---

## License

MIT. Third-party binaries (BusyBox, socat) keep their own licenses; they are included solely as diagnostic tools.
