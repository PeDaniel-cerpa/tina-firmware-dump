# 01 - Firmware research

[Español](01-investigation.es.md) · [Back](../README.md)

**Keywords:** allwinner, tina linux, openwrt, firmware research, boot hook, S01app, mmcblk0, superfloppy, FAT32, musl time64, busybox telnetd, reverse engineering

This is the analysis phase that explains **why** the method works. You do not need to repeat it to use the procedure, but it helps when adapting it to other models.

---

## 1. Target identification

From the extracted firmware (`podofo_full.bin`, and later from the direct dump):

```text
OS:             Tina Linux (OpenWrt), Neptune release
Version:        4.0.0
Kernel:         Linux 4.9.191
Rootfs:         squashfs (read-only) + overlay
Architecture:   ARM EABI5, hard-float
Loader:         /lib/ld-musl-armhf.so.1  (musl libc)
Model 1:        TF811 -> build tina.zengfu.20260302,      target v837s-perf1,  64 MB RAM
Model 2:        M750  -> build tina.zhangxiangpu.20260815, target v853-perf1, 128 MB RAM
Resolution:     854x480
WiFi:           rtl8733bs / rtl8821cs
```

The kernel cmdline confirms the partition layout:

```text
root=/dev/mtdblock2 rootwait init=/pseudo_init rdinit=/rdinit
partitions=boot@mtdblock1:rootfs@mtdblock2:rootfs_data@mtdblock3:
            env@mtdblock4:bootlogo@mtdblock5:private@mtdblock6:UDISK@mtdblock7
androidboot.hardware=sun8iw21p1 boot_type=3 gpt=1
```

---

## 2. The hook: `/etc/init.d/S01app`

Inside the extracted rootfs, `etc/init.d/S01app` contains exactly:

```sh
if [ -z "$(grep '\<vfat\>' /proc/mounts)" ]; then
     /bin/mount -t vfat /dev/mmcblk0 /mnt/extsd 2>/dev/null
#    && /bin/mount -t vfat /dev/mmcblk0p1 /mnt/extsd
if [ -f "/mnt/extsd/debug1" ];then
        echo "sdcard had been mount and find th debug1"
        /mnt/extsd/debug1
fi
fi
```

Three critical conclusions:

1. **It runs as root**: every script in `/etc/init.d/` runs with UID 0. No privilege escalation needed.
2. **Exact name required**: `/mnt/extsd/debug1`, no extension. `debug1.sh` or `DEBUG1` will not work.
3. **It is synchronous**: `S01app` waits for `debug1` to finish before starting WiFi and the app. Any network service must be launched in the background (`&`).

And a hidden problem:

```sh
/bin/mount -t vfat /dev/mmcblk0 /mnt/extsd 2>/dev/null    # <- mounts the WHOLE DISK
# && /bin/mount -t vfat /dev/mmcblk0p1 /mnt/extsd         # <- THIS LINE IS COMMENTED OUT
```

The firmware tries to mount `/dev/mmcblk0`, **not partition 1**.

---

## 3. The SD card problem (and its solution)

With a normal **MBR disk with one FAT32 partition**:

```text
/dev/mmcblk0     <- whole disk (MBR table, not FAT)
/dev/mmcblk0p1   <- FAT32 partition (where the files are)
```

`mount -t vfat /dev/mmcblk0` **fails**. Since the `mmcblk0p1` fallback is commented out, `/mnt/extsd` stays empty and `if [ -f /mnt/extsd/debug1 ]` never matches. Result: no log, no dump.

With a **FAT32 superfloppy** card:

```text
/dev/mmcblk0     <- FAT32 directly (no MBR, no partitions)
```

`mount -t vfat /dev/mmcblk0` **succeeds**, the hook fires and `debug1` runs as root.

> This was the key change that took the method from "nothing happens" to "complete dump".

Note: `rc.final` and `etc/udev/hotplug-tf.sh` do mount `mmcblk0p1`, but they run **after** `S01app` already passed the check. They cannot be used as an alternative.

---

## 4. What tools exist (and which do not)

The rootfs and the included busybox were checked:

| Tool | Available in firmware | Use |
|---|---|---|
| `/bin/sh`, `dd`, `cp`, `mount`, `ifconfig`, `route`, `pidof` | Yes | Dump and diagnostics |
| `sshd`, `dropbear` | **No** | - |
| `telnetd` (firmware busybox) | **No** (not compiled in) | - |
| `tftp`, `nc`, `netcat` | **No** | - |
| `httpd` | **No** | - |
| `adbd` | **No** (`S50adb` exits; `S50usb` tries it and fails) | - |

Therefore the remote shell has to **come from the SD card**, not from what the device ships with.

---

## 5. Choosing the network server

### Failed attempts

| Binary tried | Reason for failure |
|---|---|
| `socat` 1.7.4.4 from OpenWrt 23.05 (`arm_cortex-a7_vfpv4`) | Requires `__nanosleep_time64`, `__gettimeofday_time64`, `__localtime64`, `__lstat_time64`. The firmware's musl is older (time32 ABI). |
| `socat` 1.7.3.4 from OpenWrt 21.02 (`arm_cortex-a7`) | No time64 symbols, but soft-float and interpreter `/lib/ld-musl-arm.so.1` (different from the device's `/lib/ld-musl-armhf.so.1`). |
| `socat` 1.7.3.4 from Alpine 3.12 (`armv7`, armhf) | Correct interpreter and no time64 symbols, but depends on `libssl.so.1.1`, `libcrypto.so.1.1` and `libreadline.so.8`, absent from the rootfs. |

### Chosen solution

**Static BusyBox 1.31.0 for ARMv7** (`busybox.net`, `defconfig-multiarch-musl` build):

```text
ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), statically linked, stripped
```

- Needs **no** system libraries at all (solves the musl problem).
- Includes the `telnetd` applet.
- Invoked as `/mnt/extsd/busybox_net telnetd -p 23 -l /bin/sh`.
- The `-l /bin/sh` drops straight into root, with no `/etc/passwd` or password.

---

## 6. Final strategy summary

```text
FAT32 superfloppy SD
   |
   |  S01app: mount -t vfat /dev/mmcblk0 /mnt/extsd
   v
/mnt/extsd/debug1  (root, synchronous)
   |
   +--> info.txt          (CMDLINE, /proc/mtd, ifconfig, route, mounts)
   +--> mtdblock0..7.bin  (dd bs=64k of each /dev/mtdblock*)
   +--> etc/, overlay/, data/  (cp -RpL, avoiding symlink issues)
   |
   +--> busybox_net telnetd -p 23 -l /bin/sh  &   (background, does not block)
```

The result is a **complete and readable dump** without touching the flash or disassembling the device.
