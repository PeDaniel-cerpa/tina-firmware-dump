# Allwinner / Tina Linux Firmware Dump — root shell over IP without disassembly

[Español](README.es.md)

**Extract the complete firmware from an Allwinner CarPlay screen / Android head unit running Tina Linux (OpenWrt) — no teardown, no reflashing, no serial cable.**

A practical, hardware-tested guide that uses an existing boot hook in `/etc/init.d/S01app` to run a script from a microSD as root. The script dumps all MTD partitions, copies `/etc`, `/overlay` and `/data`, and starts a root telnet shell reachable over WiFi/Ethernet.

> **Verified on real hardware:** TF811 (v837s, 64 MB RAM) and M750 (v853, 128 MB RAM). Both produced a full 16 MB / 8-partition firmware dump plus configuration data.

---

## Keywords

`allwinner` `tina linux` `openwrt` `firmware dump` `firmware extraction` `firmware backup` `carplay screen` `carplay display` `android head unit` `car stereo` `root shell` `telnetd` `busybox` `mtd` `nand flash` `mtdblock` `embedded linux` `reverse engineering` `armv7` `armhf` `musl` `fat32` `superfloppy` `sd card` `adb alternative` `no teardown` `v853` `v837s` `sun8iw21p1` `TF811` `M750` `uboot` `squashfs` `overlayfs` `shell over IP` `Tera Term`

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
| [`files/busybox_net`](files/busybox_net) | 1.1 MB | Static ARMv7 BusyBox 1.31 with `telnetd` applet |
| [`files/debug1-v1-socat.sh`](files/debug1-v1-socat.sh) | 2 KB | Original version (socat attempt, **does not work**: see doc 04) |
| [`files/socat`](files/socat) | 205 KB | Binary that failed due to musl time64 ABI (kept as reference) |
| [`files/README.txt`](files/README.txt) | 2.6 KB | Original instructions copied to the SD |
| [`scripts/make_sd_image.sh`](scripts/make_sd_image.sh) | - | Creates the FAT32 superfloppy image |
| [`scripts/write_sd_windows.ps1`](scripts/write_sd_windows.ps1) | - | Writes the image to disk (Windows, self-elevating) |
| [`scripts/make_bootlogo.sh`](scripts/make_bootlogo.sh) | - | Converts your image into a valid 854x480 bootlogo |

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

The two models analyzed (**TF811** with `v837s`/64 MB and **M750** with `v853`/128 MB) **are not interchangeable**: different SoC, RAM, panel and camera calibration. Do not flash one device's firmware onto the other. See [docs/05-screen-analysis.md](docs/05-screen-analysis.md).

---

## License

MIT. Third-party binaries (BusyBox, socat) keep their own licenses; they are included solely as diagnostic tools.
