# Volcado de firmware de pantallas Allwinner / Tina Linux sin desarmar

[English (default)](README.md) · [Procedimiento completo](docs/02-procedure.es.md) · [Solución de problemas](docs/04-troubleshooting.es.md)

Guia practica, probada en hardware real, para **obtener una shell root por IP y copiar el firmware completo** de una pantalla CarPlay basada en Allwinner con Tina Linux (OpenWrt), **sin desarmar el equipo y sin regrabar la flash**.

Todo se apoya en un unico "gancho" que ya trae el firmware: `/etc/init.d/S01app` ejecuta `/mnt/extsd/debug1` como root si ese archivo existe en la microSD.

> **Estado:** metodo verificado en dos pantallas reales (modelos **TF811** y **M750**). Ambas producen un volcado completo de 8 particiones MTD (16 MB) mas `/etc`, `/overlay` y `/data`.

---

## Palabras clave

`allwinner` `tina linux` `openwrt` `volcado de firmware` `extraccion de firmware` `copiar firmware` `pantalla carplay` `carplay` `autorradio android` `shell root` `telnetd` `busybox` `mtd` `nand flash` `mtdblock` `linux embebido` `ingenieria inversa` `armv7` `armhf` `musl` `fat32` `superfloppy` `tarjeta SD` `alternativa ADB` `sin desarmar` `v853` `v837s` `sun8iw21p1` `TF811` `M750` `uboot` `squashfs` `overlayfs` `shell por IP` `Tera Term`

---

## Indice

| Documento | Contenido |
|---|---|
| [01 - Investigacion](docs/01-investigation.es.md) | Que se encontro en el firmware y POR QUE funciona el metodo |
| [02 - Procedimiento](docs/02-procedure.es.md) | Paso a paso, desde cero hasta el volcado en el PC |
| [03 - Archivos](docs/03-files.es.md) | Los archivos usados, que hacen y de donde salieron |
| [04 - Solucion de problemas](docs/04-troubleshooting.es.md) | Todos los fallos encontrados y como se resolvieron |
| [05 - Analisis de las dos pantallas](docs/05-screen-analysis.es.md) | TF811 vs M750: diferencias y advertencias |
| [06 - Modificar imagenes](docs/06-modificar-imagenes.es.md) | Cambiar el logo de arranque, fondos e iconos |
| [07 - Opciones desactivadas](docs/07-opciones-desactivadas.es.md) | Servicios desactivados, binarios ausentes, flags XML y nodos DTB |

---

## Resumen rapido

### 1. Preparar la microSD

La SD **no puede ser MBR con particion**. Debe ser **FAT32 "superfloppy"** (sistema de archivos directo en el disco, sin tabla de particiones). Esto es obligatorio porque el firmware monta `/dev/mmcblk0` (disco entero), no `/dev/mmcblk0p1`.

```bash
# Linux (requiere mkfs.fat y mtools)
./scripts/make_sd_image.sh firmware_dump.img
```

```powershell
# Windows (PowerShell como Administrador)
.\scripts\write_sd_windows.ps1 -ImagePath .\firmware_dump.img -DiskNumber 1 -DriveLetter F
```

Resultado:

```
F:\
├── debug1          <- script, se ejecuta como root al arrancar
└── busybox_net     <- BusyBox estatico ARM con telnetd
```

### 2. Arrancar la pantalla

1. Apaga la pantalla, inserta la SD y enciendela.
2. Espera 30-40 segundos.
3. Conecta el PC al WiFi de la pantalla (`TF811-xxxx` o `M750-xxxx`, clave `12345678`).
4. Pon IP fija en el PC: `192.168.10.250`, mascara `255.255.255.0`, gateway `192.168.10.1`.

### 3. Conectar y recoger

```text
Tera Term -> New connection -> TCP/IP
Host: 192.168.10.1
Port: 23
```

