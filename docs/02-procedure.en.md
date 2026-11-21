# 02 - Full procedure

[Español](02-procedimiento.md) · [Back](../README.en.md)

Step by step, from zero to the firmware on your PC. Estimated time: 15-25 minutes.

---

## Requirements

- The screen, of course, and a microSD of at least 1 GB.
- A Windows PC (for Tera Term) or a PC with an SD reader.
- Windows: **PowerShell as Administrator** (to write the disk in raw mode).
- Linux: `mkfs.fat` (dosfstools) and `mtools` (`mcopy`).
- The files from [`files/`](../files/).

> The whole procedure is **non-destructive to the screen**: only the microSD is written.

---

## Phase 0 - Identify the SD disk

With the SD connected to the PC, in Windows:

```powershell
Get-Partition -DriveLetter F | Get-Disk |
  Select-Object Number,FriendlyName,PartitionStyle,
                @{N='SizeGB';E={[math]::Round($_.Size/1GB,2)}}
```

Real example:

```text
Number         : 1
FriendlyName   : MXT-USB Storage Device
PartitionStyle : MBR
SizeGB         : 3.75
```

Note the **disk number** (in the example, `1`). It will be used as `-DiskNumber`.

It is also useful to confirm it is FAT32:

```powershell
Get-Volume -DriveLetter F | Select DriveLetter,FileSystem,SizeRemaining
```

---

## Phase 1 - Prepare the files

Copy these two files to a working folder:

```text
debug1          (the script)
busybox_net     (static BusyBox with telnetd)
```

Both must be placed in the **root** of the SD, with these exact names:

```
F:\debug1
F:\busybox_net
```

If you edit `debug1` on Windows, save it with **LF** line endings (not CRLF):

```bash
sed -i 's/\r$//' debug1
sh -n debug1        # should report correct syntax
```

Quick check for CRLF:

```powershell
$b=[IO.File]::ReadAllBytes("F:\debug1")
"CRLF=$(([regex]::Matches([Text.Encoding]::ASCII.GetString($b),"`r`n")).Count)"
"LF=$(([regex]::Matches([Text.Encoding]::ASCII.GetString($b),"`n")).Count)"
```

It must report `CRLF=0`.

---

## Phase 2 - Create the superfloppy SD (FAT32 without partition table)

This is the CRITICAL part. A normal MBR SD does not work.

### Option A: Linux (recommended)

```bash
# Install tools if missing
sudo apt install -y dosfstools mtools

# Create a 1 GB image with FAT32 directly (no MBR)
./scripts/make_sd_image.sh firmware_dump.img

# Verify
./scripts/verify_sd.sh firmware_dump.img
```

Expected output:

```text
Volume in drive : is FIRMWARE
Directory for ::/
debug1        2068 ...
busybox_net 1152216 ...
        2 files          1 155 284 bytes
                  1 068 000 256 bytes free
```

Then write the image to the SD:

```bash
sudo dd if=firmware_dump.img of=/dev/sdX bs=4M status=progress conv=fsync
```

> **Careful:** `/dev/sdX` is the SD disk, not your system disk. Check it with `lsblk`.

### Option B: Windows (elevated PowerShell)

The script self-elevates (UAC prompt appears). **It will erase all content on the chosen disk.**

```powershell
.\scripts\write_sd_windows.ps1 `
    -ImagePath .\firmware_dump.img `
    -DiskNumber 1 `
    -DriveLetter F
```

If you do not want to create the image on Linux, you can also use **Rufus** in *DD Image* mode with the `.img`.

### Verification on Windows

```powershell
Get-Volume -DriveLetter F | Select DriveLetter,FileSystem,Size
Get-ChildItem F:\ | Select Name,Length
```

It should show `FileSystem = FAT32`, ~1 GB size, and only `debug1` + `busybox_net`.

> Note: Windows may still show "PartitionStyle: MBR" in Disk Manager because the image has no table; what matters is that `mount -t vfat /dev/mmcblk0` works on the screen.

---

## Phase 3 - Configure networking on Windows

