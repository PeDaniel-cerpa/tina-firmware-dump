# 04 - Solucion de problemas

[English](04-troubleshooting.md) · [Volver](../README.es.md)

**Keywords:** solucion de problemas volcado firmware, symbol not found time64, acceso denegado disco, diskpart medios extraibles, wsl mount, CRLF, symlinks FAT32, connection timeout

Todos los problemas que aparecieron durante el desarrollo del metodo, con el diagnostico y la solucion real aplicada. Si algo falla, busca aqui primero.

---

## 1. No se crea `debug1.log` ni `firmware_dump`

**Sintoma:** tras arrancar con la SD, la SD sigue igual: solo `debug1` y `busybox_net`. No hay log.

**Causa:** la SD es MBR con particion FAT32. El firmware hace:

```sh
mount -t vfat /dev/mmcblk0 /mnt/extsd 2>/dev/null   # disco entero -> FALLA
# && mount -t vfat /dev/mmcblk0p1 /mnt/extsd        # comentada
if [ -f /mnt/extsd/debug1 ]; then ... fi             # nunca se cumple
```

**Solucion:** convertir la SD en FAT32 superfloppy (sin tabla de particiones). Ver [Fase 2](02-procedure.es.md#fase-2---crear-la-sd-superfloppy-fat32-sin-tabla-de-particiones).

**Como confirmar la causa:** el log de la SD no existe. Si el log existe pero no hay shell, salta al problema 4.

---

## 2. `Operation not permitted` al copiar `/etc`

**Sintoma** en `debug1.log`:

```text
cp: can't create symlink '/mnt/extsd/firmware_dump/etc/./mtab': Operation not permitted
cp: can't create symlink '/mnt/extsd/firmware_dump/etc/./rc.d/K80udev': Operation not permitted
```

**Causa:** FAT32 no soporta symlinks y `cp -Rp` intenta recrearlos.

**Solucion:** usar `cp -RpL` (la `L` dereferencia los enlaces y copia el contenido al que apuntan):

```sh
cp -RpL /etc/. /mnt/extsd/firmware_dump/etc/
```

---

## 3. `socat`: `__nanosleep_time64: symbol not found`

**Sintoma** en `debug1.log`:

```text
Error relocating /mnt/extsd/socat: __nanosleep_time64: symbol not found
Error relocating /mnt/extsd/socat: __gettimeofday_time64: symbol not found
Error relocating /mnt/extsd/socat: __localtime64: symbol not found
Error relocating /mnt/extsd/socat: __lstat_time64: symbol not found
```

**Causa:** el `socat` de OpenWrt 23.05 se compilo con musl que usa la ABI time64 (estructuras de tiempo de 64 bits). La musl del firmware (`/lib/ld-musl-armhf.so.1`) es mas antigua y solo tiene la ABI time32.

**Solucion:** no usar `socat`. Usar BusyBox estatico con `telnetd` ([`files/busybox_net`](../files/busybox_net)).

**Alternativas descartadas:**

| Intento | Motivo |
|---|---|
| `socat` OpenWrt 21.02 `arm_cortex-a7` | Sin time64 pero soft-float, interprete `/lib/ld-musl-arm.so.1` |
| `socat` Alpine 3.12 `armv7` | Interprete correcto pero necesita `libssl`/`libcrypto`/`libreadline` ausentes |

---

## 4. El puerto no responde aunque el log dice "ACTIVO"

**Sintoma:** `debug1.log` termina con `telnetd ACTIVO en puerto 23`, pero Tera Term no conecta.

**Causas posibles, en orden:**

1. **El PC no esta en la red correcta.** Si el WiFi del PC esta conectado a otra red (por ejemplo tu WiFi de casa), el ping a `192.168.10.1` falla. Verificalo:

   ```powershell
   Get-NetIPAddress -InterfaceIndex 16 -AddressFamily IPv4
   Get-NetConnectionProfile -InterfaceIndex 16 | Select Name
   ```

2. **La IP del equipo no es `192.168.10.1`.** Mira `firmware_dump/info.txt`, seccion `ifconfig`. El rango DHCP del firmware es `192.168.10.250-254`, asi que la pantalla suele ser `.1`, pero no es garantia.

3. **Estas probando desde WSL.** WSL2 va por NAT y no alcanza `192.168.10.x`. Usa Tera Term o `nc` de Windows.

4. **El demonio murio al salir el script.** Confirmalo dentro de la propia shell (si puedes entrar) o con el log.

---

## 5. `ping` funciona un rato y luego deja de funcionar

**Causa:** cambiaste de WiFi para tener internet y volver a escribir al asistente. Es normal: con la IP estatica `192.168.10.250` no hay internet.

**Solucion:** alterna entre la red de la pantalla (para probar) y tu WiFi normal (para escribir). Al volver, repon la IP estatica:

```powershell
netsh interface ip set address name="Wi-Fi" static 192.168.10.250 255.255.255.0 192.168.10.1
```

---

## 6. Windows: `Acceso denegado` al escribir el disco en crudo

**Sintoma:** al abrir `\\.\PhysicalDrive1` con `FileAccess.Write`:

```text
Excepción al llamar a "Open" con los argumentos "4":
"Acceso denegado a la ruta de acceso '\\.\PhysicalDrive1'."
```

**Diagnostico:** el proceso debe estar elevado. Verificalo dentro del script:

```powershell
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
$pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

**Solucion:** elevar con `Start-Process ... -Verb RunAs` y ademas desmontar el volumen con `FSCTL_DISMOUNT_VOLUME` antes de escribir. El script [`scripts/write_sd_windows.ps1`](../scripts/write_sd_windows.ps1) ya hace ambas cosas.

---

## 7. `diskpart: No se admite la operación en medios extraíbles`

**Sintoma:**

```text
Error del Servicio de disco virtual:
No se admite la operación en medios extraíbles.
```

**Causa:** `diskpart` no puede hacer `offline disk` / `clean` en discos USB extraíbles.

**Solucion:** no usar `diskpart`. Usar escritura raw con `FSCTL_DISMOUNT_VOLUME`, o usar Rufus en modo DD.

---

## 8. `wsl --mount` no funciona con la SD

**Sintoma:**

```text
Error: 0x80040315
Wsll/Service/AttachDisk/MountDisk/WSL_E_ELEVATION_NEEDED_TO_MOUNT_DISK
```

y, elevado:

```text
El sistema no puede encontrar el controlador especificado.
Error: 0x8007000f
```

**Causa:** WSL2 `wsl --mount` no admite discos USB extraíbles.

**Solucion:** escribir la imagen desde Windows (script provisto) o desde Linux con `dd`.

---

## 9. El `debug1` no se ejecuta por CRLF

**Sintoma:** el log no aparece o sale `^M: not found`.

**Solucion:**

```bash
sed -i 's/\r$//' debug1
sh -n debug1
```

Verificacion en Windows:

```powershell
$b=[IO.File]::ReadAllBytes("F:\debug1")
([regex]::Matches([Text.Encoding]::ASCII.GetString($b),"`r`n")).Count   # debe ser 0
```

---

## 10. `nc` desde WSL da `Connection timed out`

**Causa:** WSL2 usa NAT y no tiene ruta a la red `192.168.10.0/24`. El ping desde WSL tambien falla (100% packet loss) mientras que desde Windows funciona.

**Solucion:** usar Tera Term (TCP/IP) o `nc` nativo de Windows. No perder tiempo depurando el puerto desde WSL.

---

## 11. La shell conecta pero parece "no hacer nada"

Al conectar por Tera Term debes presionar **Enter** una o dos veces. El prompt puede ser:

```text
/ #
```

o:

```text
root@TinaLinux:~#
```

Si sale `login:`, escribe `root` y Enter. Si sale pantalla en blanco, presiona Enter.

Comandos de prueba:

```sh
whoami
cat /proc/mtd
```

---

## 12. Fecha 1970 en los logs

**Sintoma:** `Thu Jan 1 00:00:02 UTC 1970`.

**Causa:** el equipo no tiene RTC con bateria; al arrancar usa epoch. Es **normal** y no afecta al volcado.

---

## Arbol de decision rapido

```text
¿Existe debug1.log en la SD?
├── NO  -> problema 1 (SD superfloppy) o 9 (CRLF)
└── SÍ
    ├── ¿Aparece error "symbol not found"? -> problema 3 (usar busybox_net)
    ├── ¿Aparece "cp: can't create symlink"? -> problema 2 (cp -RpL)
    ├── ¿Dice "telnetd ACTIVO" pero no conecta? -> problema 4 / 5 / 10
    └── ¿Todo OK? -> ya tienes el firmware en firmware_dump/
```
