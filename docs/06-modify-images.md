# 06 - Modifying the screen images

[Español](06-modificar-imagenes.es.md) · [Back](../README.md)

**Keywords:** change carplay screen image, allwinner bootlogo, mtdblock5 jpeg, head unit wallpaper, modify tina linux firmware, overlayfs rootfs, replace boot logo

Guide to changing the images in the dumped firmware. There are **three different places**, depending on what you want to change:

| Want to change… | Location | Difficulty |
|---|---|---|
| The logo shown at power-on | `mtdblock5` (`bootlogo` partition) | Easy |
| Interface backgrounds / icons | `/data/res/pic/` inside rootfs | Easy with overlay |
| The base firmware (to distribute it) | `mtdblock2` (squashfs) | Advanced |

---

## 1. Identify which image you want to change

### Boot logo

The `bootlogo` partition is **a plain 854x480 JPEG**, no special header, padded with `0xFF` up to 131072 bytes (128 KB).

You already have a copy of the original on the SD:

```
F:\bootlogo_original_M750.jpg
```

Open it on Windows to check whether it is what you want to change.

> **If your new screen is a different model:** do not reuse this JPEG blindly. First dump it with the [procedure](02-procedure.md) and check the size of `mtd5` and the panel resolution in `info.txt`. The format is always baseline JPEG, but dimensions may differ. `make_bootlogo.sh` exposes `W`/`H` as variables at the top of the file.

### Interface backgrounds

Inside the rootfs (`mtdblock2`) there are, among others:

```text
data/res/pic/bin/auto_des.png      460x280  <- "auto" mode background
data/res/pic/bin/carplay_des.png   460x280  <- CarPlay background
data/res/pic/bin/hicar_des.png     460x280  <- HiCar background
data/res/pic/bin/carlife_des.png   460x280  <- CarLife background
data/res/pic/bin/elook_des.png     460x280
data/res/pic/osdlogo.png           208x48
data/res/pic/carplay_car.png       105x105
```

There are 222 PNG images in total under `data/res/pic/`.

---

## 2. Change the boot logo

### 2.1 Generate the file

With the included tool:

```bash
scripts/make_bootlogo.sh my_logo.png bootlogo.bin
```

The script:

1. Resizes to **854x480** (padding with black if needed).
2. Converts to **baseline JPEG** (mandatory; the bootloader does not understand progressive).
3. Pads with `0xFF` to exactly **131072 bytes**.

Verification:

```bash
file bootlogo.bin
# JPEG image data ..., baseline, precision 8, 854x480, components 3
stat -c%s bootlogo.bin
# 131072
```

> If your JPEG exceeds 128 KB, lower the quality: `-q:v 4` for ffmpeg or `-quality 80` for convert.

### 2.2 Copy to the SD

```
F:\bootlogo.bin
```

### 2.3 Write it to the screen from the root shell

Connect with Tera Term to `192.168.10.1:23` and run:

```sh
# 1) Copy to /tmp (the SD may be unmounted during the write)
cp /mnt/extsd/bootlogo.bin /tmp/bootlogo.bin

# 2) Erase the bootlogo partition (128 KB = 131072 bytes)
dd if=/dev/zero of=/dev/mtd_name/bootlogo bs=1024 count=128

# 3) Write the new logo
dd if=/tmp/bootlogo.bin of=/dev/mtd_name/bootlogo bs=1024 count=128
sync

# 4) Verify: the md5 hashes must match
md5sum /tmp/bootlogo.bin /dev/mtd_name/bootlogo
```

You can also use `/dev/mtdblock5` directly if `/dev/mtd_name/bootlogo` does not exist (it is created by `S00part` at boot).

### 2.4 Reboot and check

```sh
reboot
```

Your image should appear instead of the original logo.

### 2.5 Rollback

Do not delete `F:\bootlogo_original_M750.jpg`. To restore the factory logo:

```sh
cp /mnt/extsd/bootlogo_original_M750.jpg /tmp/orig.bin
dd if=/dev/zero of=/dev/mtd_name/bootlogo bs=1024 count=128
dd if=/tmp/orig.bin of=/dev/mtd_name/bootlogo bs=1024 count=128
sync
reboot
```

---

## 3. Change backgrounds / icons without reflashing rootfs

The firmware mounts an **overlayfs**:

```text
/dev/by-name/rootfs_data  -> /overlay   (jffs2, writable)
overlayfs:/overlay / overlay  lowerdir=/, upperdir=/overlay/upper
```

Any file placed in `/overlay/upper/...` **replaces** the read-only rootfs version. There is no need to unpack or rebuild the squashfs.

Example to change the CarPlay background:

```sh
# On the PC: create a 460x280 carplay_des.png and copy it to F:\

# On the screen, via telnet:
mkdir -p /overlay/upper/data/res/pic/bin
cp /mnt/extsd/carplay_des.png /overlay/upper/data/res/pic/bin/carplay_des.png
sync
reboot
```

For the OSD logo:

```sh
mkdir -p /overlay/upper/data/res/pic
cp /mnt/extsd/osdlogo.png /overlay/upper/data/res/pic/osdlogo.png
sync
reboot
```

**Precautions:**

- The `rootfs_data` (`/overlay`) partition is only **320 KB**. Do not add many large images.
- Use PNG with the **same dimensions and format** as the original (RGBA for `*_des.png`).
- Some images may be cached by the app; reboot the screen.
- If something goes wrong, delete the overlay file and reboot:

```sh
rm /overlay/upper/data/res/pic/bin/carplay_des.png
reboot
```

---

## 4. Modify the base firmware (advanced)

If you want to **distribute** a modified firmware (not just change your own screen), you must rebuild the squashfs.

### 4.1 Extract

```bash
unsquashfs -d rootfs mtdblock2.bin
```

### 4.2 Modify

Edit files inside `rootfs/data/res/pic/`.

### 4.3 Repack

The original uses **xz, block size 262144**:

```bash
mksquashfs rootfs mtdblock2_nuevo.bin \
    -comp xz -b 262144 -noappend
```

Verify with:

```bash
unsquashfs -s mtdblock2_nuevo.bin
```

### 4.4 Write

```sh
dd if=/dev/zero of=/dev/mtd_name/rootfs bs=1024 count=12992
dd if=/mnt/extsd/mtdblock2_nuevo.bin of=/dev/mtd_name/rootfs bs=1024 count=12992
sync
reboot
```

> **High risk:** rootfs is 12.75 MB and a bad write leaves the screen unable to boot. Always keep a copy of the original `mtdblock2.bin` and, if something fails, reflash it the same way. `bootlogo` and the overlay are much safer.

---

## 5. Decision summary

```text
Want to change the power-on logo?
  -> mtdblock5, 854x480 JPEG, 128 KB, make_bootlogo.sh script

Want to change backgrounds/icons only on YOUR screen?
  -> copy PNG to /overlay/upper/data/res/pic/... and reboot

Want to create a modified firmware for other screens?
  -> extract mtdblock2, edit, mksquashfs, reflash (very carefully)
```

---

## 6. Model warning

These instructions were tested on the **M750** (v853, 854x480). If you modify the **TF811**, use its own files: the panel is `R0H` instead of `RX`, resolution is also 854x480, but camera calibration and build are different. Do not mix images between models.
