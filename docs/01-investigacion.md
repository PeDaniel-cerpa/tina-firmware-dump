# 01 - Investigacion del firmware

[English](01-investigation.en.md) · [Volver](../README.md)

Esta es la fase de analisis que explica **por que** funciona el metodo. No hace falta repetirla para usar el procedimiento, pero ayuda a adaptarlo a otros modelos.

---

## 1. Identificacion del equipo

A partir del firmware extraido (`podofo_full.bin`, y luego del volcado directo):

```text
Sistema:        Tina Linux (OpenWrt), release Neptune
Version:        4.0.0
Kernel:         Linux 4.9.191
Rootfs:         squashfs (solo lectura) + overlay
Arquitectura:   ARM EABI5, hard-float
Loader:         /lib/ld-musl-armhf.so.1  (musl libc)
Modelo 1:       TF811  -> build tina.zengfu.20260302,   target v837s-perf1, 64 MB RAM
Modelo 2:       M750   -> build tina.zhangxiangpu.20260815, target v853-perf1, 128 MB RAM
Resolucion:     854x480
WiFi:           rtl8733bs / rtl8821cs
```

El `cmdline` del kernel confirma el esquema de particiones:

```text
root=/dev/mtdblock2 rootwait init=/pseudo_init rdinit=/rdinit
partitions=boot@mtdblock1:rootfs@mtdblock2:rootfs_data@mtdblock3:
            env@mtdblock4:bootlogo@mtdblock5:private@mtdblock6:UDISK@mtdblock7
androidboot.hardware=sun8iw21p1 boot_type=3 gpt=1
```

---

## 2. El gancho: `/etc/init.d/S01app`

Dentro del rootfs extraido, el archivo `etc/init.d/S01app` contiene exactamente:

```sh
if [ -z "$(grep '\<vfat\>' /proc/mounts)" ]; then
     /bin/mount -t vfat /dev/mmcblk0 /mnt/extsd 2>/dev/null
#    && /bin/mount -t vfat /dev/mmcblk0p1 /mnt/extsd
if [ -f "/mnt/extsd/debug1" ];then
        echo "sdcard had been mount and find th debug1"
        /mnt/extsd/debug1
fi
fi
```

Tres conclusiones críticas:

1. **Se ejecuta como root**: todos los scripts de `/etc/init.d/` corren con UID 0. No hace falta escalar privilegios.
2. **Busca un nombre exacto**: `/mnt/extsd/debug1`, sin extension. `debug1.sh` o `DEBUG1` no sirven.
3. **Es sincronico**: `S01app` espera a que `debug1` termine antes de seguir arrancando la WiFi y la app. Cualquier servicio de red debe lanzarse en segundo plano (`&`).

Y un problema oculto muy importante:

```sh
/bin/mount -t vfat /dev/mmcblk0 /mnt/extsd 2>/dev/null    # <- monta el DISCO ENTERO
# && /bin/mount -t vfat /dev/mmcblk0p1 /mnt/extsd         # <- ESTA LINEA ESTA COMENTADA
```

El firmware intenta montar `/dev/mmcblk0`, **no la particion 1**.

---

## 3. El problema de la SD (y su solucion)

Con una microSD normal en **MBR con una particion FAT32**:

```text
/dev/mmcblk0     <- disco entero (tabla MBR, no es FAT)
/dev/mmcblk0p1   <- particion FAT32 (aqui estan los archivos)
```

`mount -t vfat /dev/mmcblk0` **falla**. Como la linea alternativa `mmcblk0p1` esta comentada, `/mnt/extsd` queda vacio y el `if [ -f /mnt/extsd/debug1 ]` nunca se cumple. Resultado: ni log, ni volcado.

Con una microSD **FAT32 superfloppy**:

```text
/dev/mmcblk0     <- FAT32 directo (sin MBR, sin particiones)
```

`mount -t vfat /dev/mmcblk0` **funciona**, el gancho dispara y `debug1` corre como root.

> Este fue el cambio clave que hizo que el metodo pasara de "no pasa nada" a "volcado completo".

Nota: `rc.final` y `etc/udev/hotplug-tf.sh` si montan `mmcblk0p1`, pero lo hacen **despues** de que `S01app` ya paso el chequeo. Por eso no sirven como alternativa.

---

## 4. Que herramientas hay (y cuales no)

Se reviso el rootfs y el busybox incluido:

| Herramienta | Disponible en el firmware | Uso |
|---|---|---|
| `/bin/sh`, `dd`, `cp`, `mount`, `ifconfig`, `route`, `pidof` | Si | Volcado y diagnostico |
| `sshd`, `dropbear` | **No** | - |
| `telnetd` (busybox del firmware) | **No** (no compilado) | - |
| `tftp`, `nc`, `netcat` | **No** | - |
| `httpd` | **No** | - |
| `adbd` | **No** (`S50adb` tiene `exit`; `S50usb` lo intenta y falla) | - |

Por eso la shell remota tiene que **entrar desde la SD**, no usar lo que trae el equipo.

---

## 5. Eleccion del servidor de red

### Intentos fallidos

| Binario probado | Motivo del fallo |
|---|---|
| `socat` 1.7.4.4 de OpenWrt 23.05 (`arm_cortex-a7_vfpv4`) | Requiere simbolos `__nanosleep_time64`, `__gettimeofday_time64`, `__localtime64`, `__lstat_time64`. La musl del firmware es mas vieja (ABI time32). |
| `socat` 1.7.3.4 de OpenWrt 21.02 (`arm_cortex-a7`) | Sin simbolos time64, pero es soft-float e interprete `/lib/ld-musl-arm.so.1` (distinto del `/lib/ld-musl-armhf.so.1` del equipo). |
| `socat` 1.7.3.4 de Alpine 3.12 (`armv7`, armhf) | Interprete correcto y sin time64, pero depende de `libssl.so.1.1`, `libcrypto.so.1.1` y `libreadline.so.8` que no estan en el rootfs. |

### Solucion elegida

**BusyBox 1.31.0 estatico para ARMv7** (`busybox.net`, build `defconfig-multiarch-musl`):

```text
ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), statically linked, stripped
```

- No necesita **ninguna** libreria del sistema (resuelve el problema de musl).
- Incluye el applet `telnetd`.
- Se invoca como `/mnt/extsd/busybox_net telnetd -p 23 -l /bin/sh`.
- El `-l /bin/sh` entra directo en root, sin archivo `/etc/passwd` ni password.

---

## 6. Estrategia final resumida

```text
SD superfloppy FAT32
   |
   |  S01app: mount -t vfat /dev/mmcblk0 /mnt/extsd
   v
/mnt/extsd/debug1  (root, sincronico)
   |
   +--> info.txt       (CMDLINE, /proc/mtd, ifconfig, route, mounts)
   +--> mtdblock0..7.bin  (dd bs=64k de cada /dev/mtdblock*)
   +--> etc/, overlay/, data/  (cp -RpL, sin seguir enlaces problematicos)
   |
   +--> busybox_net telnetd -p 23 -l /bin/sh  &   (background, no bloquea)
```

El resultado es un volcado **completo y legible** sin tocar la flash ni desarmar el dispositivo.
