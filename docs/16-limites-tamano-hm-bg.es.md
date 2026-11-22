# 16 - Tamaño máximo de `hm_bg`

[English](16-hm-bg-size-limits.md) · [Volver](../README.es.md)

**Keywords:** tamaño máximo hm_bg.jpg, image.bin.lzma BGRA8888, fondo 854x480, espacio libre mtdblock2, overlay 320 KB, tmpfs image.bin, fondo sdvcam

**No hay un único límite fijo en bytes** para `hm_bg`. Existe en dos sitios con dos restricciones distintas, y suelen confundirse:

| Copia | Ruta | Tamaño actual | Límite real |
|---|---|---:|---|
| JPEG suelto | `/data/res/pic/bin/hm_bg.jpg` | 140.795 bytes | Espacio libre en `mtdblock2` (~1,27 MB) o 320 KB si se instala en `/overlay` |
| Imagen empaquetada | dentro de `/data/res/pic/image.bin.lzma` → `/tmp/image.bin` | 1.639.680 bytes | `854 × 480 × 4` BGRA8888, fijado por su cabecera para este layout |

---

## 1. El JPEG suelto: el archivo que se sustituye

`home_main.xml` declara el fondo como:

```xml
<image name="hm_bg" left="0" top="0" picture="hm_bg.jpg"/>
```

La pantalla es `854 × 480` (`device.xml`), así que el JPEG debe seguir siendo **854×480**. Hacerlo más grande no da más detalle visible: la UI lo escala/recorta al mismo widget.

Archivo actual:

```text
JPEG baseline 854x480, 140.795 bytes
```

### Instalación permanente (recomendada, dentro de `mtdblock2`)

Tamaños de la partición y del squashfs personalizado:

```text
partición mtdblock2 : 13.303.808 bytes
squashfs personalizado: 12.033.501 bytes
libre               :  1.270.307 bytes (~1,21 MiB)
```

Como un JPEG ya está comprimido, squashfs apenas lo reduce. Un `hm_bg.jpg` suelto puede crecer de ~141 KB a **unos 1,1–1,2 MB** antes de agotar la partición. Deja margen para metadatos del squashfs.

### Instalación por overlay / SD (método antiguo de la doc 08)

`/overlay` solo tiene **320 KB** libres. El archivo actual de 140 KB cabe, pero un fondo mucho mayor no. Por eso la doc 08 usa enlaces simbólicos desde la SD. Para una imagen más grande, incorpora el archivo al rootfs.

---

## 2. La entrada empaquetada: píxeles crudos, no bytes JPEG

`sdvcam` descomprime `image.bin.lzma` en `/tmp/image.bin` al arrancar. Totales del archivo:

```text
image.bin.lzma (comprimido)   :   590.593 bytes
image.bin (descomprimido)     : 13.388.944 bytes
```

Cada entrada tiene:

```text
64 bytes  nombre
12 bytes  cabecera: u32 flags=1, u32 descriptor, u32 data_size
N bytes   píxeles BGRA8888 crudos
```

Para `hm_bg.jpg` dentro del archivo:

```text
descriptor = 0x1e035605   (formato 5, 854x480)
data_size  = 1.639.680    = 854 * 480 * 4
```

Por tanto, la copia **empaquetada** ocupa siempre 1,6 MB de píxeles crudos; su tamaño no sigue el tamaño del JPEG. Cambiar sus dimensiones exige reescribir `descriptor` y `data_size` y desplazar todas las entradas posteriores, además de recomprimir. No aporta nada para esta UI: el widget sigue siendo 854×480.

---

## 3. La RAM no es el cuello de botella

El DTB declara:

```dts
memory@40000000 {
    reg = <0x00 0x40000000 0x00 0x20000000>;  /* 512 MiB */
};
```

`/tmp` es un tmpfs montado por `/etc/preinit`. Con 512 MiB de RAM su tamaño por defecto ronda los 256 MiB, muy por encima de los 12,8 MiB del archivo descomprimido. Un JPEG mayor se decodifica en un framebuffer de unos `854*480*4 ≈ 1,6 MB`; incluso varios son asumibles.

---

## 4. Respuesta práctica

| Pregunta | Respuesta |
|---|---|
| ¿Debe ser 854×480? | **Sí**, es el tamaño declarado del widget y de la pantalla |
| ¿Puedo subir calidad/tamaño del JPEG? | **Sí**, hasta ~1,1–1,2 MB en el rootfs permanente |
| ¿Puedo hacerlo mayor que 854×480? | No sirve: se escalará y solo desperdicia RAM/almacenamiento |
| ¿Puedo copiarlo a `/data`? | Solo si caben ≤320 KB en el overlay; si no, reconstruye `mtdblock2` |
| ¿Limita la entrada empaquetada de 1,6 MB al JPEG? | No, son píxeles crudos a los mismos 854×480 |
| ¿Es esto el bootlogo? | No. El bootlogo es `mtdblock5`, 131.072 bytes, rellenado con `0xFF` |

**Recomendación:** mantén 854×480, exporta el JPEG con calidad 85–95 (normalmente 150–400 KB) y grábalo en `mtdblock2` con las docs 09-10. No hace falta tocar `image.bin` si solo cambias el JPEG suelto.

---

## 5. Verificar tu archivo

```sh
file data/res/pic/bin/hm_bg.jpg
stat -c '%s bytes' data/res/pic/bin/hm_bg.jpg
# tras reempaquetar, comprobar que queda espacio:
unsquashfs -s mtdblock2_custom.bin | grep 'Filesystem size'
# debe permanecer por debajo de 13.303.808 bytes
```

Si el tamaño del squashfs se acerca al de la partición, baja la calidad del JPEG o elimina recursos sin uso antes de grabar.
