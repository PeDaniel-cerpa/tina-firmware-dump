# 19 - Final M750 UI over SD with `debug1` (no UART) plus `zlink` fix

[Español](19-ui-final-m750-por-sd.es.md) · [Back](../README.md)

**Keywords:** `debug1`, FAT32 superfloppy SD, `mtdblock2`, `mtdblock5`, bootlogo, `zlink.xml`, brightness/home widget, no UART, M750

This document closes the M750 case. After restoring the stock 16 MiB NOR ([doc 18](18-m750-uart-recovery.md)), the pre-TPMS-widget design was flashed and then the blank space at the top of the brightness/home widget was fixed. **Everything was done by booting only from the SD**: `debug1` runs as root from `/mnt/extsd` at boot and writes directly to MTD. No U-Boot `sf` commands were needed.

---

## 1. Starting point

The board already booted from the stock dump (MD5 `8c0abbd6e0f327e5d9ab38146a90f5ca`). Kept:

- `mtdblock2` (rootfs) with the **layout2** custom UI: new BG, 8 icons, AERUNO font, large centred clock and FRO/BAC on top, **no TPMS bar**.
- `mtdblock5` (bootlogo) with the working logo: MD5 `d105460a6164c8d5e861f337b429f873`.

Relevant MTD layout (erase block `0x10000`):

| MTD | Offset | Size | Use |
|---|---:|---:|---|
| `mtdblock2` | `0x290000` | `0xcb0000` (13 MB) | rootfs / UI |
| `mtdblock5` | `0xfb0000` | `0x20000` (128 KB) | bootlogo |

---

## 2. Files used

| File on SD | MD5 | Purpose |
|---|---|---|
| `debug1` | `7ebe0b0e843747972fa101554ee89bc0` | Final script that writes rootfs and bootlogo |
| `busybox_net` | `10ac2a1c34b0b02f2d0ce7a4420ade5c` | Static BusyBox with `telnetd` for debugging |
| `mtdblock2_custom.bin` | `2a3fb11dfe526948908e2a5e9148f855` | **Final** = layout2 + `zlink.xml` fix, no TPMS |
| `bootlogo.bin` | `d105460a6164c8d5e861f337b429f873` | «Proyecto nuevo» bootlogo |
| `dump_completo.bin` | `8c0abbd6e0f327e5d9ab38146a90f5ca` | NOR backup |

The intermediate `layout2` rootfs (MD5 `fa89ce4593b1b67fee2d3e8d381ac340`) is kept as reference. The exact script is in [`examples/debug1-M750-sd-only.sh`](../examples/debug1-M750-sd-only.sh).

---

## 3. Exact `zlink.xml` change

The brightness/home widget had a blank area at the top because the group started at `top="180"` with `height="300"` and its buttons were shifted 60 px down. The fix (identical to `mtdblock2_final.bin`) is:

```diff
--- layout2/data/res/layout/zlink.xml
+++ final/data/res/layout/zlink.xml
@@ -233,9 +233,9 @@
 			bgColor="128|128|128"
 			radius="15"
 			left="754"
-			top="180"
+			top="240"
 			width="100"
-			height="300">
+			height="240">
@@ -247,31 +247,31 @@
 			<imgbtn name="zlink_btn_drag_vol"      top="60"  -> top="0" />
 			<imgbtn name="zlink_btn_drag_bright"   top="140" -> top="80" />
 			<imgbtn name="zlink_btn_drag_exit"     top="220" -> top="160" />
 			<imgbtn name="zlink_btn_drag_bright1"  top="60"  -> top="0" />
 			<imgbtn name="zlink_btn_drag_exit1"    top="140" -> top="80" />
```

It is the **only** file that differs between `layout2` and `final` (573 files in each squashfs). No TPMS bar was added.

---

## 4. Procedure with SD

The card must be **FAT32 superfloppy** (no MBR) because the firmware mounts `/dev/mmcblk0`, not `/dev/mmcblk0p1`. Either write a prepared `.img` with `scripts/write_sd_windows.ps1` or copy the five files to the root.

1. Power off the M750.
2. Insert the SD with the files from section 2.
3. Power on and wait **40-60 s**. `S01app` runs `/mnt/extsd/debug1` as root.
4. The script:
   - saves `mtdblock2_original_backup.bin` and `bootlogo_original_backup.bin` if absent;
   - verifies MD5 from the SD and from `/tmp` before writing;
   - clears whiteouts in `/overlay/upper` (`home_main.xml`, `zlink.xml`, `tyre_warn.xml`, `config_devmng.xml` and images);
   - `dd`s to `/dev/mtdblock2` and reads back to verify;
   - creates flags `rootfs_final.done` / `bootlogo.done`;
   - starts `telnetd` on port 23 for debugging.
5. Power off, **remove the SD** and power on without it.

> If `bootlogo.done` already exists from a previous flash, the bootlogo step is skipped. Delete it only if you want to rewrite the logo.

---

## 5. Verification

Remove the SD and open `debug1.log`. For the `zlink` update it should contain:

```text
[debug1] rootfs MD5 SD      : 2a3fb11dfe526948908e2a5e9148f855
[debug1] rootfs MD5 leido  : 2a3fb11dfe526948908e2a5e9148f855
[debug1] ROOTFS FINAL (zlink sin hueco) GRABADO Y VERIFICADO
[debug1] creado /mnt/extsd/rootfs_final.done
[debug1] bootlogo.done existe -> bootlogo ya grabado, omito
[debug1] telnetd ACTIVO en puerto 23 (debug)
[debug1] Si todo salio bien: APAGA, SACA LA SD Y ENCIENDE SIN SD
```

Visible result: «Proyecto nuevo» bootlogo, home with new BG, 8 icons, AERUNO, large centred clock, FRO/BAC on top, brightness/home widget without the blank top area and **no TPMS widget**.

---

## 6. Retries

- To redo the rootfs: delete `rootfs_final.done`.
- To redo the bootlogo: delete `bootlogo.done`.
- The SD backups allow reverting with `dd if=mtdblock2_original_backup.bin of=/dev/mtdblock2` and the equivalent for `mtdblock5`.

From WSL everything was copied to Windows drive `F:` by invoking `powershell.exe`, and every MD5 was checked with `Get-FileHash -Algorithm MD5`; the SD appears as a ~128 MB FAT32 volume labelled `FIRMWARE`.