### 3.1 Connect to the screen's WiFi

- SSID: `TF811-xxxx` (or `M750-xxxx`)
- Password: `12345678`

### 3.2 Set a static IP

GUI:

1. `Win + R` -> `ncpa.cpl`
2. Right-click **Wi-Fi** -> Properties
3. Double-click **Internet Protocol Version 4 (TCP/IPv4)**
4. Select **Use the following IP address**:

```text
IP address:            192.168.10.250
Subnet mask:           255.255.255.0
Default gateway:       192.168.10.1
DNS:                   (empty)
```

By command (PowerShell as Administrator):

```powershell
netsh interface ip set address name="Wi-Fi" static 192.168.10.250 255.255.255.0 192.168.10.1
```

To see the exact adapter name:

```powershell
Get-NetAdapter | Where Status -ne Disabled | Select Name,Status,ifIndex
```

### 3.3 Verify

```cmd
ping 192.168.10.1
```

If it does not respond, stop here: check the WiFi and IP. (The real IP may be different; it is in `info.txt` on the SD after boot.)

> Do not use WSL for `ping` or `nc`: WSL2 uses NAT and cannot reach the `192.168.10.x` network. Use Windows commands or Tera Term.

---

## Phase 4 - Boot and connect

1. **Power off the screen.**
2. Insert the prepared SD **before powering on**.
3. Power on and wait **30-40 seconds** (the script takes ~7 s to dump, but WiFi takes longer).
4. Open **Tera Term**:
   - `File -> New connection`
   - Select **TCP/IP**
   - **Host:** `192.168.10.1`
   - **Port:** `23`
   - `OK`
5. Press **Enter** a couple of times. You should see:

```text
/ #
```

or:

```text
root@TinaLinux:~#
```

6. Verify:

```sh
whoami        # -> root
cat /proc/mtd
```

There is no password: the script uses `telnetd -l /bin/sh`, which drops straight into root.

Alternative with native Windows `nc`:

```cmd
nc 192.168.10.1 23
```

---

## Phase 5 - Collect the dump

Power off, remove the SD and connect it to the PC. It should contain:

```
F:\
├── debug1.log
├── debug1
├── busybox_net
└── firmware_dump\
    ├── info.txt
    ├── mtdblock0.bin    384 KB   uboot
    ├── mtdblock1.bin    2.1 MB   boot
    ├── mtdblock2.bin   12.7 MB   rootfs
    ├── mtdblock3.bin    320 KB   rootfs_data
    ├── mtdblock4.bin    128 KB   env
    ├── mtdblock5.bin    128 KB   bootlogo
    ├── mtdblock6.bin     64 KB   private
    ├── mtdblock7.bin    128 KB   UDISK
    ├── etc\
    ├── overlay\
    └── data\
```

Copy `F:\firmware_dump\` to your working folder and store it.

`debug1.log` should end like this:

```text
[debug1] telnetd ACTIVO en puerto 23 -> Tera Term: 192.168.10.1:23
[debug1] === FIN Thu Jan  1 00:00:09 UTC 1970 ===
```

(The date is 1970 because the device has no battery-backed RTC; this is normal.)

---

## Phase 6 - Restore normality

Return the PC's WiFi to DHCP:

```powershell
netsh interface ip set address name="Wi-Fi" dhcp
```

If you want to leave the SD as it was, delete only `firmware_dump` and `debug1.log`. `debug1` and `busybox_net` can stay: they do nothing unless the device boots with that SD inserted.

---

## Useful commands inside the shell

```sh
cat /proc/mtd                                          # partitions
df -h                                                  # free space
cat /etc/banner                                        # system version
dd if=/dev/mtdblock5 of=/mnt/extsd/bootlogo.bin        # dump only the logo
cp -a /etc /mnt/extsd/etc2                             # copy configuration
ifconfig                                              # see the real IP
```

---

## Repeating the dump

No need to rebuild the SD. Delete `F:\firmware_dump` (and optionally `debug1.log`), reinsert the SD and boot. The script recreates everything.