No pide password: entra directo en un prompt root. Si la IP no es esa, mirala en `firmware_dump/info.txt` (seccion `ifconfig`).

Al sacar la SD:

```
F:\
├── debug1.log
└── firmware_dump\
    ├── info.txt
    ├── mtdblock0.bin ... mtdblock7.bin    <- EL FIRMWARE COMPLETO
    ├── etc\
    ├── overlay\
    └── data\
```

---

## Archivos incluidos

| Archivo | Tamano | Funcion |
|---|---|---|
| [`files/debug1`](files/debug1) | 2 KB | Script principal: vuelca MTD, copia configuracion y levanta telnetd |
| [`files/debug1-bootlogo.sh`](files/debug1-bootlogo.sh) | 4 KB | Igual, pero graba `bootlogo.bin` desde la SD automaticamente |
| [`files/busybox_net`](files/busybox_net) | 1.1 MB | BusyBox 1.31 estatico ARMv7 con applet `telnetd` |
| [`files/debug1-v1-socat.sh`](files/debug1-v1-socat.sh) | 2 KB | Version original (intento con socat, **no funciona**: ver doc 04) |
| [`files/socat`](files/socat) | 205 KB | Binario que fallo por ABI time64 de musl (se conserva como referencia) |
| [`files/README.txt`](files/README.txt) | 2.6 KB | Instrucciones originales que se copiaron a la SD |
| [`scripts/make_sd_image.sh`](scripts/make_sd_image.sh) | - | Crea la imagen FAT32 superfloppy |
| [`scripts/write_sd_windows.ps1`](scripts/write_sd_windows.ps1) | - | Escribe la imagen en el disco ( Windows, eleva automaticamente) |
| [`scripts/make_bootlogo.sh`](scripts/make_bootlogo.sh) | - | Convierte tu imagen en un bootlogo valido de 854x480 |

Checksums SHA256 y URLs de origen: [docs/03-files.es.md](docs/03-files.es.md).

Tambien se incluyen logs **reales** de una ejecucion correcta en [`examples/`](examples/), utiles para comparar si algo sale mal:

```text
examples/debug1-M750.log    <- log de ejecucion del script
examples/info-M750.txt      <- CMDLINE, /proc/mtd, ifconfig, route, mounts
```

> Antes de subir el repo, revisa `examples/info-M750.txt`: contiene datos del equipo (MAC, cmdline). Si no quieres publicarlos, sustituye el archivo por una version anonimizada.

---

## Por que no funcionan los metodos obvios

| Metodo | Resultado |
|---|---|
| `sshd` / `dropbear` | No estan en el rootfs |
| `telnetd` del firmware | El busybox incluido no lo compila |
| `tftp` / `nc` del firmware | No disponibles |
| ADB | `adbd` no existe; `S50adb` tiene `exit` al inicio |
| WSL -> `nc 192.168.10.1` | WSL2 va por NAT, no alcanza esa red (usar Tera Term desde Windows) |
| `socat` de OpenWrt 23.05 | Falla: `__nanosleep_time64: symbol not found` (musl time64) |
| SD en MBR/FAT32 normal | El hook nunca se ejecuta: el firmware monta `/dev/mmcblk0`, no la particion |

Detalle completo en [docs/04-troubleshooting.es.md](docs/04-troubleshooting.es.md).

---

## Advertencia importante

Este metodo es **de lectura y diagnostico**. No modifica la flash del equipo.

Los dos modelos analizados (**TF811** con chip `v837s`/64 MB y **M750** con chip `v853`/128 MB) **no son intercambiables**: distinto SoC, distinta RAM, distinto panel y distinta calibracion de camara. No flashees el firmware de uno en el otro. Ver [docs/05-screen-analysis.es.md](docs/05-screen-analysis.es.md).

---

## Licencia

MIT. Los binarios de terceros (BusyBox, socat) conservan sus propias licencias; se incluyen unicamente como herramientas de diagnostico.
