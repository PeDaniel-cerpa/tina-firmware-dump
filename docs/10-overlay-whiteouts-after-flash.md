# 10 - Missing images after flashing the rootfs (overlay whiteouts)

[Español](10-whiteouts-overlay-tras-grabar.es.md) · [Back](../README.md)

**Keywords:** overlayfs whiteout, /overlay/upper, missing images, sdvcam no icons, mtdblock2 flash, image.bin.lzma hidden, Tina Linux rootfs

This documents a real failure that happened after baking custom images into `mtdblock2` (doc 09). The system booted normally but the UI showed **no images at all**. It was confirmed fixed on the M750 screen by removing the overlay whiteouts.

---

## 1. Symptom

- The flash script finished successfully and printed `ROOTFS GRABADO Y VERIFICADO`.
- `F:\rootfs_custom.done` existed.
- After removing the SD and powering on, Linux booted and the bootlogo appeared.
- The `sdvcam` interface started but every icon and the background were missing.

The first reaction was to suspect a truncated image archive, but the archive was intact. The delay that caused the user to power off happened **after** the flash had already finished, so the rootfs itself was fine.

---

## 2. Root cause

`/data` is not a plain directory. It is part of the squashfs root (`lowerdir`) exposed through overlayfs:

```text
/dev/by-name/rootfs_data  /overlay          jffs2  rw   (320 KB)
overlayfs:/overlay        /                 overlayfs  rw
  lowerdir=/ (squashfs)
  upperdir=/overlay/upper
  workdir=/overlay/workdir
```

The flash script did this before writing the new rootfs:

```sh
rm -f /data/res/pic/image.bin.lzma
rm -f /data/res/pic/bin/hm_bg.jpg
...
```

In overlayfs, deleting a file that exists only in the lower layer does **not** delete the lower file. It creates a **whiteout** (a character device `0:0`) in `/overlay/upper`. After the new rootfs was written, those whiteouts were still there and kept hiding the freshly installed files.

So the images were present in the new squashfs, but invisible at `/data/...`.

---

## 3. Why copying files to `/data` does not fix it

A whiteout wins over a lower file. Copying a file to `/data/...` would create an upper file only if the whiteout is gone first; otherwise the path still resolves as "deleted". Also, the overlay has just **320 KB** free, so copying the ~474 KB `image.bin.lzma` into it is not possible.

The whiteout must be removed from the real upper filesystem:

```sh
rm -f /overlay/upper/data/res/pic/image.bin.lzma
rm -f /overlay/upper/data/res/pic/bin/hm_bg.jpg
...
```

Note the path: `/overlay/upper/...`, not `/data/...`.

---

## 4. The fix that was applied

[`files/debug1-fix-overlay-whiteouts.sh`](../files/debug1-fix-overlay-whiteouts.sh) was copied to the SD as `debug1`:

```text
F:\debug1                 MD5 934ec0807dd824fe83593dc17cf1abbd
F:\rootfs_custom.done     SI (rootfs ya grabado)
```

Procedure used:

1. Power off, insert SD, power on.
2. Wait **20-30 s** (nothing is flashed; it only cleans the overlay).
3. Power off and read `F:\debug1.log`.
4. Remove the SD and power on.

The script removes only these 10 upper entries:

```text
data/res/pic/image.bin.lzma
data/res/pic/bin/hm_bg.jpg
data/res/pic/bin/hm_auto_icon.png
data/res/pic/bin/hm_hicar_icon.png
data/res/pic/bin/hm_gps_icon_0.png ... hm_gps_icon_5.png
```

It also removes `/tmp/image.bin` so `sdvcam` re-extracts the archive from the new rootfs, then prints MD5 checks of the now-visible files:

```text
[debug1] image.bin.lzma visible: 53533ecef3a9084db898df5037ca9d0d
[debug1] hm_bg.jpg visible: 29c75c931c8c8e19c2dabe7a15b32171
[debug1] hm_auto_icon.png visible: 8f594a4bc3fedfe4315e9d96d8e31d45
[debug1] creado /mnt/extsd/overlay_fix.done - apaga y enciende SIN SD
```

Result: **confirmed working**. All images and the custom colours appeared after booting without the SD.

---

## 5. Prevention for future rootfs flashes

A rootfs flashing script should never leave whiteouts behind. Either:

- do not `rm` lower files before flashing, or
- after writing `mtdblock2`, clean `/overlay/upper/data/res/pic/...` in the same boot, or
- boot once with the fix script (doc 09, section 4) before using the screen without the SD.

The fix is idempotent: running it again just reports `sin entrada upper: ...` for each file and is harmless.

---

## 6. Rollback context

If you ever need to return to the factory rootfs, the original partition was saved before flashing:

```text
F:\mtdblock2_original_backup.bin   MD5 43acc068c9d79de63e480970d2ff72e3
```

Copy it over `F:\mtdblock2_custom.bin`, delete `F:\rootfs_custom.done`, boot with the SD once, then power cycle. If images disappear again, run this whiteout fix as well.
