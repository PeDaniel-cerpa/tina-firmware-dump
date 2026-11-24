# 18 - Recuperación real de la M750 por UART (resuelto)

[English](18-m750-uart-recovery.md) · [Volver](../README.es.md)

**Keywords:** M750, V553, V853, V533, PhoenixCard, boot_package, sunxi-package, U-Boot `sf`, `sf probe`, `fatload`, `sunxi_card0_probe`, CRC32, recuperación SPI NOR, pantalla negra, sin retroiluminación, bootlogo, dump 16 MB

> **Resultado final:** la M750 volvió a mostrar el bootlogo y entró al **home correctamente**. La flash SPI NOR quedó restaurada al dump completo de fábrica (`M750_16MB_stock.bin`, MD5 `8c0abbd6e0f327e5d9ab38146a90f5ca`). No hizo falta regrabar la UI final para que el equipo arrancara bien.
>
> Este documento reconstruye **todo** el proceso, incluidos los intentos fallidos, para que pueda repetirse sin repetir los errores.

---

## 1. Síntoma y punto de partida

- Equipo: pantalla M750 (CarPlay / Tina Linux), 16 MiB de SPI NOR `py25q128ha`.
- Síntoma: bootlogo/negra después de meter cambios de UI en `mtdblock2`.
- Restricción inicial: sin cable USB de datos, sin consola serial, sin botones ni acceso a puertos de la pantalla.
- Ya se disponía del volcado completo de 16 MiB obtenido con el hook `debug1` (docs 01-10):

```text
dump_completo.bin
Tamaño:  16777216 bytes (0x1000000)
MD5:     8c0abbd6e0f327e5d9ab38146a90f5ca
SHA256:  f0bd763cff93f829b2cdabc026489c30b922b754c2a32053645ae90ac7f26dea
CRC32:   aed73153
```

- `rootfs` factory (`mtdblock2`): MD5 `43acc068c9d79de63e480970d2ff72e3`.
- `rootfs` con la UI final generada durante el trabajo: MD5 `2a3fb11dfe526948908e2a5e9148f855` (quedó como `/tmp/opencode/mtdblock2_final.bin`; **no fue necesario grabarlo** al final).
- `bootlogo` vigente (`mtdblock5`): MD5 `d105460a6164c8d5e861f337b429f873`.

---

## 2. Lo que no funcionó (y por qué)

### 2.1 PhoenixCard con imágenes V853

Se usó como donante la imagen `v853_linux_100ask_uart0.img` (MD5 `3fe608b451408643802f47451be0c70c`), que PhoenixCard aceptaba quemar en modo **Startup**.

Hallazgos:

1. **PhoenixCard valida el nombre del archivo.** Renombrar la imagen original hacía que fallara; con el nombre exacto `v853_linux_100ask_uart0.img` quemaba bien. Un cambio de un solo byte en relleno también quemaba bien, así que el rechazo no era por integridad genérica.
2. **El rechazo real venía de cambiar la estructura del `boot_package`.** El package original de 100ask tiene `valid_len=0x10c000` y 3 items:

   | Item | Offset | Longitud |
   |---|---:|---:|
   | `optee` | `0x800` | `0xc098` |
   | `u-boot` | `0xcc00` | `0xe0000` |
   | `dtb` | `0xecc00` | `0x1c000` |

   Si se cambiaban item count, offsets o longitudes, PhoenixCard terminaba con:

   ```text
   E: [pheonix card_00]Burn Sucess
   E: Burn Failed -1
   No Drive
   ```

   Conservando los 3 items, offsets y longitudes, y cambiando solo los bytes del payload, la imagen quemaba correctamente.
3. Checksums invertidos del formato:
   - `V*.fex`: suma de dwords little-endian del archivo, `& 0xffffffff`, guardada little-endian (no CRC32 ni MD5).
   - `sunxi-package`: `STAMP = 0x5F0A6C39` en `+0x14`; checksum = suma de dwords sobre `pkg[:valid_len]`. Coincide en los originales.
4. Los payloads M750 del package deben ir **raw**, no comprimidos:
   - `u-boot`: `8e0100ea75626f6f74…`
   - `dtb`: `d00dfeed…` (DTB descomprimido de 114290 bytes)
   - flag de item `3` en ambos.

Variantes generadas y resultado observado:

| Imagen | MD5 | Resultado |
|---|---|---|
| `M750_100ASK_SAMELEN.img` | `4199ca49aa7868a0a185936aa9efe39d` | Quemó en Startup; no se logró arranque útil |
| `M750_100ASK_COMBINED.img` | `694029fc799fa90fa9dcbb8ed90ca8f3` | Quemó en Startup; pantalla **sin retroiluminación** |
| `M750_100ASK_DTBONLY.img` | `b7a8f2f2fda64db354c01073589d9ecd` | Generada para aislar el DTB; no resolvió el arranque |
| `M750_SD_FULL.img` | `a4eef4bc3be0821fe46dbc7a09f833f8` | `cardscript` ampliado con ENV/BOOT/ROOTFS; sin arranque |
| 100ask original | `3fe608b451408643802f47451be0c70c` | Quemó; pantalla negra |
| R12 V533 854×480 | `11f65f1efdeddb8fa6bdf212b2259051` | Donante V533 preparado; no se obtuvo arranque |

