# 03 - Archivos utilizados

[English](03-files.en.md) · [Volver](../README.md)

Inventario completo de cada archivo que se uso en el procedimiento, su funcion, origen y checksum.

---

## 1. `debug1` - el script principal

**Ruta en la SD:** `/mnt/extsd/debug1` (raiz, sin extension)
**Tamano:** 2068 bytes
**SHA256:** `cff1f9167a5ad338e48e7dc0228306b996fb0b9e5148d37293f78be039036882`
**Fuente:** [`files/debug1`](../files/debug1)

Lo que hace, en orden:

1. Escribe `/mnt/extsd/debug1.log` (se sobrescribe en cada arranque).
2. Genera `firmware_dump/info.txt` con:
   - `date`, `/proc/cmdline`, `/proc/mtd`, `/proc/partitions`
   - `/proc/mounts`, salida de `ifconfig` y `route -n`
   - **Aqui se ve la IP real del equipo**, util si el DHCP no dio `192.168.10.1`.
3. Volca cada `/dev/mtdblock*` con `dd if=... of=firmware_dump/<nombre>.bin bs=64k`.
4. Copia `/etc`, `/overlay` y `/data` con `cp -RpL` (dereferencia symlinks; `cp -Rp` normal fallaba con `Operation not permitted` en FAT32).
5. Si existe `/mnt/extsd/busybox_net`, lanza en segundo plano:

```sh
/mnt/extsd/busybox_net telnetd -p 23 -l /bin/sh >> "$LOG" 2>&1 &
```

6. Escribe `=== FIN ... ===` y sale con `exit 0`.

### Por que `exit 0` y el `&` son importantes

`S01app` llama al script de forma sincronica. Si `telnetd` corriera en primer plano, el arranque se quedaria colgado esperando a que el servidor termine (nunca termina) y la WiFi/app no levantarian. El `&` lo deja en background y el `exit 0` le dice a init que todo salio bien.

### Requisitos de formato

- Nombre exacto: `debug1` (sin `.sh`, sin mayusculas).
- Saltos de linea **LF** (UNIX). Con CRLF, el `/bin/sh` del firmware puede fallar con `^M: not found`.
- Permisos de ejecucion: `chmod +x debug1` (en FAT32 todos los archivos son ejecutables de todos modos).

---

## 2. `busybox_net` - el servidor telnet

