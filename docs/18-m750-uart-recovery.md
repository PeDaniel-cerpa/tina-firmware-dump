# 18 - Real M750 recovery over UART (solved)

[Español](18-recuperacion-m750-por-uart.es.md) · [Back](../README.md)

**Keywords:** M750, V553, V853, V533, PhoenixCard, boot_package, sunxi-package, U-Boot `sf`, `sf probe`, `fatload`, `sunxi_card0_probe`, CRC32, SPI NOR recovery, black screen, no backlight, bootlogo, 16 MB dump

> **Final result:** the M750 showed its bootlogo again and booted all the way into the **home screen**. The 16 MiB SPI NOR was restored byte-for-byte from the board's own dump (`M750_16MB_stock.bin`, MD5 `8c0abbd6e0f327e5d9ab38146a90f5ca`). Re-flashing the custom UI was not necessary.
>
> This document records the whole process, including the failed attempts, so it can be reproduced without repeating the mistakes.

---

## 1. Symptom and starting point

- Device: M750 CarPlay screen, Tina Linux, 16 MiB `py25q128ha` SPI NOR.
- Symptom: bootlogo/black screen after changing UI files in `mtdblock2`.
- Initial constraints: no USB data cable, no serial console, no buttons, no display ports, no teardown.
- A full `debug1` dump already existed (docs 01-10):

```text
dump_completo.bin
Size:    16777216 bytes (0x1000000)
MD5:     8c0abbd6e0f327e5d9ab38146a90f5ca
SHA256:  f0bd763cff93f829b2cdabc026489c30b922b754c2a32053645ae90ac7f26dea
CRC32:   aed73153
```

- Factory `rootfs` (`mtdblock2`): MD5 `43acc068c9d79de63e480970d2ff72e3`.
- Final UI `rootfs` built during the work: MD5 `2a3fb11dfe526948908e2a5e9148f855` (`/tmp/opencode/mtdblock2_final.bin`) — **not needed in the end**.
- Current `bootlogo` (`mtdblock5`): MD5 `d105460a6164c8d5e861f337b429f873`.

---

## 2. What did not work (and why)

### 2.1 PhoenixCard with V853 images

Donor: `v853_linux_100ask_uart0.img` (MD5 `3fe608b451408643802f47451be0c70c`), accepted by PhoenixCard in **Startup** mode.

Findings:

1. **PhoenixCard checks the file name.** Renaming the original made it fail; the exact name `v853_linux_100ask_uart0.img` burned fine. Changing one filler byte also burned fine, so rejection was not generic integrity checking.
2. **The real rejection came from changing the `boot_package` structure.** The original 100ask package has `valid_len=0x10c000` and 3 items:

   | Item | Offset | Length |
   |---|---:|---:|
   | `optee` | `0x800` | `0xc098` |
   | `u-boot` | `0xcc00` | `0xe0000` |
   | `dtb` | `0xecc00` | `0x1c000` |

   Changing item count, offsets or lengths produced:

   ```text
   E: [pheonix card_00]Burn Sucess
   E: Burn Failed -1
   No Drive
   ```

   Keeping the 3 items/offsets/lengths and only replacing payload bytes burned correctly.
3. Reverse-engineered checksums:
   - `V*.fex`: sum of little-endian dwords `& 0xffffffff`, stored little-endian (not CRC32/MD5).
   - `sunxi-package`: `STAMP = 0x5F0A6C39` at `+0x14`; checksum = dword sum over `pkg[:valid_len]`.
4. M750 package payloads must be **raw**:
   - `u-boot`: `8e0100ea75626f6f74…`
   - `dtb`: `d00dfeed…` (114290-byte decompressed DTB)
   - item flag `3` for both.

Generated variants:

| Image | MD5 | Result |
|---|---|---|
| `M750_100ASK_SAMELEN.img` | `4199ca49aa7868a0a185936aa9efe39d` | Burned in Startup; no useful boot |
| `M750_100ASK_COMBINED.img` | `694029fc799fa90fa9dcbb8ed90ca8f3` | Burned; screen with **no backlight** |
| `M750_100ASK_DTBONLY.img` | `b7a8f2f2fda64db354c01073589d9ecd` | Built to isolate the DTB; did not fix boot |
| `M750_SD_FULL.img` | `a4eef4bc3be0821fe46dbc7a09f833f8` | Extended cardscript with ENV/BOOT/ROOTFS; no boot |
| Original 100ask | `3fe608b451408643802f47451be0c70c` | Burned; black screen |
| R12 V533 854x480 | `11f65f1efdeddb8fa6bdf212b2259051` | Closest V533 donor prepared; no successful boot |

