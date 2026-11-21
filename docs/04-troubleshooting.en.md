# 04 - Troubleshooting

[Español](04-solucion-problemas.md) · [Back](../README.en.md)

Every problem encountered while developing the method, with the diagnosis and the fix actually applied. If something fails, look here first.

---

## 1. No `debug1.log` and no `firmware_dump` is created

**Symptom:** after booting with the SD, the card still only contains `debug1` and `busybox_net`. No log.

**Cause:** the SD is MBR with a FAT32 partition. The firmware does:

```sh
mount -t vfat /dev/mmcblk0 /mnt/extsd 2>/dev/null   # whole disk -> FAILS
# && mount -t vfat /dev/mmcblk0p1 /mnt/extsd        # commented out
if [ -f /mnt/extsd/debug1 ]; then ... fi             # never matches
```

**Fix:** convert the SD to FAT32 superfloppy (no partition table). See [Phase 2](02-procedure.en.md#phase-2---create-the-superfloppy-sd-fat32-without-partition-table).

**How to confirm:** there is no log at all. If a log exists but there is no shell, jump to problem 4.

---

## 2. `Operation not permitted` when copying `/etc`

**Symptom** in `debug1.log`:

```text
cp: can't create symlink '/mnt/extsd/firmware_dump/etc/./mtab': Operation not permitted
cp: can't create symlink '/mnt/extsd/firmware_dump/etc/./rc.d/K80udev': Operation not permitted
```

**Cause:** FAT32 does not support symlinks and `cp -Rp` tries to recreate them.

**Fix:** use `cp -RpL` (the `L` dereferences links and copies the target content):

```sh
cp -RpL /etc/. /mnt/extsd/firmware_dump/etc/
```

---

## 3. `socat`: `__nanosleep_time64: symbol not found`

**Symptom** in `debug1.log`:

```text
Error relocating /mnt/extsd/socat: __nanosleep_time64: symbol not found
Error relocating /mnt/extsd/socat: __gettimeofday_time64: symbol not found
Error relocating /mnt/extsd/socat: __localtime64: symbol not found
Error relocating /mnt/extsd/socat: __lstat_time64: symbol not found
```

**Cause:** OpenWrt 23.05's `socat` was built against a musl using the time64 ABI (64-bit time structures). The firmware's musl (`/lib/ld-musl-armhf.so.1`) is older and only has the time32 ABI.

**Fix:** do not use `socat`. Use static BusyBox with `telnetd` ([`files/busybox_net`](../files/busybox_net)).

**Discarded alternatives:**

| Attempt | Reason |
|---|---|
| OpenWrt 21.02 `socat` `arm_cortex-a7` | No time64 but soft-float, interpreter `/lib/ld-musl-arm.so.1` |
| Alpine 3.12 `socat` `armv7` | Correct interpreter but needs `libssl`/`libcrypto`/`libreadline`, absent |

---

## 4. Port does not respond although the log says "ACTIVE"

**Symptom:** `debug1.log` ends with `telnetd ACTIVO en puerto 23`, but Tera Term cannot connect.

**Possible causes, in order:**

1. **The PC is not on the right network.** If the PC's WiFi is connected to another network (e.g. your home WiFi), ping to `192.168.10.1` fails. Check:

   ```powershell
   Get-NetIPAddress -InterfaceIndex 16 -AddressFamily IPv4
   Get-NetConnectionProfile -InterfaceIndex 16 | Select Name
   ```

2. **The device IP is not `192.168.10.1`.** Check `firmware_dump/info.txt`, section `ifconfig`. The firmware DHCP range is `192.168.10.250-254`, so the screen is usually `.1`, but not guaranteed.

3. **You are testing from WSL.** WSL2 uses NAT and cannot reach `192.168.10.x`. Use Tera Term or Windows `nc`.

4. **The daemon died when the script exited.** Confirm from the shell itself (if you can get in) or via the log.

---

## 5. Ping works for a while and then stops

**Cause:** you switched WiFi to get internet and talk to the assistant. Normal: with the static IP `192.168.10.250` there is no internet.

**Fix:** alternate between the screen's network (to test) and your normal WiFi (to chat). When returning, restore the static IP:

```powershell
netsh interface ip set address name="Wi-Fi" static 192.168.10.250 255.255.255.0 192.168.10.1
```

---

## 6. Windows: `Access denied` writing raw disk

**Symptom:** opening `\\.\PhysicalDrive1` with `FileAccess.Write`:

```text
Exception calling "Open" with argument count: "4":
"Access to the path '\\.\PhysicalDrive1' is denied."
```

**Diagnosis:** the process must be elevated. Verify inside the script:

```powershell
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
$pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

**Fix:** elevate with `Start-Process ... -Verb RunAs` and also dismount the volume with `FSCTL_DISMOUNT_VOLUME` before writing. [`scripts/write_sd_windows.ps1`](../scripts/write_sd_windows.ps1) already does both.

---

## 7. `diskpart: The operation is not supported on removable media`

**Symptom:**

```text
Virtual Disk Service error:
The operation is not supported on removable media.
```

**Cause:** `diskpart` cannot `offline disk` / `clean` USB removable disks.

**Fix:** do not use `diskpart`. Use raw writing with `FSCTL_DISMOUNT_VOLUME`, or use Rufus in DD mode.

---

## 8. `wsl --mount` does not work with the SD

**Symptom:**

```text
Error: 0x80040315
Wsl/Service/AttachDisk/MountDisk/WSL_E_ELEVATION_NEEDED_TO_MOUNT_DISK
```

and elevated:

```text
The system cannot find the device specified.
Error: 0x8007000f
```

**Cause:** WSL2 `wsl --mount` does not support USB removable disks.

**Fix:** write the image from Windows (provided script) or from Linux with `dd`.

---

## 9. `debug1` does not run due to CRLF

**Symptom:** no log appears, or `^M: not found`.

**Fix:**

```bash
sed -i 's/\r$//' debug1
sh -n debug1
```

Verification on Windows:

```powershell
$b=[IO.File]::ReadAllBytes("F:\debug1")
([regex]::Matches([Text.Encoding]::ASCII.GetString($b),"`r`n")).Count   # must be 0
```

---

## 10. `nc` from WSL gives `Connection timed out`

**Cause:** WSL2 uses NAT and has no route to `192.168.10.0/24`. Ping from WSL also fails (100% packet loss) while it works from Windows.

**Fix:** use Tera Term (TCP/IP) or native Windows `nc`. Do not waste time debugging the port from WSL.

---

## 11. Shell connects but seems to "do nothing"

After connecting with Tera Term you must press **Enter** once or twice. The prompt may be:

```text
/ #
```

or:

```text
root@TinaLinux:~#
```

If `login:` appears, type `root` and Enter. If the screen is blank, press Enter.

Test commands:

```sh
whoami
cat /proc/mtd
```

---

## 12. Date 1970 in the logs

**Symptom:** `Thu Jan 1 00:00:02 UTC 1970`.

**Cause:** the device has no battery-backed RTC; at boot it uses the epoch. This is **normal** and does not affect the dump.

---

## Quick decision tree

```text
Is there a debug1.log on the SD?
├── NO  -> problem 1 (superfloppy SD) or 9 (CRLF)
└── YES
    ├── "symbol not found" error? -> problem 3 (use busybox_net)
    ├── "cp: can't create symlink"? -> problem 2 (cp -RpL)
    ├── Says "telnetd ACTIVE" but no connection? -> problem 4 / 5 / 10
    └── All OK? -> you already have the firmware in firmware_dump/
```
