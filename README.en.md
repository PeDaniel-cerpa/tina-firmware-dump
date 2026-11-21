# Dumping firmware from Allwinner / Tina Linux screens without disassembly

[Español](README.md) · [Full procedure](docs/02-procedure.en.md) · [Troubleshooting](docs/04-troubleshooting.en.md)

A practical, hardware-tested guide to **get an root shell over IP and copy the entire firmware** from an Allwinner-based CarPlay screen running Tina Linux (OpenWrt), **without opening the device and without reflashing**.

Everything relies on a single hook already present in the firmware: `/etc/init.d/S01app` runs `/mnt/extsd/debug1` as root if that file exists on the microSD.

> **Status:** method verified on two real screens (**TF811** and **M750** models). Both produced a complete dump of 8 MTD partitions (16 MB) plus `/etc`, `/overlay` and `/data`.

---

## Contents

| Document | Description |
|---|---|
| [01 - Research](docs/01-investigation.en.md) | What was found in the firmware and WHY this works |
| [02 - Procedure](docs/02-procedure.en.md) | Step by step, from zero to dump on the PC |
| [03 - Files](docs/03-files.en.md) | The files used, what they do and where they came from |
| [04 - Troubleshooting](docs/04-troubleshooting.en.md) | Every failure encountered and how it was fixed |
| [05 - Screen comparison](docs/05-screen-analysis.en.md) | TF811 vs M750: differences and warnings |

---

## Quick start

### 1. Prepare the microSD

The card **cannot be MBR with a partition**. It must be **FAT32 "superfloppy"** (filesystem directly on the disk, no partition table). This is mandatory because the firmware mounts `/dev/mmcblk0` (whole disk), not `/dev/mmcblk0p1`.

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
| [`files/busybox_net`](files/busybox_net) | 1.1 MB | Static ARMv7 BusyBox 1.31 with `telnetd` applet |
| [`files/debug1-v1-socat.sh`](files/debug1-v1-socat.sh) | 2 KB | Original version (socat attempt, **does not work**: see doc 04) |
| [`files/socat`](files/socat) | 205 KB | Binary that failed due to musl time64 ABI (kept as reference) |
| [`files/README.txt`](files/README.txt) | 2.6 KB | Original instructions copied to the SD |
| [`scripts/make_sd_image.sh`](scripts/make_sd_image.sh) | - | Creates the FAT32 superfloppy image |
| [`scripts/write_sd_windows.ps1`](scripts/write_sd_windows.ps1) | - | Writes the image to disk (Windows, self-elevating) |

SHA256 checksums and upstream URLs: [docs/03-files.en.md](docs/03-files.en.md).

Real logs from a successful run are also included in [`examples/`](examples/), useful for comparison if something goes wrong:

```text
examples/debug1-M750.log    <- script execution log
examples/info-M750.txt      <- CMDLINE, /proc/mtd, ifconfig, route, mounts
```

> Before publishing, review `examples/info-M750.txt`: it contains device data (MAC, cmdline). If you do not want to publish it, replace the file with an anonymized version.

---

## Why the obvious methods do not work

| Method | Result |
|---|---|
| `sshd` / `dropbear` | Not present in the rootfs |
| Firmware's `telnetd` | Included busybox was built without it |
| Firmware's `tftp` / `nc` | Not available |
| ADB | No `adbd` binary; `S50adb` exits immediately |
| WSL -> `nc 192.168.10.1` | WSL2 uses NAT, cannot reach that subnet (use Tera Term on Windows) |
| OpenWrt 23.05 `socat` | Fails: `__nanosleep_time64: symbol not found` (musl time64) |
| Normal MBR/FAT32 SD | Hook never fires: firmware mounts `/dev/mmcblk0`, not the partition |

Full detail in [docs/04-troubleshooting.en.md](docs/04-troubleshooting.en.md).

---

## Important warning

This method is **read-only and diagnostic**. It does not modify the device's flash.

The two models analyzed (**TF811** with `v837s`/64 MB chip and **M750** with `v853`/128 MB chip) **are not interchangeable**: different SoC, RAM, panel and camera calibration. Do not flash one device's firmware onto the other. See [docs/05-screen-analysis.en.md](docs/05-screen-analysis.en.md).

---

## License

MIT. Third-party binaries (BusyBox, socat) keep their own licenses; they are included solely as diagnostic tools.