### 2.2 The decisive clue

With any of those SD cards inserted, the M750 had **no backlight at all**. With the SD removed, the original bootlogo came back. That proved:

- the NOR was still fine and booted by itself;
- the failure happened when trying to boot from SD, before panel initialization.

Also, the 100ask `cardscript.fex` has only two steps:

```ini
[boot_0_0]   ; boot0 at LBA 16
[boot_1_0]   ; boot_package at LBA 32800
```

PhoenixCard **Startup** therefore writes only boot0 + boot_package. Adding cardscript steps did not help because the problem was SoC compatibility, not SD partitions.

---

## 3. The real hardware

Opening the board showed the chip marking **V553**. That explains everything:

| | Firmware / attempts | Actual hardware |
|---|---|---|
| String in `boot.img` | `v853-perf1` | — |
| SDK / platform attempted | `sun8iw21p1`, Cortex-A7 | `sun50i`, 4x Cortex-A53 |
| Soldered chip | — | **V553** (V533/V536 family) |

- **V553**: 4x Cortex-A53, Mali-T720 MP2, 4K@30 decode. Better for UI/general use.
- **V853 / V853S**: Cortex-A7 + RISC-V, ~1 TOPS NPU, no dedicated GPU. Better for vision/AI, but **a different architecture**.
- **V533**: sibling of V553 (same A53/sun50i family). That is why R12/RX7/T86/BK1 were the closest donors, though still not the exact chip.

> Historical correction: the repo previously said "M750 = v853" based on the firmware string. The string is the **build target**, not the physical chip. The correct recovery was to use the dump from the board itself. See also the correction note in [05-screen-analysis.md](05-screen-analysis.md).

---

## 4. UART console: the turning point

The user got **TX/RX** (plus GND) working at **115200 baud**. That made it possible to drop PhoenixCard and write the NOR directly from U-Boot.

### 4.1 Prompt and initial commands

```text
=> help
...
sf      - SPI flash sub-system
sunxi_card0_probe- probe sunxi card0 device
...
```

Relevant `printenv` lines:

```text
bootcmd=run setargs_nor boot_normal
boot_normal=sunxi_flash read 44800000 ${boot_partition};bootm 44800000
boot_partition=boot
nor_root=/dev/mtdblock2
partitions=boot@mtdblock1:rootfs@mtdblock2:rootfs_data@mtdblock3:env@mtdblock4:bootlogo@mtdblock5:private@mtdblock6:UDISK@mtdblock7
uboot_message=2018.07-g7572878-dirty(06/15/2026-06:26:11)
```

`sf probe 0`:

```text
sf: bus-0 cs-0 spedd-50000000Hz mode-3000
SF: Detected py25q128ha(IO DTR) with page size 256 Bytes, erase size 64 KiB, total 16 MiB
```

`bdinfo`:

```text
DRAM bank 0: start 0x40000000, size 0x08000000   ; 128 MiB
baudrate    = 115200 bps
fdt_blob    = 43ee0e68
```

U-Boot runs from RAM and `sf` sees the whole NOR: we can flash without Linux or PhoenixCard.

### 4.2 Initialize the SD

`mmcinfo` fails at first:

```text
=> mmcinfo
curr_device:-1
No MMC device available
```

Use the Allwinner-specific command:

```text
=> sunxi_card0_probe
curr_device:0
Device: SUNXI SD/MMC
Name: APPSD
Capacity: 3.8 GiB
=> fatls mmc 0
            System Volume Information/
  16777216   dump_completo.bin
```

---

## 5. Prepare the SD

1. Format a microSD as **FAT32 superfloppy** (no MBR/GPT), same as for the `debug1` hook.
2. Copy the board's own 16 MiB dump to the root:

```text
F:\dump_completo.bin      ; MD5 8c0abbd6e0f327e5d9ab38146a90f5ca
```

In this repo it is [`dumps/M750/M750_16MB_stock.bin`](../dumps/M750/M750_16MB_stock.bin).

---

## 6. Exact flashing sequence

Run **one line at a time** at the `=>` prompt:

```text
sunxi_card0_probe
fatload mmc 0 0x42000000 dump_completo.bin
sf probe 0
sf erase 0x10000 0xff0000
sf write 0x42010000 0x10000 0xff0000
sf erase 0 0x10000
sf write 0x42000000 0 0x10000
```

