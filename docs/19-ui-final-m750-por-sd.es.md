# 19 - UI final de la M750 por SD con `debug1` (sin UART) y fix de `zlink`

[English](19-m750-sd-only-debug.md) · [Volver](../README.es.md)

**Keywords:** `debug1`, SD FAT32 superfloppy, `mtdblock2`, `mtdblock5`, bootlogo, `zlink.xml`, widget de brillo/home, sin UART, M750

Este documento cierra el caso de la M750. Después de recuperar el NOR con el volcado de fábrica ([doc 18](18-recuperacion-m750-por-uart.es.md)), se grabó el diseño anterior al widget de presión de neumáticos y luego se corrigió el espacio en blanco superior del widget que contiene los botones de brillo y home. **Todo se hizo arrancando solo con la SD**: el script `debug1` se ejecuta como root desde `/mnt/extsd` al arrancar y escribe directamente en MTD. No hicieron falta comandos `sf` de U-Boot.

---

## 1. Estado de partida

La placa ya arrancaba con el dump stock de 16 MiB (MD5 `8c0abbd6e0f327e5d9ab38146a90f5ca`). Se conservó:

- `mtdblock2` (rootfs) con la UI personalizada **layout2**: BG nueva, 8 iconos, fuente AERUNO, reloj grande centrado y FRO/BAC arriba, **sin barra TPMS**.
- `mtdblock5` (bootlogo) con el logo que funcionaba: MD5 `d105460a6164c8d5e861f337b429f873`.

Layout MTD relevante (erase block `0x10000`):

| MTD | Offset | Tamaño | Uso |
|---|---:|---:|---|
| `mtdblock2` | `0x290000` | `0xcb0000` (13 MB) | rootfs / UI |
| `mtdblock5` | `0xfb0000` | `0x20000` (128 KB) | bootlogo |

---

## 2. Archivos usados

| Archivo en la SD | MD5 | Función |
|---|---|---|
| `debug1` | `7ebe0b0e843747972fa101554ee89bc0` | Script final que graba rootfs y bootlogo |
| `busybox_net` | `10ac2a1c34b0b02f2d0ce7a4420ade5c` | BusyBox estático con `telnetd` para debug |
| `mtdblock2_custom.bin` | `2a3fb11dfe526948908e2a5e9148f855` | **Final** = layout2 + fix `zlink.xml`, sin TPMS |
| `bootlogo.bin` | `d105460a6164c8d5e861f337b429f873` | Bootlogo «Proyecto nuevo» |
| `dump_completo.bin` | `8c0abbd6e0f327e5d9ab38146a90f5ca` | Respaldo del NOR |

El rootfs intermediate `layout2` (MD5 `fa89ce4593b1b67fee2d3e8d381ac340`) quedó como referencia. El script exacto está en [`examples/debug1-M750-sd-only.sh`](../examples/debug1-M750-sd-only.sh).

---

## 3. Cambio exacto en `zlink.xml`

El widget de brillo/home tenía un hueco arriba porque el grupo empezaba en `top="180"` con `height="300"` y los botones estaban desplazados 60 px hacia abajo. La corrección (idéntica a `mtdblock2_final.bin`) es:

```diff
--- layout2/data/res/layout/zlink.xml
+++ final/data/res/layout/zlink.xml
@@ -233,9 +233,9 @@
 			bgColor="128|128|128"
 			radius="15"
 			left="754"
-			top="180"
+			top="240"
 			width="100"
-			height="300">
+			height="240">
@@ -247,31 +247,31 @@
 			<imgbtn name="zlink_btn_drag_vol"      top="60"  -> top="0" />
 			<imgbtn name="zlink_btn_drag_bright"   top="140" -> top="80" />
 			<imgbtn name="zlink_btn_drag_exit"     top="220" -> top="160" />
 			<imgbtn name="zlink_btn_drag_bright1"  top="60"  -> top="0" />
 			<imgbtn name="zlink_btn_drag_exit1"    top="140" -> top="80" />
```

Es el **único** archivo que difiere entre `layout2` y `final` (573 archivos en cada squashfs). No se agregó ninguna barra TPMS.

---

## 4. Procedimiento con SD

La SD debe ser **FAT32 superfloppy** (sin MBR), porque el firmware monta `/dev/mmcblk0`, no `/dev/mmcblk0p1`. Se puede grabar una imagen `.img` con `scripts/write_sd_windows.ps1` o copiar los cinco archivos a la raíz.

1. Apagar la M750.
2. Poner la SD con los archivos de la sección 2.
3. Encender y esperar **40-60 s**. `S01app` ejecuta `/mnt/extsd/debug1` como root.
4. El script:
   - guarda `mtdblock2_original_backup.bin` y `bootlogo_original_backup.bin` si no existen;
   - verifica MD5 desde la SD y desde `/tmp` antes de escribir;
   - limpia whiteouts en `/overlay/upper` (`home_main.xml`, `zlink.xml`, `tyre_warn.xml`, `config_devmng.xml` e imágenes);
   - hace `dd` a `/dev/mtdblock2` y vuelve a leer para verificar;
   - crea los flags `rootfs_final.done` / `bootlogo.done`;
   - levanta `telnetd` en el puerto 23 para debug.
5. Apagar, **sacar la SD** y volver a encender sin SD.

> Si el flag `bootlogo.done` ya existe de una grabación anterior, el script omite el bootlogo. Borrarlo solo si se quiere regrabar el logo.

---

## 5. Verificación

Sacar la SD y abrir `debug1.log`. En la actualización del `zlink` debe aparecer:

```text
[debug1] rootfs MD5 SD      : 2a3fb11dfe526948908e2a5e9148f855
[debug1] rootfs MD5 leido  : 2a3fb11dfe526948908e2a5e9148f855
[debug1] ROOTFS FINAL (zlink sin hueco) GRABADO Y VERIFICADO
[debug1] creado /mnt/extsd/rootfs_final.done
[debug1] bootlogo.done existe -> bootlogo ya grabado, omito
[debug1] telnetd ACTIVO en puerto 23 (debug)
[debug1] Si todo salio bien: APAGA, SACA LA SD Y ENCIENDE SIN SD
```

Resultado visual: bootlogo «Proyecto nuevo», home con BG nueva, 8 iconos, AERUNO, reloj grande centrado, FRO/BAC arriba, widget de brillo/home sin hueco superior y **sin widget TPMS**.

---

## 6. Reintentos

- Para repetir el rootfs: borrar `rootfs_final.done`.
- Para repetir el bootlogo: borrar `bootlogo.done`.
- Los backups en la SD permiten volver al estado anterior con `dd if=mtdblock2_original_backup.bin of=/dev/mtdblock2` y equivalente para `mtdblock5`.

Desde WSL se copió todo a la unidad `F:` de Windows invocando `powershell.exe` y se verificó cada MD5 con `Get-FileHash -Algorithm MD5`; la SD aparece como FAT32 de ~128 MB con etiqueta `FIRMWARE`.
