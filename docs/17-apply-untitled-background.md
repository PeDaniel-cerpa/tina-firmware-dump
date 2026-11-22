# 17 - Apply `Untitled-1.jpg` as the home background

[Español](17-aplicar-fondo-untitled.es.md) · [Back](../README.md)

**Keywords:** Untitled-1.jpg, hm_bg replacement, BGRA8888 packed entry, rebuild mtdblock2, rootfs background, overlay whiteouts

This records the exact change made when the user supplied `C:\Users\pedan\Downloads\Untitled-1.jpg` as the new home background.

---

## 1. Source image

```text
C:\Users\pedan\Downloads\Untitled-1.jpg
854x480, baseline JPEG, 496,410 bytes
MD5    c68f0bad9c1d541f3b117b057abf77d7
SHA256 26294fbd442d1519a539dbf829eb5b41b6b3413a2c6c3bdddf649b301620c7a4
```

It is already the declared widget size (`854 × 480`), so no resizing was needed. It fits comfortably in the 1.27 MB spare space of `mtdblock2` (doc 16).

---

## 2. What was patched

Both copies of the background were replaced so the screen and the packed resource loader agree:

| Target | Before | After |
|---|---|---:|
| `data/res/pic/bin/hm_bg.jpg` | 140,795 bytes | 496,410 bytes |
| `hm_bg.jpg` entry inside `image.bin` | 1,639,680 B BGRA | same size, new pixels |
| `data/res/pic/image.bin.lzma` | 590,593 bytes | 975,348 bytes |

The packed entry keeps its header:

```text
descriptor = 0x1e035605   (format 5, 854x480)
data_size  = 1,639,680    = 854 * 480 * 4
```

Only the 1,639,680 bytes of raw BGRA8888 pixels changed. Every other entry in `image.bin` is byte-for-byte identical, and the other 8 custom images (`hm_auto_icon`, `hm_hicar_icon`, `hm_gps_icon_0..5`) were not touched.

The replacement was done with [`scripts/replace_packed_image.py`](../scripts/replace_packed_image.py), which decodes the JPEG to RGBA, swaps R/B into BGRA and verifies the dimensions against the entry descriptor.

---

## 3. Rebuilt rootfs

```sh
mksquashfs m750root_untitled mtdblock2_untitled.bin \
    -noappend -all-root -comp xz -b 262144
truncate -s 13303808 mtdblock2_untitled.bin
# pad from the squashfs size (12,949,476) to the partition end with 0xFF
```

| Field | Value |
|---|---|
| Partition size | 13,303,808 bytes |
| Squashfs size | 12,949,476 bytes |
| Free space left | 354,332 bytes |
| MD5 | `a07151afca25933809575fe0bf96cc90` |
| SHA256 | `c967c7f04c007e3f5d72aee6fbd0514e0af32c0e271e24ceb10abd659d54f87d` |

Inside the squashfs:

```text
data/res/pic/bin/hm_bg.jpg    MD5 c68f0bad9c1d541f3b117b057abf77d7
data/res/pic/image.bin.lzma   MD5 7dc5a5d46047897ed6c65299ed061630
```

---

## 4. Delivered files

A ready-to-copy folder was placed on the Windows side:

```text
C:\Users\pedan\Downloads\Firmware_Hunk_Untitled_BG\
    mtdblock2_custom.bin
    debug1-flash-bg
    debug1-fix-whiteouts
    hm_bg.jpg
    README.txt
```

[`files/debug1-flash-untitled-bg.sh`](../files/debug1-flash-untitled-bg.sh) is a variant of the flash script with:

```text
FLAG=/mnt/extsd/rootfs_bg.done
EXPECTED=a07151afca25933809575fe0bf96cc90
```

It uses a **new flag** (`rootfs_bg.done`), so the existing `rootfs_custom.done` does not block reflashing. It keeps the existing `mtdblock2_original_backup.bin`.

---

## 5. Flashing steps (summary)

1. Copy `mtdblock2_custom.bin` and `debug1-flash-bg` to the SD root; rename the latter to `debug1` (no extension).
2. Boot with the SD, wait 30–40 s, power off. Check `debug1.log` for `ROOTFS GRABADO Y VERIFICADO` and `rootfs_bg.done`.
3. Replace SD `debug1` with `debug1-fix-whiteouts`; boot once with the SD, wait 20–30 s, power off. This removes the whiteouts created by step 2.
4. Remove the SD and boot normally. The new background is now permanent.

See docs 09-10 for the full reasoning about squashfs rebuilds and overlayfs whiteouts.

---

## 6. Verification expected on the device

`debug1.log` from step 3 should contain:

```text
[debug1] hm_bg.jpg visible: c68f0bad9c1d541f3b117b057abf77d7
[debug1] image.bin.lzma visible: 7dc5a5d46047897ed6c65299ed061630
```

If those MD5s appear, both the loose JPEG and the packed resource are coming from the new rootfs and the SD is no longer needed.