### 2.2 La pista decisiva

Con cualquiera de esas SD puestas, la M750 quedaba **totalmente sin backlight**. Al sacar la SD y encender, **volvía el bootlogo original**. Eso demostró dos cosas:

- el NOR seguía intacto y arrancaba bien por sí solo;
- el fallo ocurría al intentar arrancar desde SD, antes de inicializar el panel.

Además, el `cardscript.fex` de 100ask solo tiene dos pasos:

```ini
[boot_0_0]   ; boot0 en LBA 16
[boot_1_0]   ; boot_package en LBA 32800
```

Es decir: el modo **Startup** de PhoenixCard escribe **solo boot0 + boot_package**. No escribe kernel ni rootfs. Agregar pasos al `cardscript` no sirvió porque el problema era de compatibilidad de SoC, no de particiones SD.

---

## 3. Identidad real del hardware

Al abrir físicamente la placa, la marcación del chip dice **V553**. Esto explica todo:

| | Firmware / intentos | Hardware real |
|---|---|---|
| String en `boot.img` | `v853-perf1` | — |
| SDK / plataforma del intento | `sun8iw21p1`, Cortex-A7 | `sun50i`, 4× Cortex-A53 |
| Chip soldado | — | **V553** (familia V533/V536) |

- **V553**: 4× Cortex-A53, Mali-T720 MP2, decodificación 4K@30. Mejor para UI/y uso general.
- **V853 / V853S**: Cortex-A7 + RISC-V, NPU ~1 TOPS, sin GPU dedicada. Mejor para visión/IA, pero **otra arquitectura**.
- **V533**: hermano del V553 (misma familia A53/sun50i). Por eso las imágenes R12/RX7/T86/BK1 eran los donantes más cercanos, aunque tampoco son el chip exacto.

> Corrección histórica: el repo decía «M750 = v853» basándose en el string del firmware. El string es el **target de compilación**, no el chip físico. La recuperación correcta fue usar el dump de la propia placa. Ver también la nota de corrección en [05-screen-analysis.es.md](05-screen-analysis.es.md).

---

## 4. Consola UART: el cambio de estrategia

El usuario logró comunicación por los pines **TX/RX** (más GND) a **115200 baudios**. Eso permitió abandonar PhoenixCard y grabar el NOR directamente desde U-Boot.

### 4.1 Prompt y comandos iniciales

Al encender y detener el arranque:

```text
=> help
...
sf      - SPI flash sub-system
sunxi_card0_probe- probe sunxi card0 device
...
```

Datos relevantes de `printenv`:

```text
bootcmd=run setargs_nor boot_normal
boot_normal=sunxi_flash read 44800000 ${boot_partition};bootm 44800000
boot_partition=boot
nor_root=/dev/mtdblock2
partitions=boot@mtdblock1:rootfs@mtdblock2:rootfs_data@mtdblock3:env@mtdblock4:bootlogo@mtdblock5:private@mtdblock6:UDISK@mtdblock7
uboot_message=2018.07-g7572878-dirty(06/15/2026-06:26:11)
```

`sf probe 0`:

```text
sf: bus-0 cs-0 spedd-50000000Hz mode-3000
SF: Detected py25q128ha(IO DTR) with page size 256 Bytes, erase size 64 KiB, total 16 MiB
```

`bdinfo`:

```text
DRAM bank 0: start 0x40000000, size 0x08000000   ; 128 MiB
arch_number = 0x00000000
baudrate    = 115200 bps
fdt_blob    = 43ee0e68
```

Conclusión: U-Boot corre desde RAM y `sf` ve el NOR completo; se puede grabar sin depender de Linux ni de PhoenixCard.

### 4.2 Inicializar la SD

`mmcinfo` falla al principio:

```text
=> mmcinfo
curr_device:-1
No MMC device available
```

La solución es el comando propio de Allwinner:

```text
=> sunxi_card0_probe
curr_device:0
Device: SUNXI SD/MMC
Name: APPSD
Capacity: 3.8 GiB
=> fatls mmc 0
            System Volume Information/
  16777216   dump_completo.bin
```

---

## 5. Preparar la SD

1. Formatear una microSD como **FAT32 superfloppy** (sin MBR/GPT), igual que para el hook `debug1`.
2. Copiar a la raíz el dump de 16 MiB del propio equipo:

```text
F:\dump_completo.bin      ; MD5 8c0abbd6e0f327e5d9ab38146a90f5ca
```

En el repo ese archivo está como [`dumps/M750/M750_16MB_stock.bin`](../dumps/M750/M750_16MB_stock.bin).

---

## 6. Secuencia exacta de grabación

Ejecutar **una línea por vez** en el prompt `=>`:

```text
sunxi_card0_probe
fatload mmc 0 0x42000000 dump_completo.bin
sf probe 0
sf erase 0x10000 0xff0000
sf write 0x42010000 0x10000 0xff0000
sf erase 0 0x10000
sf write 0x42000000 0 0x10000
```

