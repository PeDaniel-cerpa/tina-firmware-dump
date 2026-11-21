# 13 - Hidden UI options found in the firmware

[Español](13-opciones-ocultas-ui.es.md) · [Back](../README.md)

**Keywords:** hidden UI options, commented XML items, model.xml setting menu, net_item.xml, config_devmng.xml flags, attrState hide, factory test overlay, Zlink hidden modes, AUX button, sys password code, adbEnable

This audit answers a concrete question: **which options are hidden in the UI?** The answer was found offline in `data/res/layout/*.xml` and `data/res/param/config_devmng.xml` from the extracted rootfs. No SD card or powered screen was needed.

There are **three different mechanisms**:

1. `<!-- ... -->` blocks around `<item>` / `<group>` / `<switch>` elements — the option still has its image, model and strings, but is not drawn.
2. `attrState="hide"` on elements that exist at runtime but start hidden.
3. Flags in `config_devmng.xml` / `device.xml` that gate a feature even when its layout exists.

---

## 1. Hidden entries in the settings menu (`model.xml`)

The `<data_model name="setting">` block contains **30 commented `<item>` lines**. Almost every target still exists as a `<data_model>` or as a real window, and the icons are still present in `data/res/pic/bin/`, so uncommenting is realistic.

| Group | Item / control | Label | Target | Notes |
|---|---|---|---|---|
| `Zlink / phone modes` | `i_zlink_mode` | `ZLINK_MODE` | setting_zlink_mode | model + 3 variants |
| `Zlink / phone modes` | `i_zlink_mode_zh` | `ZLINK_MODE` | setting_zlink_mode_zh | model |
| `Zlink / phone modes` | `i_zlink_mode_en` | `ZLINK_MODE` | setting_zlink_mode_en | model |
| `Zlink / phone modes` | `i_zlink_pre_full` | `ZLINK_PRE` | setting_zlink_pre_full | model |
| `Zlink / phone modes` | — | `CarLife / AirPlay / wireless mirror / CarLife wired / mirror` | setting_zlink_mode | 5 values (2,3,4,5,6) |
| `Camera / DVR` | `i_camformat` | `CAM_FORMAT` | setting_camformat | model; 720P/720N/1080P/1080N/1440P/1440N |
| `Camera / DVR` | `i_pixel` | `RESOLUTION` | setting_pixel | model; 4K/2.5K/1080P/720P |
| `Camera / DVR` | `i_cycle` | `CYCLE_TIME` | setting_cycle | model |
| `Camera / DVR` | `i_pre_mode` | `PRE_MODE_SW` | setting_pre_mode | model |
| `Camera / DVR` | `i_exp` | `EXPOSURE` | setting_exp | model |
| `Camera / DVR` | `i_gsensor` | `SENSITIVITY` | setting_gsensor | model |
| `Camera / DVR` | `i_lapse_time` | `LAPSE_REC` | setting_lapse_time | model |
| `Camera / DVR` | `i_parking_time` | `PARKING_TIME` | setting_parking_time | model |
| `Camera / DVR` | `i_parking` | `PARKING` | setting_parking | model |
| `Camera / DVR` | `i_power_mode` | `POWER_MODE` | setting_power_mode | model |
| `Camera / DVR` | `i_back_line` | `BACK_LINE` | backline | real window in setting_backline.xml |
| `Camera / DVR` | — | `camera2_group (left camera flip/mirror)` | setting_channel.xml | commented group, no menu item |
| `OSD / GPS` | `i_osd` | `OSD` | setting_osd | model |
| `OSD / GPS` | `i_gps_osd` | `GPS_SWITCH` | setting_gps_osd | model; needs UART1 + path fix |
| `Audio` | `i_volume` | `VOLUME (levels)` | setting_volume | model; distinct from active volume_switch |
| `Audio` | `i_rec_audio` | `AUDIO (record audio)` | setting_recaudio | model |
| `Audio` | `i_tone (duplicate)` | `KEYTONE` | setting_tone | active i_tone uses TIP_VOICE instead |
| `Audio` | `i_poweron_voice` | `POWERON_VOICE` | setting_poweron_voice | model |
| `Audio` | `i_voice_ctrl` | `VOICE_CTRL` | setting_voice_ctrl | model |
| `Audio` | `i_edog_audio` | `EDOG_AUDIO` | setting_edog_audio | model |
| `System` | `i_shutdown_time` | `SHUTDOWN_TIMER` | setting_shutdown_time | model |
| `System` | `i_time_format` | `TIME_FORMAT` | setting_time_format | model; also active in app net_item 915 |
| `System` | `i_stk_bright` | `SCREEN_BRIGHTNESS (manual)` | setting_stk_bright | model |
| `System` | `i_frequency` | `FREQUENCY (50/60 Hz)` | setting_frequency | model; no frequency_n.png |
| `System` | `i_media_save` | `MEDIA_SAVE` | setting_media_save | model missing; only string + app entry |
| `System` | `i_wifi_sw` | `WIFI_SWITCH` | setting_wifi | model |
| `System` | `i_wifi_info` | `WIFI_INFO` | setting_wifi_info | real window in setting.xml |
| `System` | — | `system password code field` | setting_sys_switch.xml | commented <edit> box |

