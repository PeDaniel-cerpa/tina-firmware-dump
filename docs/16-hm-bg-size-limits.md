# 16 - Maximum size of `hm_bg`

[Español](16-limites-tamano-hm-bg.es.md) · [Back](../README.md)

**Keywords:** hm_bg.jpg size limit, image.bin.lzma BGRA8888, 854x480 background, mtdblock2 free space, overlay 320 KB, tmpfs image.bin, sdvcam background

There is **no single hardcoded byte limit** for `hm_bg`. It exists in two places with two different constraints, and they are often confused:

| Copy | Path | Current size | Real limit |
|---|---|---:|---|
| Loose JPEG | `/data/res/pic/bin/hm_bg.jpg` | 140,795 bytes | Free space in `mtdblock2` (~1.27 MB) or 320 KB if installed in `/overlay` |
| Packed raw image | inside `/data/res/pic/image.bin.lzma` → `/tmp/image.bin` | 1,639,680 bytes | `854 × 480 × 4` BGRA8888, fixed by its header for this layout |

---

## 1. Loose JPEG: the file you actually replace

`home_main.xml` declares the background as:

```xml
<image name="hm_bg" left="0" top="0" picture="hm_bg.jpg"/>
```

The screen is `854 × 480` (`device.xml`), so the JPEG should stay **854×480**. Making it larger does not give more visible detail: the UI scales/crops it to the same widget.

Current file:

```text
854x480 baseline JPEG, 140,795 bytes
```

### Permanent install (recommended, baked into `mtdblock2`)

The partition and current custom squashfs sizes are:

```text
mtdblock2 partition : 13,303,808 bytes
custom squashfs     : 12,033,501 bytes
free                :  1,270,307 bytes (~1.21 MiB)
```

Because a JPEG is already compressed, squashfs will barely shrink it. So a loose `hm_bg.jpg` can realistically grow from ~141 KB to **about 1.1–1.2 MB** before you run out of partition space. Leave a margin for the squashfs metadata.

### Overlay / SD install (old doc 08 method)

`/overlay` only has **320 KB** free. The current 140 KB file fits, but a much larger background will not. That is why doc 08 uses symlinks from the SD. For a bigger image, bake it into the rootfs instead.

---

## 2. Packed entry: raw pixels, not JPEG bytes

`sdvcam` decompresses `image.bin.lzma` into `/tmp/image.bin` at boot. Archive totals:

```text
image.bin.lzma (compressed)   :   590,593 bytes
image.bin (uncompressed)      : 13,388,944 bytes
```

Each entry has:

```text
64 bytes  name
12 bytes  header: u32 flags=1, u32 descriptor, u32 data_size
N bytes   raw BGRA8888 pixels
```

For `hm_bg.jpg` inside the archive:

```text
descriptor = 0x1e035605   (format 5, 854x480)
data_size  = 1,639,680    = 854 * 480 * 4
```

So the **packed** copy is always 1.6 MB of raw pixels; its size does not follow the JPEG file size. Changing its dimensions requires rewriting `descriptor` and `data_size` and shifting every later entry, then recompressing. There is no benefit for this UI: the widget is still 854×480.

---

## 3. RAM is not the bottleneck

The DTB declares:

```dts
memory@40000000 {
    reg = <0x00 0x40000000 0x00 0x20000000>;  /* 512 MiB */
};
```

`/tmp` is a tmpfs mounted by `/etc/preinit`. With 512 MiB RAM its default size is roughly 256 MiB, far above the 12.8 MiB uncompressed archive. A bigger JPEG is decoded into a framebuffer of about `854*480*4 ≈ 1.6 MB`; even several of those are affordable.

---

## 4. Practical answer

| Question | Answer |
|---|---|
| Must it be 854×480? | **Yes**, that is the declared widget/screen size |
| Can I raise JPEG quality / file size? | **Yes**, up to ~1.1–1.2 MB in the permanent rootfs |
| Can I make it larger than 854×480? | Not useful; it will be scaled, and RAM/storage are wasted |
| Can I just drop it in `/data`? | Only if ≤320 KB free in overlay; otherwise rebuild `mtdblock2` |
| Does the 1.6 MB packed entry limit the JPEG? | No, it is decoded raw pixels at the same 854×480 |
| Is this the bootlogo? | No. Bootlogo is `mtdblock5`, 131,072 bytes, padded with `0xFF` |

**Recommendation:** keep 854×480, export the JPEG at quality 85–95 (typically 150–400 KB), and bake it into `mtdblock2` with docs 09-10. There is no need to touch `image.bin` if you only change the loose JPEG.

---

## 5. Verifying your own file

```sh
file data/res/pic/bin/hm_bg.jpg
stat -c '%s bytes' data/res/pic/bin/hm_bg.jpg
# after repacking, confirm there is still room:
unsquashfs -s mtdblock2_custom.bin | grep 'Filesystem size'
# it must stay below 13,303,808 bytes
```

If the squashfs size approaches the partition size, reduce JPEG quality or remove unused resources before flashing.
