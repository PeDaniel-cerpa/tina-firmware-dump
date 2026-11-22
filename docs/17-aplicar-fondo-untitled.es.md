# 17 - Aplicar `Untitled-1.jpg` como fondo principal

[English](17-apply-untitled-background.md) · [Volver](../README.es.md)

**Keywords:** Untitled-1.jpg, reemplazo hm_bg, entrada BGRA8888, reconstruir mtdblock2, fondo rootfs, whiteouts overlay

Este documento registra el cambio exacto realizado cuando el usuario entregó `C:\Users\pedan\Downloads\Untitled-1.jpg` como nuevo fondo de la pantalla principal.

---

## 1. Imagen de origen

```text
C:\Users\pedan\Downloads\Untitled-1.jpg
JPEG baseline 854x480, 496.410 bytes
MD5    c68f0bad9c1d541f3b117b057abf77d7
SHA256 26294fbd442d1519a539dbf829eb5b41b6b3413a2c6c3bdddf649b301620c7a4
```

Ya tiene el tamaño declarado del widget (`854 × 480`), así que no hizo falta redimensionarla. Cabe holgadamente en los 1,27 MB libres de `mtdblock2` (doc 16).

---

## 2. Qué se parcheó

Se sustituyeron **las dos copias** del fondo para que la pantalla y el cargador de recursos empaquetados coincidan:

| Destino | Antes | Después |
|---|---|---:|
| `data/res/pic/bin/hm_bg.jpg` | 140.795 bytes | 496.410 bytes |
| Entrada `hm_bg.jpg` dentro de `image.bin` | 1.639.680 B BGRA | mismo tamaño, píxeles nuevos |
| `data/res/pic/image.bin.lzma` | 590.593 bytes | 975.348 bytes |

La entrada empaquetada conserva su cabecera:

```text
descriptor = 0x1e035605   (formato 5, 854x480)
data_size  = 1.639.680    = 854 * 480 * 4
```

Solo cambiaron los 1.639.680 bytes de píxeles BGRA8888. El resto de entradas de `image.bin` es idéntico byte a byte, y las otras 8 imágenes personalizadas (`hm_auto_icon`, `hm_hicar_icon`, `hm_gps_icon_0..5`) no se tocaron.

El reemplazo se hizo con [`scripts/replace_packed_image.py`](../scripts/replace_packed_image.py): decodifica el JPEG a RGBA, intercambia R/B para obtener BGRA y verifica las dimensiones contra el descriptor de la entrada.

---

## 3. Rootfs reconstruido

```sh
mksquashfs m750root_untitled mtdblock2_untitled.bin \
    -noappend -all-root -comp xz -b 262144
truncate -s 13303808 mtdblock2_untitled.bin
# rellenar desde el tamaño del squashfs (12.949.476) hasta el final con 0xFF
```

| Campo | Valor |
|---|---|
| Tamaño de partición | 13.303.808 bytes |
| Tamaño squashfs | 12.949.476 bytes |
| Espacio libre restante | 354.332 bytes |
| MD5 | `a07151afca25933809575fe0bf96cc90` |
| SHA256 | `c967c7f04c007e3f5d72aee6fbd0514e0af32c0e271e24ceb10abd659d54f87d` |

Dentro del squashfs:

```text
data/res/pic/bin/hm_bg.jpg    MD5 c68f0bad9c1d541f3b117b057abf77d7
data/res/pic/image.bin.lzma   MD5 7dc5a5d46047897ed6c65299ed061630
```

---

## 4. Archivos entregados

Se creó una carpeta lista para copiar en el lado Windows:

```text
C:\Users\pedan\Downloads\Firmware_Hunk_Untitled_BG\
    mtdblock2_custom.bin
    debug1-flash-bg
    debug1-fix-whiteouts
    hm_bg.jpg
    README.txt
```

[`files/debug1-flash-untitled-bg.sh`](../files/debug1-flash-untitled-bg.sh) es una variante del script de grabación con:

```text
FLAG=/mnt/extsd/rootfs_bg.done
EXPECTED=a07151afca25933809575fe0bf96cc90
```

Usa un **flag nuevo** (`rootfs_bg.done`), así que el `rootfs_custom.done` existente no bloquea volver a grabar. Conserva el backup `mtdblock2_original_backup.bin` ya existente.

---

## 5. Pasos de grabación (resumen)

1. Copia `mtdblock2_custom.bin` y `debug1-flash-bg` a la raíz de la SD; renombra el segundo a `debug1` (sin extensión).
2. Enciende con la SD, espera 30–40 s y apaga. Revisa `debug1.log`: debe aparecer `ROOTFS GRABADO Y VERIFICADO` y `rootfs_bg.done`.
3. Sustituye `debug1` de la SD por `debug1-fix-whiteouts`; arranca una vez con la SD, espera 20–30 s y apaga. Esto borra los whiteouts creados en el paso 2.
4. Retira la SD y arranca normalmente. El fondo nuevo queda permanente.

Las docs 09-10 explican en detalle la reconstrucción del squashfs y los whiteouts de overlayfs.

---

## 6. Verificación esperada en el dispositivo

El `debug1.log` del paso 3 debe contener:

```text
[debug1] hm_bg.jpg visible: c68f0bad9c1d541f3b117b057abf77d7
[debug1] image.bin.lzma visible: 7dc5a5d46047897ed6c65299ed061630
```

Si aparecen esos MD5, tanto el JPEG suelto como el recurso empaquetado vienen del rootfs nuevo y la SD ya no es necesaria.