Notes:

- `i_tone` appears twice: the active one says `TIP_VOICE`, the commented one says `KEYTONE`. Do not enable both with the same name.
- `MEDIA_SAVE` has a string and an app entry but **no** `setting_media_save` model; it would need the model to be restored too.
- `setting_wifi_info` is a real window already defined in `setting.xml`; only its menu shortcut is commented.

---

## 2. Hidden controls inside the layout windows

These are complete widgets wrapped in XML comments. They are not menu entries; they are pieces of a page that were disabled for this product variant.

| File | Commented control | What it would show |
|---|---|---|
| `home.xml` | `test_board` | `Debug overlay: G-sensor, RTC, ACC and other live values` |
| `home.xml` | `status_gpsinfo` | `eDog/GPS status: alarm type, speed limit, distance` |
| `home.xml` | `s_rec_gps / s_rec_phone / s_rec_wifi` | `Recording status icons with `attrState="hide"`` |
| `home.xml` | `btn_playback` | `Direct playback buttons on the home bar` |
| `setting_channel.xml` | `camera2_group` | `Left camera flip and mirror switches` |
| `setting_sys_switch.xml` | `setsyspsd_code` | `Password code entry field` |
| `audio_out.xml` | `aux_btn / aux_btn_nobt` | `AUX input selector` |
| `fmbluetooth.xml` | `fmdisplay_group / fmdoc_group` | `FM display and documentation panel` |
| `zlink_mode.xml` | `switch_wifi` | `WiFi on/off switch inside Zlink mode` |
| `zlink_mode.xml` | `music_group` | `Music playback controls and progress slider` |
| `zlink_mode.xml` | `ZM_PROBLEM_titel` | `Zlink problem / device-name diagnostics` |
| `zlink_mode.xml` | `mirror_qrc` | `Android mirror QR code` |
| `zlink.xml` | `zlink_audio / zlink_btn_cam` | `Volume bubble and camera shortcuts` |
| `playback.xml` | `btn_park / tabview` | `Parking files tab and file-type buttons` |

The `test_board` group in `home.xml` is the closest thing to a **factory/debug panel**: it prints live G-sensor, RTC and ACC values directly on the home screen.

---

## 3. What the mobile app sees is different

`net_item.xml` defines the settings exposed over WiFi to the companion app. Its active and commented lists do **not** match the display menu:

| Surface | Entries | Meaning |
|---|---|---|
| `Screen menu (model.xml)` | `30 entries above` | `Visible on the 854x480 display after uncommenting` |
| `App / WiFi API (net_item.xml)` | `12 active IDs: 902, 905, 906, 915, 916, 920-922, 926-929, 3028` | `Exposed to the mobile app` |
| `App / WiFi API (net_item.xml)` | `24 commented IDs: 900, 901, 903, 907-914, 917-919, 923-925, 928, 930-934` | `Hidden from the mobile app` |