Salida real de las escrituras:

```text
16777216 bytes read in 757 ms (21.1 MiB/s)
SF: 16711680 bytes @ 0x10000 Erased: OK
SF: 16711680 bytes @ 0x10000 time:17073 ms Written: OK
SF: 65536 bytes @ 0x0 Erased: OK
SF: 65536 bytes @ 0x0 time:59 ms Written: OK
```

### Por qué ese orden

- Se graba primero **todo excepto boot0** (`0x10000..0xffffff`). Si algo falla ahí, el equipo todavía entra a U-Boot y se puede repetir.
- El **boot0 se graba al final**. Es lo único que puede dejar el equipo sin arranque si se corta la alimentación.
- El buffer en `0x42000000` es el dump completo; el resto se escribe desde `0x42010000` (salta el boot0) y luego el boot0 desde `0x42000000`.

### Avisos que aparecen y son normales

```text
ERROR: reserving fdt memory region failed (addr=48000000 size=400000)
...
```

son avisos de reserva FDT de `fatload`, no fallos de lectura.

Si `sf` parece desaparecer y dice `Unknown command 'sf'` tras la transferencia, escribir solo `sf` y pulsar Enter: vuelve el usage y se puede continuar. Fue un glitch de la serial, no un comando eliminado.

---

## 7. Verificación

La lectura de **todo el chip** falla por DMA:

```text
=> sf read 0x43000000 0 0x1000000
device 0 whole chip
rx wait_dma_recv_over fail
SF: ... Read: ERROR -1
=> crc32 0x43000000 0x1000000
CRC32 ... ==> 6f3b4103     ; NO confiar en este valor
```

Verificar **por bloques pequeños**:

```text
=> sf read 0x43000000 0 0x10000
device 0 offset 0x0, size 0x10000
rx wait_dma_recv_over fail
SF: ... Read: ERROR -1
=> crc32 0x43000000 0x10000
CRC32 for 43000000 ... 4300ffff ==> 5560ecb6
```

`5560ecb6` es exactamente el CRC32 del boot0 del dump. El mensaje `rx wait_dma_recv_over fail` aparece pero **los datos leídos son correctos** en lecturas chicas.

CRCs de referencia del dump:

| Rango | Tamaño | CRC32 |
|---|---:|---|
| `0x0..0xffff` (boot0) | `0x10000` | `5560ecb6` |
| `0x10000..0xffffff` (resto) | `0xff0000` | `698f2fc1` |
| Todo el dump | `0x1000000` | `aed73153` |
| `0x10000..0x5ffff` (package) | `0x50000` | `4a57c7dc` |
| `0x60000..0x28ffff` (boot) | `0x230000` | `43260230` |
| `0x290000..0xf3ffff` (rootfs) | `0xcb0000` | `3038e714` |
| `0xf90000..0xfaffff` (env) | `0x20000` | `a3293403` |
| `0xfb0000..0xfcffff` (bootlogo) | `0x20000` | `ce3c4937` |

---

## 8. Reinicio y resultado final

```text
=> reset
```

Tras el reset:

- volvió el **bootlogo**;
- el sistema siguió arrancando y entró al **home**;
- la pantalla quedó funcionando perfecto.

No fue necesario regrabar el `rootfs` con la UI final ni tocar el bootlogo: el dump completo de fábrica ya dejó el equipo operativo.

---

## 9. Checklist de reproducción

1. Tener el dump correcto del **mismo equipo**: MD5 `8c0abbd6e0f327e5d9ab38146a90f5ca`.
2. SD FAT32 superfloppy con `dump_completo.bin` en la raíz.
3. UART 115200 8N1, GND común; detener en `=>`.
4. `sunxi_card0_probe` → `fatls mmc 0` debe listar 16777216 bytes.
5. `fatload mmc 0 0x42000000 dump_completo.bin`.
6. `sf probe 0` → detectar `py25q128ha`, 16 MiB, erase 64 KiB.
7. Borrar y escribir resto, luego boot0 (orden de la sección 6).
8. Verificar boot0: `crc32 0x43000000 0x10000` → `5560ecb6`.
9. `reset`.
10. **No cortar alimentación** durante `sf erase`/`sf write`.

### No hacer

- No quemar imágenes V853/V837S/V873S en una placa V553.
- No fiarse del `sf read` de 16 MiB completo.
- No usar PhoenixCard Product/NOR sin haber validado antes el arranque SD y el layout.
- No mezclar dumps de TF811 y M750: distinto `boot`/`rootfs`, distinta RAM y distinto panel.

---

## 10. Archivos relacionados

- [Volcados completos](../dumps/README.md) — TF811 y M750, con hashes.
- [Doc 05](05-screen-analysis.es.md) — comparativa de las dos placas (con corrección de chip).
- [Doc 11](11-volcado-podofo-a4628-uart.es.md) — origen del método por UART.
- [`examples/uart-restore-M750.txt`](../examples/uart-restore-M750.txt) — transcripción sanitizada de la sesión que funcionó.