**Ruta en la SD:** `/mnt/extsd/busybox_net`
**Tamano:** 1 152 216 bytes (1.1 MB)
**SHA256:** `cd04052b8b6885f75f50b2a280bfcbf849d8710c8e61d369c533acf307eda064`
**Tipo:** `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), statically linked, stripped`
**Origen:** [BusyBox 1.31.0, build `defconfig-multiarch-musl`, `busybox-armv7l`](https://busybox.net/downloads/binaries/1.31.0-defconfig-multiarch-musl/busybox-armv7l)

Se renombro a `busybox_net` para que el script pueda comprobar su existencia con un nombre propio.

Applets verificados dentro del binario:

```text
telnetd     <- el que usamos
telnet
httpd
tftp
```

(no incluye `sh`/`ash` standalone, pero no lo necesitamos: usamos `-l /bin/sh` del propio firmware).

### Por que estatico

El firmware usa musl antiguo. Cualquier binario dinamico compilado contra musl nuevo falla con errores `__*_time64: symbol not found`. Al ser estatico, **no carga ninguna libreria del sistema** y el problema desaparece.

El comando exacto que se ejecuta:

```sh
/mnt/extsd/busybox_net telnetd -p 23 -l /bin/sh
```

`-l /bin/sh` sustituye al login: entra directo como root, sin `/etc/passwd` ni contrasena.

---

## 3. `socat` - el intento fallido (se conserva como referencia)

**Tamano:** 209 380 bytes
**SHA256:** `8baea5a082d47fce4c7639d51f8cda291219ea7651d9fc43780ff890ba2960be`
**Origen:** [OpenWrt 23.05.2, `socat_1.7.4.4-1_arm_cortex-a7_vfpv4.ipk`](https://downloads.openwrt.org/releases/23.05.2/packages/arm_cortex-a7_vfpv4/packages/socat_1.7.4.4-1_arm_cortex-a7_vfpv4.ipk)
**Interprete:** `/lib/ld-musl-armhf.so.1` (coincide con el firmware)

Parecia compatible (mismo interprete, hard-float), pero **no funciona**. Al ejecutarlo:

```text
Error relocating /mnt/extsd/socat: __nanosleep_time64: symbol not found
Error relocating /mnt/extsd/socat: __gettimeofday_time64: symbol not found
Error relocating /mnt/extsd/socat: __localtime64: symbol not found
Error relocating /mnt/extsd/socat: __lstat_time64: symbol not found
```

Se probaron tambien:

| Version | Resultado |
|---|---|
| OpenWrt 21.02.7 `arm_cortex-a7` (`socat_1.7.3.4-2`) | Sin time64, pero soft-float e interprete `/lib/ld-musl-arm.so.1` |
| Alpine 3.12 `armv7` (`socat-1.7.3.4-r0.apk`) | Interprete correcto, pero depende de `libssl.so.1.1`, `libcrypto.so.1.1`, `libreadline.so.8` |

Por eso se descarto. El script [`files/debug1-v1-socat.sh`](../files/debug1-v1-socat.sh) es la version original que lo usaba (puerto 4444) y se incluye solo como documentacion historica.

---

## 4. `README.txt`

**Tamano:** 2614 bytes
**SHA256:** `fac892d40496a4811f0c000110957de1fcb11adc3b6a46a51bb72331ba256cd9`
**Fuente:** [`files/README.txt`](../files/README.txt)

Instrucciones originales en espanol que se copiaron a la SD junto al `debug1` v1. Se conservan porque documentan como se concibio el metodo (aunque menciona `socat` y el puerto 4444, que ya no se usan).

---

## 5. Scripts de apoyo

### `scripts/make_sd_image.sh`

Crea una imagen `.img` FAT32 superfloppy de 1 GB y copia `debug1` + `busybox_net` a la raiz. Usa `mkfs.fat -F 32 -s 4` y `mcopy -i`.

```bash
./scripts/make_sd_image.sh firmware_dump.img
```

### `scripts/verify_sd.sh`

Lista el contenido de la imagen y comprueba que los dos archivos esten presentes y con el tamano correcto.

```bash
./scripts/verify_sd.sh firmware_dump.img
```

### `scripts/write_sd_windows.ps1`

Escribe la imagen en crudo en un disco Windows. Se eleva automaticamente a Administrador. Usa `FSCTL_DISMOUNT_VOLUME` para liberar el volumen antes de escribir (sin eso, Windows devuelve `Acceso denegado`).

```powershell
.\scripts\write_sd_windows.ps1 -ImagePath .\firmware_dump.img -DiskNumber 1 -DriveLetter F
```

Parametros:

| Parametro | Significado |
|---|---|
| `-ImagePath` | Ruta al `.img` |
| `-DiskNumber` | Numero de disco (Get-Disk) |
| `-DriveLetter` | Letra asignada a la SD |

> **Advertencia:** el disco elegido se borra por completo. Verifica dos veces el numero.

---

## Tabla de checksums

| Archivo | SHA256 |
|---|---|
| `debug1` (v2, funcional) | `cff1f9167a5ad338e48e7dc0228306b996fb0b9e5148d37293f78be039036882` |
| `debug1` v1 (socat, fallido) | `6c51277da3a5ceb33f9dbd1e7486bd44682fd2726f3f80dd8d000041254a2c28` |
| `busybox_net` | `cd04052b8b6885f75f50b2a280bfcbf849d8710c8e61d369c533acf307eda064` |
| `socat` | `8baea5a082d47fce4c7639d51f8cda291219ea7651d9fc43780ff890ba2960be` |
| `README.txt` | `fac892d40496a4811f0c000110957de1fcb11adc3b6a46a51bb72331ba256cd9` |
