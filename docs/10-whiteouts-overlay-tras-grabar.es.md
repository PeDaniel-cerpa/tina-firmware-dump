# 10 - Sin imágenes tras grabar el rootfs (whiteouts del overlay)

[English](10-overlay-whiteouts-after-flash.md) · [Volver](../README.es.md)

**Keywords:** whiteout overlayfs, /overlay/upper, sin imágenes, sdvcam sin iconos, grabar mtdblock2, image.bin.lzma oculto, rootfs Tina Linux

Este documento recoge un fallo real ocurrido después de integrar imágenes personalizadas en `mtdblock2` (doc 09). El sistema arrancaba normalmente pero la interfaz **no mostraba ninguna imagen**. Se confirmó resuelto en la pantalla M750 eliminando los whiteouts del overlay.

---

## 1. Síntoma

- El script de grabación terminó bien e imprimió `ROOTFS GRABADO Y VERIFICADO`.
- Existía `F:\rootfs_custom.done`.
- Al quitar la SD y encender, Linux arrancaba y aparecía el bootlogo.
- La interfaz `sdvcam` iniciaba pero faltaban todos los iconos y el fondo.

La primera sospecha fue un paquete de imágenes corrupto, pero estaba íntegro. La demora que hizo apagar la pantalla ocurrió **después** de que la grabación terminara, así que el rootfs estaba bien.

---

## 2. Causa

`/data` no es un directorio normal. Parte del squashfs (`lowerdir`) se expone mediante overlayfs:

```text
/dev/by-name/rootfs_data  /overlay          jffs2  rw   (320 KB)
overlayfs:/overlay        /                 overlayfs  rw
  lowerdir=/ (squashfs)
  upperdir=/overlay/upper
  workdir=/overlay/workdir
```

El script de grabación hizo esto antes de escribir el rootfs nuevo:

```sh
rm -f /data/res/pic/image.bin.lzma
rm -f /data/res/pic/bin/hm_bg.jpg
...
```

En overlayfs, borrar un archivo que solo existe en la capa inferior **no** borra ese archivo: crea un **whiteout** (un dispositivo de carácter `0:0`) en `/overlay/upper`. Tras grabar el rootfs nuevo, esos whiteouts seguían ahí y seguían ocultando los archivos recién instalados.

Es decir: las imágenes estaban dentro del squashfs nuevo, pero invisibles en `/data/...`.

---

## 3. Por qué no sirve copiar archivos a `/data`

Un whiteout gana sobre un archivo inferior. Copiar a `/data/...` no crea el archivo upper mientras el whiteout siga existiendo: la ruta sigue resolviéndose como «borrada». Además, el overlay tiene solo **320 KB** libres, así que no cabe copiar el `image.bin.lzma` de ~474 KB.

Hay que borrar el whiteout del sistema de archivos upper real:

```sh
rm -f /overlay/upper/data/res/pic/image.bin.lzma
rm -f /overlay/upper/data/res/pic/bin/hm_bg.jpg
...
```

Fíjate en la ruta: `/overlay/upper/...`, no `/data/...`.

---

## 4. La solución aplicada

Se copió [`files/debug1-fix-overlay-whiteouts.sh`](../files/debug1-fix-overlay-whiteouts.sh) a la SD como `debug1`:

```text
F:\debug1                 MD5 934ec0807dd824fe83593dc17cf1abbd
F:\rootfs_custom.done     SI (rootfs ya grabado)
```

Procedimiento:

1. Apaga la pantalla, inserta la SD y enciende.
2. Espera solo **20-30 s** (no graba nada, solo limpia el overlay).
3. Apaga y lee `F:\debug1.log`.
4. Retira la SD y enciende.

El script borra únicamente estas 10 entradas del upper:

```text
data/res/pic/image.bin.lzma
data/res/pic/bin/hm_bg.jpg
data/res/pic/bin/hm_auto_icon.png
data/res/pic/bin/hm_hicar_icon.png
data/res/pic/bin/hm_gps_icon_0.png ... hm_gps_icon_5.png
```

También borra `/tmp/image.bin` para que `sdvcam` vuelva a extraer el paquete del rootfs nuevo, e imprime los MD5 de los archivos ya visibles:

```text
[debug1] image.bin.lzma visible: 53533ecef3a9084db898df5037ca9d0d
[debug1] hm_bg.jpg visible: 29c75c931c8c8e19c2dabe7a15b32171
[debug1] hm_auto_icon.png visible: 8f594a4bc3fedfe4315e9d96d8e31d45
[debug1] creado /mnt/extsd/overlay_fix.done - apaga y enciende SIN SD
```

Resultado: **confirmado funcionando**. Todas las imágenes y los colores personalizados aparecieron al arrancar sin la SD.

---

## 5. Prevención para futuras grabaciones de rootfs

Un script que grabe el rootfs no debe dejar whiteouts. Puede:

- no hacer `rm` de archivos inferiores antes de grabar, o
- limpiar `/overlay/upper/data/res/pic/...` en el mismo arranque tras escribir `mtdblock2`, o
- arrancar una vez con el script corrector (doc 09, apartado 4) antes de usar la pantalla sin SD.

El corrector es idempotente: si se ejecuta otra vez, solo informa `sin entrada upper: ...` para cada archivo y no hace daño.

---

## 6. Contexto de vuelta atrás

Si alguna vez necesitas volver al rootfs de fábrica, la partición original se guardó antes de grabar:

```text
F:\mtdblock2_original_backup.bin   MD5 43acc068c9d79de63e480970d2ff72e3
```

Cópialo sobre `F:\mtdblock2_custom.bin`, borra `F:\rootfs_custom.done`, arranca una vez con la SD y apaga/enciende. Si vuelven a faltar imágenes, aplica también este corrector de whiteouts.
