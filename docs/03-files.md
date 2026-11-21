# 03 - Files used

[Español](03-files.es.md) · [Back](../README.md)

**Keywords:** debug1 script, busybox_net, telnetd static ARM, socat, SHA256 checksums, OpenWrt, Alpine, musl time64, firmware tools

Complete inventory of every file used in the procedure, its purpose, origin and checksum.

---

## 1. `debug1` - the main script

**Path on SD:** `/mnt/extsd/debug1` (root, no extension)
**Size:** 2068 bytes
**SHA256:** `cff1f9167a5ad338e48e7dc0228306b996fb0b9e5148d37293f78be039036882`
**Source:** [`files/debug1`](../files/debug1)

What it does, in order:

1. Writes `/mnt/extsd/debug1.log` (overwritten on every boot).
2. Generates `firmware_dump/info.txt` with:
   - `date`, `/proc/cmdline`, `/proc/mtd`, `/proc/partitions`
   - `/proc/mounts`, `ifconfig` output and `route -n`
   - **The device's real IP is here**, useful if DHCP did not assign `192.168.10.1`.
3. Dumps every `/dev/mtdblock*` with `dd if=... of=firmware_dump/<name>.bin bs=64k`.
4. Copies `/etc`, `/overlay` and `/data` with `cp -RpL` (dereferences symlinks; plain `cp -Rp` failed with `Operation not permitted` on FAT32).
5. If `/mnt/extsd/busybox_net` exists, starts in background:

```sh
/mnt/extsd/busybox_net telnetd -p 23 -l /bin/sh >> "$LOG" 2>&1 &
```

6. Writes `=== FIN ... ===` and exits with `exit 0`.

### Why `exit 0` and `&` matter

`S01app` calls the script synchronously. If `telnetd` ran in the foreground, boot would hang waiting for the server to finish (it never finishes) and WiFi/app would never start. The `&` leaves it in the background and `exit 0` tells init everything went fine.

### Format requirements

- Exact name: `debug1` (no `.sh`, no uppercase).
- **LF** line endings (UNIX). With CRLF, the firmware's `/bin/sh` may fail with `^M: not found`.
- Executable bit: `chmod +x debug1` (on FAT32 everything is executable anyway).

---

## 2. `busybox_net` - the telnet server

**Path on SD:** `/mnt/extsd/busybox_net`
**Size:** 1,152,216 bytes (1.1 MB)
**SHA256:** `cd04052b8b6885f75f50b2a280bfcbf849d8710c8e61d369c533acf307eda064`
**Type:** `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), statically linked, stripped`
**Origin:** [BusyBox 1.31.0, `defconfig-multiarch-musl` build, `busybox-armv7l`](https://busybox.net/downloads/binaries/1.31.0-defconfig-multiarch-musl/busybox-armv7l)

Renamed to `busybox_net` so the script can check for its existence under its own name.

Applets verified inside the binary:

```text
telnetd     <- the one we use
telnet
httpd
tftp
```

(no standalone `sh`/`ash`, but not needed: we use `-l /bin/sh` from the firmware itself).

### Why static

The firmware uses an old musl. Any dynamically linked binary built against newer musl fails with `__*_time64: symbol not found`. Being static, it **loads no system libraries** and the problem disappears.

Exact command executed:

```sh
/mnt/extsd/busybox_net telnetd -p 23 -l /bin/sh
```

`-l /bin/sh` replaces login: it drops straight into root, with no `/etc/passwd` or password.

---

## 3. `socat` - the failed attempt (kept as reference)

**Size:** 209,380 bytes
**SHA256:** `8baea5a082d47fce4c7639d51f8cda291219ea7651d9fc43780ff890ba2960be`
**Origin:** [OpenWrt 23.05.2, `socat_1.7.4.4-1_arm_cortex-a7_vfpv4.ipk`](https://downloads.openwrt.org/releases/23.05.2/packages/arm_cortex-a7_vfpv4/packages/socat_1.7.4.4-1_arm_cortex-a7_vfpv4.ipk)
**Interpreter:** `/lib/ld-musl-armhf.so.1` (matches the firmware)

It looked compatible (same interpreter, hard-float), but **it does not work**. When executed:

```text
Error relocating /mnt/extsd/socat: __nanosleep_time64: symbol not found
Error relocating /mnt/extsd/socat: __gettimeofday_time64: symbol not found
Error relocating /mnt/extsd/socat: __localtime64: symbol not found
Error relocating /mnt/extsd/socat: __lstat_time64: symbol not found
```

Also tried:

| Version | Result |
|---|---|
| OpenWrt 21.02.7 `arm_cortex-a7` (`socat_1.7.3.4-2`) | No time64, but soft-float and interpreter `/lib/ld-musl-arm.so.1` |
| Alpine 3.12 `armv7` (`socat-1.7.3.4-r0.apk`) | Correct interpreter, but depends on `libssl.so.1.1`, `libcrypto.so.1.1`, `libreadline.so.8` |

Therefore discarded. [`files/debug1-v1-socat.sh`](../files/debug1-v1-socat.sh) is the original version that used it (port 4444), included only as historical documentation.

---

## 4. `README.txt`

**Size:** 2614 bytes
**SHA256:** `fac892d40496a4811f0c000110957de1fcb11adc3b6a46a51bb72331ba256cd9`
**Source:** [`files/README.txt`](../files/README.txt)

Original Spanish instructions copied to the SD along with `debug1` v1. Kept because it documents how the method was originally conceived (although it mentions `socat` and port 4444, which are no longer used).

---

## 5. Support scripts

### `scripts/make_sd_image.sh`

Creates a 1 GB FAT32 superfloppy `.img` and copies `debug1` + `busybox_net` to the root. Uses `mkfs.fat -F 32 -s 4` and `mcopy -i`.

```bash
./scripts/make_sd_image.sh firmware_dump.img
```

### `scripts/verify_sd.sh`

Lists the image contents and checks that both files are present with the correct size.

```bash
./scripts/verify_sd.sh firmware_dump.img
```

### `scripts/write_sd_windows.ps1`

Writes the image in raw mode to a Windows disk. Self-elevates to Administrator. Uses `FSCTL_DISMOUNT_VOLUME` to release the volume before writing (without it, Windows returns `Access denied`).

```powershell
.\scripts\write_sd_windows.ps1 -ImagePath .\firmware_dump.img -DiskNumber 1 -DriveLetter F
```

Parameters:

| Parameter | Meaning |
|---|---|
| `-ImagePath` | Path to the `.img` |
| `-DiskNumber` | Disk number (Get-Disk) |
| `-DriveLetter` | Drive letter assigned to the SD |

> **Warning:** the chosen disk is completely erased. Verify the number twice.

---

## Checksum table

| File | SHA256 |
|---|---|
| `debug1` (v2, working) | `cff1f9167a5ad338e48e7dc0228306b996fb0b9e5148d37293f78be039036882` |
| `debug1` v1 (socat, failed) | `6c51277da3a5ceb33f9dbd1e7486bd44682fd2726f3f80dd8d000041254a2c28` |
| `busybox_net` | `cd04052b8b6885f75f50b2a280bfcbf849d8710c8e61d369c533acf307eda064` |
| `socat` | `8baea5a082d47fce4c7639d51f8cda291219ea7651d9fc43780ff890ba2960be` |
| `README.txt` | `fac892d40496a4811f0c000110957de1fcb11adc3b6a46a51bb72331ba256cd9` |
