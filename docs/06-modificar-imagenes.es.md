# 06 - Modificar las imagenes de la pantalla

[English](06-modify-images.md) · [Volver](../README.es.md)

**Keywords:** cambiar imagen pantalla carplay, bootlogo allwinner, mtdblock5 jpeg, wallpaper autorradio, modificar firmware tina linux, overlayfs rootfs, reemplazar logo arranque

Guia para cambiar las imagenes del firmware volcado. Hay **tres lugares** distintos, segun lo que quieras cambiar:

| Quieres cambiar… | Donde esta | Dificultad |
|---|---|---|
| El logo que sale al encender | `mtdblock5` (particion `bootlogo`) | Facil |
| Los fondos/iconos de la interfaz | `/data/res/pic/` dentro del rootfs | Facil con overlay |
| El firmware base completo (para distribuirlo) | `mtdblock2` (squashfs) | Avanzado |

---

## 1. Identifica que imagen quieres cambiar

### Logo de arranque (bootlogo)

La particion `bootlogo` es **un JPEG plano de 854x480**, sin cabecera especial, rellenado con `0xFF` hasta 131072 bytes (128 KB).

Ya tienes una copia del original en la SD:

```
F:\bootlogo_original_M750.jpg
```

Abrelo en Windows para ver si es lo que quieres cambiar.

> **Si la pantalla nueva es de otro modelo:** no reutilices este JPEG a ciegas. Primero haz el volcado con el metodo del [procedimiento](02-procedure.es.md) y comprueba en `info.txt` el tamano de `mtd5` y la resolucion del panel. El formato es siempre JPEG baseline, pero las dimensiones pueden cambiar. El script `make_bootlogo.sh` acepta `W/H` como variables al inicio del archivo.

### Fondos de la interfaz

Dentro del rootfs (`mtdblock2`) estan, entre otros:

```text
data/res/pic/bin/auto_des.png      460x280  <- fondo modo "auto"
data/res/pic/bin/carplay_des.png   460x280  <- fondo CarPlay
data/res/pic/bin/hicar_des.png     460x280  <- fondo HiCar
data/res/pic/bin/carlife_des.png   460x280  <- fondo CarLife
data/res/pic/bin/elook_des.png     460x280
data/res/pic/osdlogo.png           208x48
data/res/pic/carplay_car.png       105x105
```

Hay 222 imagenes PNG en total en `data/res/pic/`.

---

## 2. Cambiar el logo de arranque

### 2.1 Generar el archivo

Con la herramienta incluida:

```bash
scripts/make_bootlogo.sh mi_logo.png bootlogo.bin
```

El script:

1. Redimensiona a **854x480** (rellenando con negro si hace falta).
2. Convierte a **JPEG baseline** (obligatorio; el bootloader no entiende progresivo).
3. Rellena con `0xFF` hasta exactamente **131072 bytes**.

Verificacion:

```bash
file bootlogo.bin
# JPEG image data ..., baseline, precision 8, 854x480, components 3
stat -c%s bootlogo.bin
# 131072
```

> Para imagenes panoramicas (p. ej. 1921x700) usa [`scripts/make_bootlogo_fill.sh`](../scripts/make_bootlogo_fill.sh): recorta el centro para llenar 854x480 en vez de anadir barras negras.

> Si tu JPEG supera los 128 KB, baja la calidad: `-q:v 4` en ffmpeg o `-quality 80` en convert.

### 2.2 Copiar a la SD

```
F:\bootlogo.bin
```

### 2.3 Escribirlo en la pantalla desde la shell root

Conectate por Tera Term a `192.168.10.1:23` y ejecuta:

```sh
# 1) Copiar a /tmp (la SD puede desmontarse durante la escritura)
cp /mnt/extsd/bootlogo.bin /tmp/bootlogo.bin

# 2) Borrar la particion bootlogo (128 KB = 131072 bytes)
dd if=/dev/zero of=/dev/mtd_name/bootlogo bs=1024 count=128

# 3) Escribir el nuevo logo
dd if=/tmp/bootlogo.bin of=/dev/mtd_name/bootlogo bs=1024 count=128
sync

# 4) Verificar: los md5 deben coincidir
md5sum /tmp/bootlogo.bin /dev/mtd_name/bootlogo
```

También puedes usar `/dev/mtdblock5` directamente si `/dev/mtd_name/bootlogo` no existe (lo crea `S00part` al arrancar).

### 2.3b Alternativa: hacerlo solo con la SD (sin teclado)

Si no puedes escribir en la terminal, usa [`files/debug1-bootlogo.sh`](../files/debug1-bootlogo.sh) en lugar de los comandos interactivos:

