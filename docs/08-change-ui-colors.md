# 08 - Changing the menu colours (green to red)

[Español](08-cambiar-colores-interfaz.es.md) · [Back](../README.md)

**Keywords:** change UI colour, green menu, Marlboro red, hm_bg.jpg, hm_gps_icon, image.bin.lzma, sdvcam theme, overlay symlink, debug1 colours

This guide changes the green theme of the `sdvcam` interface to **Marlboro red `210|20|20`**. It was tested on the M750 firmware, but the same method applies to the TF811 if the resource names match.

---

## 1. Where the green comes from

It is **not** only in the XML. Three layers are involved:

| Layer | Example | Effect |
|---|---|---|
| XML colours | `color="0|255|0"`, `bgColor="66|215|179"`, `color="147|220|106"` | Green text, highlights and spinners |
| Loose images | `hm_bg.jpg`, `hm_auto_icon.png`, `hm_hicar_icon.png`, `hm_gps_icon_0.png` … `hm_gps_icon_5.png` | Main background and the GPS icon sequence |
| Packed images | `data/res/pic/image.bin.lzma` → `/tmp/image.bin` | `sdvcam` decompresses this at boot and uses the raw ARGB images inside it |

The GPS icons `hm_gps_icon_0..5` are the sequence that changes with signal strength. They must all be recolored, otherwise green flashes back while the sequence animates.

---

## 2. What the SD script does

[`files/debug1-ui-red.sh`](../files/debug1-ui-red.sh) runs from `/mnt/extsd/debug1` before `sdvcam` starts:

1. Copies 10 patched XML files into `/data/res/layout/`.
2. Creates symlinks in `/data/res/pic/bin/` pointing to the recolored images on the SD.
3. Replaces `/data/res/pic/image.bin.lzma` with a symlink to the patched archive on the SD.
4. Deletes `/tmp/image.bin` so `sdvcam` re-extracts it.
5. Starts `telnetd` on port 23 as in the previous `debug1` versions.
6. Creates `/mnt/extsd/ui_red.done` only if every step succeeded.

Symlinks are used because `/overlay` is only **320 KB**. The patched `image.bin.lzma` alone is ~504 KB, so it cannot be stored in the overlay. **The SD card must stay inserted** while the screen is in use.

The script does **not** touch the bootlogo or the WiFi SSID.

---

## 3. SD layout

```text
F:\debug1                         <- debug1-ui-red.sh renamed
F:\ui_red\
    image.bin.lzma                <- patched packed images (~504 KB)
    debug1                        <- copy of the script
    xml\                          <- 10 patched XML files
        audio_out.xml
        eye_mode.xml
        fmbluetooth.xml
        hm_setting_time.xml
        home.xml
        playback.xml
        setting_time.xml
        upgrade.xml
        zlink_mode.xml
        zlink_mode_zh.xml
    pic\                          <- 26 recolored images
        hm_bg.jpg
        hm_auto_icon.png
        hm_hicar_icon.png
        hm_gps_icon_0.png ... hm_gps_icon_5.png
        answer.png
        start_play.png
        status_top_GPS_level_1..3.png
        status_top_battery_level_4.png
        status_top_wifi_connect.png
        btn_back_f.png
        calling.png
        carlife_des.png, carplay_des.png, hicar_des.png, elook_des.png
        m_carlife.png, zhijia.png, auto_des.png, wifiqrcode.png
F:\debug1_pre_ui_red              <- backup of the previous debug1
```

If `F:\ui_red.done` exists, delete it to reapply the theme.

---

## 4. Procedure

1. Power off the screen.
2. Insert the SD and power on.
3. Wait **40-60 seconds**.
4. Power off and read `F:\debug1.log`.

Expected log:

```text
[debug1] aplicando tema rojo Marlboro desde /mnt/extsd/ui_red
[debug1] XML parcheados: 10
[debug1] imagenes enlazadas: 26
[debug1] image.bin.lzma parcheado enlazado; /tmp/image.bin borrado
[debug1] TEMA ROJO APLICADO (creado /mnt/extsd/ui_red.done)
[debug1] telnetd ACTIVO en puerto 23
```

5. Power on normally. The background, icons and GPS sequence should now be red.

---

## 5. Regenerating with a different colour

The generator is [`scripts/recolor_ui.py`](../scripts/recolor_ui.py). You need the decompressed `image.bin` from the firmware dump:

```sh
unlzma -c data/res/pic/image.bin.lzma > image.bin

./scripts/recolor_ui.py \
    --res m750root/data/res \
    --image-bin image.bin \
    --out ui_red \
    --color 210,20,20
```

`--color` accepts any `R,G,B`. Pixels that are not clearly green are left untouched. The luminance is preserved and capped at the requested red channel, so bright green becomes the exact target colour while dark green stays dark.

---

## 6. Rollback

The originals are still in the read-only squashfs. To undo the overlay changes, copy this as `debug1` and boot once:

```sh
rm -f /data/res/pic/image.bin.lzma
rm -f /data/res/pic/bin/hm_bg.jpg
rm -f /data/res/pic/bin/hm_gps_icon_*.png
rm -f /data/res/pic/bin/hm_auto_icon.png
rm -f /data/res/pic/bin/hm_hicar_icon.png
rm -f /data/res/layout/audio_out.xml
rm -f /data/res/layout/eye_mode.xml
rm -f /data/res/layout/fmbluetooth.xml
rm -f /data/res/layout/hm_setting_time.xml
rm -f /data/res/layout/home.xml
rm -f /data/res/layout/playback.xml
rm -f /data/res/layout/setting_time.xml
rm -f /data/res/layout/upgrade.xml
rm -f /data/res/layout/zlink_mode.xml
rm -f /data/res/layout/zlink_mode_zh.xml
rm -f /mnt/extsd/ui_red.done
sync
```

Only delete the files listed above; deleting all files in those directories would remove unrelated user settings.

For a permanent change without the SD, rebuild `mtdblock2` with the patched resources and flash it (see doc 05).
