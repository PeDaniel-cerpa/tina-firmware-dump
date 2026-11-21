# 02 - Procedimiento completo

[English](02-procedure.md) · [Volver](../README.es.md)

**Keywords:** tutorial volcado de firmware, microSD FAT32 superfloppy, IP fija 192.168.10.250, Tera Term, telnet puerto 23, volcado MTD con dd, shell root, sin desarmar

Paso a paso, desde cero hasta tener el firmware en el PC. Tiempo estimado: 15-25 minutos.

---

## Requisitos

- La pantalla (obviamente) y una microSD de al menos 1 GB.
- Un PC con Windows (para Tera Term) o con lector de SD.
- Windows: **PowerShell como Administrador** (para escribir el disco en crudo).
- Linux: `mkfs.fat` (dosfstools) y `mtools` (`mcopy`).
- Los archivos de [`files/`](../files/).

> Todo el procedimiento es **no destructivo para la pantalla**: solo se escribe la microSD.

---

## Fase 0 - Identificar el disco de la SD

Con la SD conectada al PC, en Windows:

```powershell
Get-Partition -DriveLetter F | Get-Disk |
  Select-Object Number,FriendlyName,PartitionStyle,
                @{N='SizeGB';E={[math]::Round($_.Size/1GB,2)}}
```

Ejemplo real:

```text
Number         : 1
FriendlyName   : MXT-USB Storage Device
PartitionStyle : MBR
SizeGB         : 3.75
```

Anota el **numero de disco** (en el ejemplo, `1`). Se usara como `-DiskNumber`.

Tambien conviene verificar que sea FAT32:

```powershell
Get-Volume -DriveLetter F | Select DriveLetter,FileSystem,SizeRemaining
```

---

## Fase 1 - Preparar los archivos

Copia estos dos archivos a una carpeta de trabajo:

```text
debug1          (el script)
busybox_net     (BusyBox estatico con telnetd)
```

Ambos deben quedar en la **raiz** de la SD, con estos nombres exactos:

```
F:\debug1
F:\busybox_net
```

Si editas `debug1` en Windows, guardalo con saltos de linea **LF** (no CRLF):

```bash
sed -i 's/\r$//' debug1
sh -n debug1        # debe decir que la sintaxis es correcta
```

Comprobacion rapida de que no hay CRLF:

```powershell
$b=[IO.File]::ReadAllBytes("F:\debug1")
"CRLF=$(([regex]::Matches([Text.Encoding]::ASCII.GetString($b),"`r`n")).Count)"
"LF=$(([regex]::Matches([Text.Encoding]::ASCII.GetString($b),"`n")).Count)"
```

Debe dar `CRLF=0`.

---

## Fase 2 - Crear la SD superfloppy (FAT32 sin tabla de particiones)

Esta es la parte CRITICA. Una SD MBR normal no funciona.

### Opcion A: Linux (recomendado)

```bash
# Instalar herramientas si faltan
sudo apt install -y dosfstools mtools

# Crear imagen de 1 GB con FAT32 directo (sin MBR)
./scripts/make_sd_image.sh firmware_dump.img

# Verificar
./scripts/verify_sd.sh firmware_dump.img
```

Salida esperada:

```text
Volume in drive : is FIRMWARE
Directory for ::/
debug1        2068 ...
busybox_net 1152216 ...
        2 files          1 155 284 bytes
                  1 068 000 256 bytes free
```

Luego escribe la imagen en la SD con `dd`:

```bash
sudo dd if=firmware_dump.img of=/dev/sdX bs=4M status=progress conv=fsync
```

> **Cuidado:** `/dev/sdX` es el disco de la SD, no tu disco del sistema. Verificalo con `lsblk`.

### Opcion B: Windows (PowerShell elevado)

El script se eleva solo (mostrara UAC). **Borrara todo el contenido del disco elegido.**

```powershell
.\scripts\write_sd_windows.ps1 `
    -ImagePath .\firmware_dump.img `
    -DiskNumber 1 `
    -DriveLetter F
```

Si no quieres crear la imagen en Linux, tambien puedes usar **Rufus** en modo *DD Image* seleccionando el `.img`.

### Verificacion en Windows

```powershell
Get-Volume -DriveLetter F | Select DriveLetter,FileSystem,Size
Get-ChildItem F:\ | Select Name,Length
```

Debe mostrar `FileSystem = FAT32`, tamano ~1 GB, y solo `debug1` + `busybox_net`.

> Nota: Windows puede seguir mostrando "PartitionStyle: MBR" en el administrador de discos porque la imagen no tiene tabla; lo importante es que `mount -t vfat /dev/mmcblk0` funcione en la pantalla.