Real output:

```text
16777216 bytes read in 757 ms (21.1 MiB/s)
SF: 16711680 bytes @ 0x10000 Erased: OK
SF: 16711680 bytes @ 0x10000 time:17073 ms Written: OK
SF: 65536 bytes @ 0x0 Erased: OK
SF: 65536 bytes @ 0x0 time:59 ms Written: OK
```

### Why this order

- Write **everything except boot0** first (`0x10000..0xffffff`). If it fails, U-Boot still starts and you can retry.
- Write **boot0 last**. It is the only part that can brick booting if power is lost.
- `0x42000000` holds the whole dump; the rest is written from `0x42010000` (skipping boot0), then boot0 from `0x42000000`.

### Normal warnings

```text
ERROR: reserving fdt memory region failed (addr=48000000 size=400000)
...
```

These are `fatload` FDT reservation warnings, not read failures.

If `sf` temporarily reports `Unknown command 'sf'` after the transfer, just type `sf` and press Enter: the usage appears and you can continue. It was a serial glitch, not a removed command.

---

## 7. Verification

Reading the **whole chip** fails due to DMA:

```text
=> sf read 0x43000000 0 0x1000000
device 0 whole chip
rx wait_dma_recv_over fail
SF: ... Read: ERROR -1
=> crc32 0x43000000 0x1000000
CRC32 ... ==> 6f3b4103     ; do NOT trust this value
```

Verify **small blocks** instead:

```text
=> sf read 0x43000000 0 0x10000
device 0 offset 0x0, size 0x10000
rx wait_dma_recv_over fail
SF: ... Read: ERROR -1
=> crc32 0x43000000 0x10000
CRC32 for 43000000 ... 4300ffff ==> 5560ecb6
```

`5560ecb6` is exactly the boot0 CRC32 from the dump. The `rx wait_dma_recv_over fail` message still appears, but **small reads return correct data**.

Reference CRCs:

| Range | Size | CRC32 |
|---|---:|---|
| `0x0..0xffff` (boot0) | `0x10000` | `5560ecb6` |
| `0x10000..0xffffff` (rest) | `0xff0000` | `698f2fc1` |
| Full dump | `0x1000000` | `aed73153` |
| `0x10000..0x5ffff` (package) | `0x50000` | `4a57c7dc` |
| `0x60000..0x28ffff` (boot) | `0x230000` | `43260230` |
| `0x290000..0xf3ffff` (rootfs) | `0xcb0000` | `3038e714` |
| `0xf90000..0xfaffff` (env) | `0x20000` | `a3293403` |
| `0xfb0000..0xfcffff` (bootlogo) | `0x20000` | `ce3c4937` |

---

## 8. Reset and final result

```text
=> reset
```

After reset:

- the **bootlogo** came back;
- the system kept booting and reached the **home** screen;
- the display worked perfectly.

Re-flashing the final UI rootfs or touching the bootlogo was not needed: the complete factory dump was enough.

---

## 9. Reproduction checklist

1. Use the dump from the **same device**: MD5 `8c0abbd6e0f327e5d9ab38146a90f5ca`.
2. FAT32 superfloppy SD with `dump_completo.bin` in the root.
3. UART 115200 8N1, common GND; stop at `=>`.
4. `sunxi_card0_probe` → `fatls mmc 0` must list 16777216 bytes.
5. `fatload mmc 0 0x42000000 dump_completo.bin`.
6. `sf probe 0` → detect `py25q128ha`, 16 MiB, 64 KiB erase.
7. Erase/write the rest, then boot0 (section 6 order).
8. Verify boot0: `crc32 0x43000000 0x10000` → `5560ecb6`.
9. `reset`.
10. **Do not power off** during `sf erase`/`sf write`.

### Do not

- Do not flash V853/V837S/V873S images onto a V553 board.
- Do not trust a full-chip `sf read`.
- Do not use PhoenixCard Product/NOR without validating SD boot and layout first.
- Do not mix TF811 and M750 dumps: different `boot`/`rootfs`, RAM and panel.

---

## 10. Related files

- [Full dumps](../dumps/README.md) — TF811 and M750, with hashes.
- [Doc 05](05-screen-analysis.md) — two-board comparison (with chip correction).
- [Doc 11](11-podofo-a4628-uart-dump.md) — origin of the UART method.
- [`examples/uart-restore-M750.txt`](../examples/uart-restore-M750.txt) — sanitized transcript of the working session.
