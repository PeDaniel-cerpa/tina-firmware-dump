# 09 - Hacer permanentes las imágenes personalizadas

[English](09-permanent-custom-images.md) · [Volver](../README.es.md)

**Keywords:** rootfs permanente, mtdblock2, squashfs, hm_bg personalizado, image.bin.lzma, grabar rootfs desde SD, sin dependencia de SD

Las imágenes instaladas con el método de la doc 08 siguen dependiendo de la SD porque `image.bin.lzma` es un enlace a la tarjeta. Esta guía integra esas imágenes en un `mtdblock2` reconstruido, para que sobrevivan sin SD y tras un reset del overlay.

---

## 1. Qué se construyó

Partiendo del rootfs extraído del `mtdblock2` original:

- Se reemplazaron solo estos archivos con las versiones entregadas:
  - `data/res/pic/bin/hm_bg.jpg`
  - `data/res/pic/bin/hm_auto_icon.png`
  - `data/res/pic/bin/hm_hicar_icon.png`
  - `data/res/pic/bin/hm_gps_icon_0.png` … `hm_gps_icon_5.png`
- Se reemplazó `data/res/pic/image.bin.lzma` por una versión en la que **solo esas 9 entradas** están parcheadas; el resto del archivo es idéntico.
- Se reconstruyó el squashfs con `mksquashfs -noappend -all-root -comp xz -b 262144`.
- Se rellenó hasta el tamaño exacto de la partición `0xCB0000` (13.303.808 bytes) con `0xFF`.

Resultado:

```text
mtdblock2_custom.bin
MD5:      88a9d4a56d1f9f11e67ab1029926909b
SHA256:   28a89c0c73b06f8c05035853391cd52de8fbf31cee04fa4cabc2c35ba7573861
Tamaño:   13.303.808 bytes
```

---

## 2. Estructura en la SD

```text
F:\debug1                        <- files/debug1-flash-rootfs.sh renombrado
F:\mtdblock2_custom.bin          <- la imagen de arriba
F:\debug1_before_rootfs          <- copia del debug1 anterior
F:\mtdblock2_original_backup.bin <- creado por el script en el primer arranque
F:\rootfs_custom.done            <- creado solo tras verificar MD5
```

El script también borra los restos del overlay del método anterior basado en SD:

```text
/data/res/pic/image.bin.lzma          (enlace simbólico)
/data/res/pic/bin/hm_bg.jpg
/data/res/pic/bin/hm_auto_icon.png
/data/res/pic/bin/hm_hicar_icon.png
/data/res/pic/bin/hm_gps_icon_0..5.png
/tmp/image.bin
```

**No** toca `mtdblock5` (bootlogo) ni el SSID WiFi.

---

## 3. Procedimiento

1. Apaga la pantalla.
2. Inserta la SD y enciende.
3. Espera **60-90 segundos**. Grabar 13 MB tarda más que grabar el bootlogo.
4. Apaga y lee `F:\debug1.log`.

Log esperado:

```text
[debug1] guardando rootfs original en /mnt/extsd/mtdblock2_original_backup.bin
[debug1] MD5 SD   : 88a9d4a56d1f9f11e67ab1029926909b
[debug1] MD5 /tmp : 88a9d4a56d1f9f11e67ab1029926909b
[debug1] grabando mtdblock2 (13303808 bytes)
[debug1] MD5 leido   : 88a9d4a56d1f9f11e67ab1029926909b
[debug1] ROOTFS GRABADO Y VERIFICADO
[debug1] APAGA Y ENCIENDE para usar el rootfs nuevo
```

5. Retira la SD y enciende. Las imágenes personalizadas deben cargarse ya desde la flash.

---

## 4. Riesgos y vuelta atrás

**No cortes la alimentación durante la grabación.** Si la verificación MD5 falla, no se crea `rootfs_custom.done` y puedes repetir.

Para restaurar el rootfs de fábrica:

```text
copia F:\mtdblock2_original_backup.bin -> F:\mtdblock2_custom.bin
borra F:\rootfs_custom.done
arranca una vez con la SD
apaga y enciende
```

Después restaura el `debug1` que prefieras desde los respaldos de la SD.

### Sin imágenes después del primer arranque

Si el sistema arranca pero la interfaz no muestra imágenes, los `rm -f` sobre `/data/...` del script de grabación crearon **whiteouts** en la capa superior del overlay. Esos whiteouts ocultan los archivos que ahora están dentro del squashfs reconstruido. No se arregla copiando archivos a `/data`; hay que borrar los whiteouts de `/overlay/upper`.

Copia [`files/debug1-fix-overlay-whiteouts.sh`](../files/debug1-fix-overlay-whiteouts.sh) como `debug1`, arranca una vez con la SD, espera ~20 s, apaga, revisa `debug1.log` y enciende **sin** SD. El script borra solo los 10 whiteouts e imprime los MD5 de los archivos que quedan visibles.

---

## 5. Reconstruir con otras imágenes

```sh
# 1) descomprimir el archivo original
unlzma -c m750root/data/res/pic/image.bin.lzma > image.bin

# 2) parchear solo tus archivos dentro de image.bin (formato: nombre de
#    64 bytes, metadatos de 12 bytes, pixeles BGRA8888 crudos).
#    scripts/recolor_ui.py tiene el parser de entradas.

# 3) reemplazar los archivos sueltos y recomprimir
lzma -c image.bin > m750root/data/res/pic/image.bin.lzma

# 4) reconstruir squashfs
mksquashfs m750root mtdblock2_custom.bin \
    -noappend -all-root -comp xz -b 262144
truncate -s 13303808 mtdblock2_custom.bin
python3 - <<'PY'
p='mtdblock2_custom.bin'
b=open(p,'r+b'); b.seek(12033501); b.write(b'\xff'*(13303808-12033501)); b.close()
PY
```

El offset de relleno es el tamaño del filesystem squashfs que imprime `unsquashfs -s`; usa el valor de tu propia construcción.