---

## Fase 3 - Configurar la red en Windows

### 3.1 Conectar al WiFi de la pantalla

- SSID: `TF811-xxxx` (o `M750-xxxx`)
- Clave: `12345678`

### 3.2 Poner IP fija

Interfaz grafica:

1. `Win + R` -> `ncpa.cpl`
2. Clic derecho sobre **Wi-Fi** -> Propiedades
3. Doble clic en **Protocolo de Internet version 4 (TCP/IPv4)**
4. Seleccionar **Usar la siguiente direccion IP**:

```text
Direccion IP:        192.168.10.250
Mascara de subred:   255.255.255.0
Puerta de enlace:    192.168.10.1
DNS:                 (vacio)
```

Por comando (PowerShell como Administrador):

```powershell
netsh interface ip set address name="Wi-Fi" static 192.168.10.250 255.255.255.0 192.168.10.1
```

Para ver el nombre exacto del adaptador:

```powershell
Get-NetAdapter | Where Status -ne Disabled | Select Name,Status,ifIndex
```

### 3.3 Verificar

```cmd
ping 192.168.10.1
```

Si no responde, no sigas: revisa el WiFi y la IP. (La IP real puede ser otra; esta en `info.txt` dentro de la SD despues del arranque.)

> No uses WSL para el `ping` ni para el `nc`: WSL2 va por NAT y no alcanza la red `192.168.10.x`. Usa comandos de Windows o Tera Term.

---

## Fase 4 - Arrancar y conectarse

1. **Apaga la pantalla.**
2. Inserta la SD ya preparada **antes de encender**.
3. Enciende y espera **30-40 segundos** (el script tarda ~7 s en volcar, pero la WiFi tarda mas).
4. Abre **Tera Term**:
   - `File -> New connection`
   - Selecciona **TCP/IP**
   - **Host:** `192.168.10.1`
   - **Port:** `23`
   - `OK`
5. Presiona **Enter** un par de veces. Debe aparecer:

```text
/ #
```

o bien:

```text
root@TinaLinux:~#
```

6. Verifica:

```sh
whoami        # -> root
cat /proc/mtd
```

No hay password: el script usa `telnetd -l /bin/sh`, que entra directo como root.

Alternativa con `nc` nativo de Windows:

```cmd
nc 192.168.10.1 23
```

---

## Fase 5 - Recoger el volcado

Apaga la pantalla, saca la SD y conectala al PC. Debe contener:

```
F:\
├── debug1.log
├── debug1
├── busybox_net
└── firmware_dump\
    ├── info.txt
    ├── mtdblock0.bin    384 KB   uboot
    ├── mtdblock1.bin    2.1 MB   boot
    ├── mtdblock2.bin   12.7 MB   rootfs
    ├── mtdblock3.bin    320 KB   rootfs_data
    ├── mtdblock4.bin    128 KB   env
    ├── mtdblock5.bin    128 KB   bootlogo
    ├── mtdblock6.bin     64 KB   private
    ├── mtdblock7.bin    128 KB   UDISK
    ├── etc\
    ├── overlay\
    └── data\
```

Copia `F:\firmware_dump\` a tu carpeta de trabajo y guardalo.

El `debug1.log` debe terminar asi:

```text
[debug1] telnetd ACTIVO en puerto 23 -> Tera Term: 192.168.10.1:23
[debug1] === FIN Thu Jan  1 00:00:09 UTC 1970 ===
```

(La fecha es 1970 porque el equipo no tiene RTC con bateria; es normal.)

---

## Fase 6 - Volver a la normalidad

Devuelve el WiFi del PC a DHCP:

```powershell
netsh interface ip set address name="Wi-Fi" dhcp
```

Y, si quieres dejar la SD como estaba, borra solo `firmware_dump` y `debug1.log`. Los archivos `debug1` y `busybox_net` pueden quedarse: no hacen nada si no arranca el equipo con esa SD.

---

## Comandos utiles dentro de la shell

```sh
cat /proc/mtd                                          # particiones
df -h                                                  # espacio
cat /etc/banner                                        # version del sistema
dd if=/dev/mtdblock5 of=/mnt/extsd/bootlogo.bin        # copiar solo el logo
cp -a /etc /mnt/extsd/etc2                             # copiar configuracion
ifconfig                                              # ver la IP real
```

---

## Repetir el volcado

No hace falta rehacer la SD. Borra `F:\firmware_dump` (y opcionalmente `debug1.log`), vuelve a insertar la SD y arranca. El script lo recrea todo.
