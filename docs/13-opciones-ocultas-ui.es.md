# 13 - Opciones ocultas de la interfaz en el firmware

[English](13-hidden-ui-options.md) · [Volver](../README.es.md)

**Keywords:** opciones ocultas UI, items XML comentados, menú setting model.xml, net_item.xml, flags config_devmng.xml, attrState hide, panel factory test, modos Zlink ocultos, botón AUX, código sys password, adbEnable

Esta auditoría responde a una pregunta concreta: **¿qué opciones están ocultas en la interfaz?** La respuesta se encontró offline en `data/res/layout/*.xml` y `data/res/param/config_devmng.xml` del rootfs extraído. No hicieron falta la SD ni la pantalla encendida.

Hay **tres mecanismos distintos**:

1. Bloques `<!-- ... -->` alrededor de `<item>` / `<group>` / `<switch>`: la opción conserva su imagen, modelo y textos, pero no se dibuja.
2. `attrState="hide"` en elementos que existen en ejecución pero arrancan ocultos.
3. Flags en `config_devmng.xml` / `device.xml` que bloquean una función aunque su layout exista.

---

## 1. Entradas ocultas en el menú de ajustes (`model.xml`)

El bloque `<data_model name="setting">` contiene **30 líneas `<item>` comentadas**. Casi todos los destinos siguen existiendo como `<data_model>` o como ventana real, y los iconos siguen en `data/res/pic/bin/`, así que descomentar es viable.

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

Notas:

- `i_tone` aparece dos veces: el activo dice `TIP_VOICE` y el comentado dice `KEYTONE`. No activar ambos con el mismo nombre.
- `MEDIA_SAVE` tiene texto y entrada en la app, pero **no** existe el modelo `setting_media_save`; habría que restaurarlo también.
- `setting_wifi_info` es una ventana real ya definida en `setting.xml`; solo está comentado su acceso desde el menú.

---

## 2. Controles ocultos dentro de las ventanas

Son widgets completos envueltos en comentarios XML. No son entradas de menú, sino partes de una página desactivadas para esta variante de producto.

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

El grupo `test_board` de `home.xml` es lo más parecido a un **panel de fábrica/depuración**: muestra en pantalla valores en vivo de G-sensor, RTC y ACC.

---

## 3. Lo que ve la app es distinto

`net_item.xml` define los ajustes expuestos por WiFi a la app del móvil. Sus listas activas y comentadas **no** coinciden con el menú de la pantalla:

| Surface | Entries | Meaning |
|---|---|---|
| `Screen menu (model.xml)` | `30 entries above` | `Visible on the 854x480 display after uncommenting` |
| `App / WiFi API (net_item.xml)` | `12 active IDs: 902, 905, 906, 915, 916, 920-922, 926-929, 3028` | `Exposed to the mobile app` |
| `App / WiFi API (net_item.xml)` | `24 commented IDs: 900, 901, 903, 907-914, 917-919, 923-925, 928, 930-934` | `Hidden from the mobile app` |

Por ejemplo `TIME_FORMAT` está oculto en pantalla pero activo en la app, mientras que `VOLUME`, `OSD`, `PARKING` y `ZLINK_MODE` están ocultos en la app y algunos también comentados en pantalla.

---

## 4. Flags que ocultan o bloquean opciones

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

Además, `data/res/config/device.xml` contiene:

```xml
adbEnable="1"        <!-- pero no hay binario adbd en el rootfs -->
devGpsUart="dev/ttyS1"  <!-- sin la barra inicial Y UART1 desactivado en el DTB -->
gpsSearch="0"
radaSwitch="0"
flags="0"
```

`adbEnable=1` es engañoso: ADB ya se auditó como no disponible en la doc 07. La ruta GPS es el mismo error de sintaxis descrito allí.

---

## 5. Opciones más seguras para activar primero

1. **WIFI_INFO**: la ventana ya existe; basta descomentar `i_wifi_info`.
2. **SHUTDOWN_TIMER**, **TIME_FORMAT**, **KEYTONE**, **POWERON_VOICE**: modelos pequeños, sin dependencias de hardware.
3. **VOLUME (niveles)** y **REC_AUDIO**: útiles si el interruptor `VOLUME` activo se queda corto.
4. **GPS info / GPS switch**: solo tras activar `uart1` en el DTB y corregir `dev/ttyS1` → `/dev/ttyS1`.
5. **Entradas de cámara** (`CAM_FORMAT`, `RESOLUTION`, `PARKING`, `LAPSE_REC`, `BACK_LINE`, grupo camera2): solo si hay cámaras reales; si no, serán opciones muertas.

Evita activar todo de una vez. Varios iconos/modelos pertenecen a un producto DVR genérico (4K, 4 cámaras, modo parking, radar eDog) que esta pantalla de 854x480 no monta.

---

## 6. Cómo aplicarlo

```sh
# 1. Trabajar sobre una copia del rootfs extraído
cp data/res/layout/model.xml data/res/layout/model.xml.bak

# 2. Quitar solo los marcadores <!-- ... --> alrededor del <item> elegido
#    Mantener nombres de item únicos.

# 3. Reconstruir squashfs / image.bin.lzma y grabar mtdblock2
#    siguiendo las docs 09 y 10 (evitar whiteouts de overlayfs).
```

Para una prueba visual rápida puedes probar el `model.xml` modificado desde el overlay, pero la vía permanente y verificada es la misma reconstrucción del rootfs usada para las imágenes personalizadas. Los PNG referenciados están en `data/res/pic/bin/`, así que no hay que crear artwork.

---

## 7. Resumen

| Mecanismo | Cantidad | Reversible | Requiere regrabar |
|---|---:|---|---|
| Items de ajustes comentados | 30 | Sí | Para cambio permanente |
| Controles dentro de páginas comentados | 14 grupos | Sí | Para cambio permanente |
| Entradas de la app comentadas (`net_item.xml`) | 24 | Sí | Para cambio permanente |
| Iconos de estado con `attrState="hide"` | 3 | Sí | Para cambio permanente |
| Flags que bloquean funciones | 10 listados | Sí | No, si se editan en overlay |
