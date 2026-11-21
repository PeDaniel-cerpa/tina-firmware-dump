# 09 - Making custom UI images permanent

[Español](09-imagenes-permanentes.es.md) · [Back](../README.md)

**Keywords:** permanent boot rootfs, mtdblock2, squashfs, custom hm_bg, image.bin.lzma, flash rootfs from SD, no SD dependency

By default the custom images installed with doc 08 still depend on the SD because `image.bin.lzma` is symlinked from the card. This guide bakes those images into a rebuilt `mtdblock2`, so they survive without the SD and after a factory reset of the overlay.

---

## 1. What was built

Starting from the original `mtdblock2.bin` extracted rootfs:

- Replaced only these files with the user-supplied versions:
  - `data/res/pic/bin/hm_bg.jpg`
  - `data/res/pic/bin/hm_auto_icon.png`
  - `data/res/pic/bin/hm_hicar_icon.png`
  - `data/res/pic/bin/hm_gps_icon_0.png` … `hm_gps_icon_5.png`
- Replaced `data/res/pic/image.bin.lzma` with a version where **only those 9 entries** were patched; every other byte of the archive is unchanged.
- Rebuilt the squashfs with `mksquashfs -noappend -all-root -comp xz -b 262144`.
- Padded to the exact partition size `0xCB0000` (13,303,808 bytes) with `0xFF`.

Result:

```text
mtdblock2_custom.bin
MD5:      88a9d4a56d1f9f11e67ab1029926909b
SHA256:   28a89c0c73b06f8c05035853391cd52de8fbf31cee04fa4cabc2c35ba7573861
Size:     13,303,808 bytes
```

---

## 2. SD layout

```text
F:\debug1                       <- files/debug1-flash-rootfs.sh renamed
F:\mtdblock2_custom.bin         <- the image above
F:\debug1_before_rootfs         <- backup of the previous debug1
F:\mtdblock2_original_backup.bin <- created by the script on first run
F:\rootfs_custom.done           <- created only after MD5 verification
```

The script also removes the overlay leftovers from the previous SD-only method:

```text
/data/res/pic/image.bin.lzma          (symlink)
/data/res/pic/bin/hm_bg.jpg
/data/res/pic/bin/hm_auto_icon.png
/data/res/pic/bin/hm_hicar_icon.png
/data/res/pic/bin/hm_gps_icon_0..5.png
/tmp/image.bin
```

It does **not** touch `mtdblock5` (bootlogo) or the WiFi SSID.

---

## 3. Procedure

1. Make sure the screen is powered off.
2. Insert the SD and power on.
3. Wait **60-90 seconds**. Flashing 13 MB is slower than flashing the bootlogo.
4. Power off and read `F:\debug1.log`.

Expected log:

```text
[debug1] guardando rootfs original en /mnt/extsd/mtdblock2_original_backup.bin
[debug1] MD5 SD   : 88a9d4a56d1f9f11e67ab1029926909b
[debug1] MD5 /tmp : 88a9d4a56d1f9f11e67ab1029926909b
[debug1] grabando mtdblock2 (13303808 bytes)
[debug1] MD5 leido   : 88a9d4a56d1f9f11e67ab1029926909b
[debug1] ROOTFS GRABADO Y VERIFICADO
[debug1] APAGA Y ENCIENDE para usar el rootfs nuevo
```

5. Remove the SD and power on. The custom images should now load from flash.

---

## 4. Risks and rollback

**Do not cut power during the write.** If the MD5 check fails, `rootfs_custom.done` is not created and you can retry.

To restore the factory rootfs:

```text
copy F:\mtdblock2_original_backup.bin -> F:\mtdblock2_custom.bin
delete F:\rootfs_custom.done
boot once with the SD
power cycle
```

After that, restore your preferred `debug1` from the SD backups.

### Images missing after the first boot

If the system boots but the UI has no images, the flash script's `rm -f` on `/data/...` created **whiteouts** in the overlay upperdir. Those whiteouts hide the files that are now inside the rebuilt squashfs. They are not fixed by copying files back to `/data`; they must be deleted from `/overlay/upper` directly.

Copy [`files/debug1-fix-overlay-whiteouts.sh`](../files/debug1-fix-overlay-whiteouts.sh) as `debug1`, boot once with the SD, wait ~20 s, power off, check `debug1.log`, then boot **without** the SD. The script removes only the 10 whiteouts and prints MD5 checks of the now visible files.

---

## 5. Rebuilding with other images

```sh
# 1) decompress the original archive
unlzma -c m750root/data/res/pic/image.bin.lzma > image.bin

# 2) patch only your files inside image.bin (same format: 64-byte name,
#    12-byte metadata, raw BGRA8888 pixels). See scripts/recolor_ui.py
#    for the entry parser.

# 3) replace the loose files and recompress
lzma -c image.bin > m750root/data/res/pic/image.bin.lzma

# 4) repack
mksquashfs m750root mtdblock2_custom.bin \
    -noappend -all-root -comp xz -b 262144
truncate -s 13303808 mtdblock2_custom.bin
python3 - <<'PY'
p='mtdblock2_custom.bin'
b=open(p,'r+b'); b.seek(12033501); b.write(b'\xff'*(13303808-12033501)); b.close()
PY
```

The padding offset above is the squashfs filesystem size printed by `unsquashfs -s`; use the value from your own build.