1. Copia `debug1-bootlogo.sh` a la raiz de la SD **con el nombre exacto `debug1`** (guarda antes tu `debug1` actual).
2. Asegurate de que `bootlogo.bin` tambien este en la raiz de la SD.
3. Apaga, inserta la SD y enciende. Espera 40-60 segundos.
4. Apaga, lleva la SD al PC y lee `F:\debug1.log`.
5. El script crea `F:\bootlogo.done` solo cuando el MD5 coincide. Borra ese archivo para volver a grabar.

Lineas esperadas en el log:

```text
[debug1] grabando bootlogo en /dev/mtd_name/bootlogo (131072 bytes)
[debug1] MD5 esperado: 5d7c...
[debug1] MD5 leido   : 5d7c...
[debug1] BOOTLOGO GRABADO Y VERIFICADO
[debug1] creado /mnt/extsd/bootlogo.done
```

### 2.4 Reiniciar y comprobar

```sh
reboot
```

Debe aparecer tu imagen en lugar del logo original.

### 2.5 Rollback

No borres `F:\bootlogo_original_M750.jpg`. Para volver al logo de fabrica:

```sh
cp /mnt/extsd/bootlogo_original_M750.jpg /tmp/orig.bin
dd if=/dev/zero of=/dev/mtd_name/bootlogo bs=1024 count=128
dd if=/tmp/orig.bin of=/dev/mtd_name/bootlogo bs=1024 count=128
sync
reboot
```

---

## 3. Cambiar fondos/iconos de la interfaz (sin regrabar el rootfs)

El firmware monta un **overlayfs**:

```text
/dev/by-name/rootfs_data  -> /overlay   (jffs2, grabable)
overlayfs:/overlay / overlay  lowerdir=/, upperdir=/overlay/upper
```

Eso significa que cualquier archivo que pongas en `/overlay/upper/...` **sustituye** al del rootfs de solo lectura. No hace falta descomprimir ni rehacer el squashfs.

Ejemplo para cambiar el fondo de CarPlay:

```sh
# En el PC: crea carplay_des.png de 460x280 y copialo a F:\

# En la pantalla, por telnet:
mkdir -p /overlay/upper/data/res/pic/bin
cp /mnt/extsd/carplay_des.png /overlay/upper/data/res/pic/bin/carplay_des.png
sync
reboot
```

Para el logo OSD:

```sh
mkdir -p /overlay/upper/data/res/pic
cp /mnt/extsd/osdlogo.png /overlay/upper/data/res/pic/osdlogo.png
sync
reboot
```

**Precauciones:**

- La particion `rootfs_data` (`/overlay`) tiene solo **320 KB**. No metas muchas imagenes grandes.
- Usa PNG con las **mismas dimensiones y formato** que el original (RGBA para los `*_des.png`).
- Algunas imagenes pueden estar cacheadas por la app; reinicia la pantalla.
- Si algo sale mal, borra el archivo del overlay y reinicia:

```sh
rm /overlay/upper/data/res/pic/bin/carplay_des.png
reboot
```

---

## 4. Modificar el firmware base (avanzado)

Si quieres **distribuir** un firmware modificado (no solo cambiar tu pantalla), tienes que rehacer el squashfs.

### 4.1 Extraer

```bash
unsquashfs -d rootfs mtdblock2.bin
```

### 4.2 Modificar

Edita los archivos dentro de `rootfs/data/res/pic/`.

### 4.3 Volver a empaquetar

El original usa **xz, block size 262144**:

```bash
mksquashfs rootfs mtdblock2_nuevo.bin \
    -comp xz -b 262144 -noappend
```

Verifica con:

```bash
unsquashfs -s mtdblock2_nuevo.bin
```

### 4.4 Escribir

```sh
dd if=/dev/zero of=/dev/mtd_name/rootfs bs=1024 count=12992
dd if=/mnt/extsd/mtdblock2_nuevo.bin of=/dev/mtd_name/rootfs bs=1024 count=12992
sync
reboot
```

> **Riesgo alto:** el rootfs es 12,75 MB y escribirlo mal deja la pantalla sin arrancar. Haz siempre una copia de `mtdblock2.bin` original y, si algo falla, regrabala por el mismo metodo. El `bootlogo` y el overlay son mucho mas seguros.

---

## 5. Resumen de decision

```text
¿Quieres cambiar el logo al encender?
  -> mtdblock5, JPEG 854x480, 128 KB, script make_bootlogo.sh

¿Quieres cambiar fondos/iconos solo en TU pantalla?
  -> copiar PNG a /overlay/upper/data/res/pic/... y reiniciar

¿Quieres crear un firmware modificado para otras pantallas?
  -> extraer mtdblock2, editar, mksquashfs, regrabar (con mucho cuidado)
```

---

## 6. Advertencia de modelo

Estas instrucciones estan probadas en la **M750** (v853, 854x480). Si vas a modificar la **TF811**, usa sus propios archivos: el panel es `R0H` en vez de `RX` y la resolucion tambien es 854x480, pero la calibracion de camara y el build son distintos. No mezcles imagenes entre modelos.
