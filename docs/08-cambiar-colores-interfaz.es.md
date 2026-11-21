# 08 - Cambiar los colores del menú (de verde a rojo)

[English](08-change-ui-colors.md) · [Volver](../README.es.md)

**Keywords:** cambiar color interfaz, menú verde, rojo Marlboro, hm_bg.jpg, hm_gps_icon, image.bin.lzma, tema sdvcam, symlink overlay, debug1 colores

Esta guía cambia el tema verde de la interfaz `sdvcam` a **rojo Marlboro `210|20|20`**. Se probó en el firmware M750; el método sirve para el TF811 si los nombres de recursos coinciden.

---

## 1. De dónde viene el verde

**No** está solo en el XML. Hay tres capas:

| Capa | Ejemplo | Efecto |
|---|---|---|
| Colores XML | `color="0|255|0"`, `bgColor="66|215|179"`, `color="147|220|106"` | Texto, resaltes y spinners verdes |
| Imágenes sueltas | `hm_bg.jpg`, `hm_auto_icon.png`, `hm_hicar_icon.png`, `hm_gps_icon_0.png` … `hm_gps_icon_5.png` | Fondo principal y secuencia de iconos GPS |
| Imágenes empaquetadas | `data/res/pic/image.bin.lzma` → `/tmp/image.bin` | `sdvcam` lo descomprime al arrancar y usa las imágenes ARGB crudas |

Los iconos `hm_gps_icon_0..5` son la secuencia que cambia con la señal. Hay que recolorar los seis, o el verde vuelve a aparecer durante la animación.

---

## 2. Qué hace el script de la SD

[`files/debug1-ui-red.sh`](../files/debug1-ui-red.sh) se ejecuta desde `/mnt/extsd/debug1`, antes de que arranque `sdvcam`:

1. Copia 10 XML parcheados a `/data/res/layout/`.
2. Crea enlaces simbólicos en `/data/res/pic/bin/` hacia las imágenes recoloreadas de la SD.
3. Sustituye `/data/res/pic/image.bin.lzma` por un enlace al paquete parcheado de la SD.
4. Borra `/tmp/image.bin` para que `sdvcam` lo vuelva a extraer.
5. Arranca `telnetd` en el puerto 23, igual que las versiones anteriores de `debug1`.
6. Crea `/mnt/extsd/ui_red.done` solo si todos los pasos funcionaron.

Se usan enlaces simbólicos porque `/overlay` tiene solo **320 KB**. El `image.bin.lzma` parcheado ocupa ~504 KB, así que no cabe en el overlay. **La SD debe quedar insertada** mientras se use la pantalla.

El script **no** toca el bootlogo ni el SSID WiFi.

---

## 3. Estructura en la SD

```text
F:\debug1                         <- debug1-ui-red.sh renombrado
F:\ui_red\
    image.bin.lzma                <- paquete parcheado (~504 KB)
    debug1                        <- copia del script
    xml\                          <- 10 XML parcheados
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
    pic\                          <- 26 imágenes recoloreadas
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
F:\debug1_pre_ui_red              <- copia del debug1 anterior
```

Si `F:\ui_red.done` existe, bórralo para volver a aplicar el tema.

---

## 4. Procedimiento

1. Apaga la pantalla.
2. Inserta la SD y enciende.
3. Espera **40-60 segundos**.
4. Apaga y lee `F:\debug1.log`.

Log esperado:

```text
[debug1] aplicando tema rojo Marlboro desde /mnt/extsd/ui_red
[debug1] XML parcheados: 10
[debug1] imagenes enlazadas: 26
[debug1] image.bin.lzma parcheado enlazado; /tmp/image.bin borrado
[debug1] TEMA ROJO APLICADO (creado /mnt/extsd/ui_red.done)
[debug1] telnetd ACTIVO en puerto 23
```

5. Enciende normalmente. El fondo, los iconos y la secuencia GPS deben salir rojos.

---

## 5. Regenerar con otro color

El generador es [`scripts/recolor_ui.py`](../scripts/recolor_ui.py). Necesitas el `image.bin` descomprimido del volcado:

```sh
unlzma -c data/res/pic/image.bin.lzma > image.bin

./scripts/recolor_ui.py \
    --res m750root/data/res \
    --image-bin image.bin \
    --out ui_red \
    --color 210,20,20
```

`--color` acepta cualquier `R,G,B`. Los píxeles que no son claramente verdes quedan intactos. Se conserva la luminancia y se limita al canal rojo pedido, así que el verde intenso se convierte en el color exacto y el verde oscuro se queda oscuro.

---

## 6. Volver atrás

Los originales siguen en el squashfs de solo lectura. Para deshacer los cambios del overlay, copia esto como `debug1` y arranca una vez:

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

Borra solo los archivos listados; borrar todos los de esos directorios eliminaría ajustes de usuario ajenos.

Para un cambio permanente sin la SD, reconstruye `mtdblock2` con los recursos parcheados y grábalo (ver doc 05).