For example `TIME_FORMAT` is hidden on the screen but active in the app, while `VOLUME`, `OSD`, `PARKING` and `ZLINK_MODE` are hidden in the app but some are also commented on screen.

---

## 4. Flags that hide or gate options

| Flag in `config_devmng.xml` | Value | Relationship with the UI |
|---|---|---|
| ``car_osd`` | `0` | `Camera overlay; window exists and app can set it, but no screen-menu item` |
| ``gps_info`` | `0` | `GPS info page exists (`gpsinfo.xml`) and menu item is active, but data needs UART1` |
| ``ble_enable`` | `0` | `BLE off; also depends on disabled `btlpm` node` |
| ``bFMenable`` | `0` | `FM off; `fmsend` is disabled in the DTB` |
| ``AUX_enable`` | `0` | `AUX input; its XML button is commented out` |
| ``switch_sys_psd`` | `0` | `Password prompt; code-entry field is commented out` |
| ``voice_ctl`` | `1` | `Voice control flag exists but its menu item is commented out` |
| ``boot_voice` / `touchtone`` | `1` | `Sounds on; related menu items (`POWERON_VOICE`, `KEYTONE`) are commented` |
| ``screen_filp`` | `0` | `Image flip; camera flip/mirror switches are mostly commented` |
| ``wifi_ssid_hide`` | `0` | `Hide AP name; no UI control exists, flag only` |

Additionally, `data/res/config/device.xml` contains:

```xml
adbEnable="1"        <!-- but there is no adbd binary in the rootfs -->
devGpsUart="dev/ttyS1"  <!-- missing leading slash AND UART1 disabled in DTB -->
gpsSearch="0"
radaSwitch="0"
flags="0"
```

`adbEnable=1` is misleading: ADB was already audited as unavailable in doc 07. The GPS path is the same typo reported there.

---

## 5. Safest options to enable first

1. **WIFI_INFO** — the window already exists; only uncomment `i_wifi_info`.
2. **SHUTDOWN_TIMER**, **TIME_FORMAT**, **KEYTONE**, **POWERON_VOICE** — small models, no hardware dependencies.
3. **VOLUME (levels)** and **REC_AUDIO** — useful if the active `VOLUME` switch is too limited.
4. **GPS info / GPS switch** — only after enabling `uart1` in the DTB and fixing `dev/ttyS1` → `/dev/ttyS1`.
5. **Camera-related entries** (`CAM_FORMAT`, `RESOLUTION`, `PARKING`, `LAPSE_REC`, `BACK_LINE`, camera2 group) — only if real cameras are fitted; otherwise they will be dead menu entries.

Avoid enabling everything at once. Several icons/models belong to a generic DVR product (4K, 4 cameras, parking mode, eDog radar) that this 854x480 screen does not populate.

---

## 6. How to apply

```sh
# 1. Work on a copy of the extracted rootfs
cp data/res/layout/model.xml data/res/layout/model.xml.bak

# 2. Remove only the chosen <!-- ... --> markers around the wanted <item> line
#    Keep item names unique.

# 3. Rebuild the squashfs / image.bin.lzma and flash mtdblock2
#    following docs 09 and 10 (avoid overlayfs whiteouts).
```

For a quick visual test you can try the modified `model.xml` from the overlay, but the permanent and verified path is the same rootfs rebuild already used for the custom images. The referenced PNGs are in `data/res/pic/bin/`, so no artwork needs to be created.

---

## 7. Summary

| Mechanism | Count | Reversible | Needs reflash |
|---|---:|---|---|
| Commented settings items | 30 | Yes | For permanent change |
| Commented in-page controls | 14 groups above | Yes | For permanent change |
| Commented app (`net_item.xml`) entries | 24 | Yes | For permanent change |
| `attrState="hide"` status icons | 3 | Yes | For permanent change |
| Flags gating features | 10 listed | Yes | No, if edited in overlay |
