# 07 - Opciones desactivadas encontradas en el firmware

[English](07-disabled-features.md) · [Volver](../README.es.md)

**Keywords:** opciones desactivadas, funciones ocultas, adb ausente, telnetd desactivado, S50telnet, S40network, S50adb, hostapd, wpa_supplicant, udhcpd, configuracion UCI, device.xml, config_devmng.xml, DTB status disabled, flags de debug, panel de fabrica

Analisis del rootfs volcado de la M750 (`mtdblock2`, extraido en `m750root`) mas las variantes TF811/backup. **No se modifico nada** del firmware para hacer este informe.

---

## 1. Resumen ejecutivo

| Pregunta | Respuesta |
|---|---|
| ¿Hay configuracion UCI (`/etc/config/*`) que cambiar? | **No.** `/etc/config` no existe en este firmware. |
| ¿Hay servicios desactivados a proposito? | **Sí**, tres scripts empiezan con un `exit` suelto. |
| ¿Estan los binarios correspondientes? | **A medias.** Algunos sí, otros no. |
| ¿Se puede activar la shell root? | **Ya está hecho** con `/mnt/extsd/debug1` (ver doc 02). |
| ¿Se puede activar ADB? | **No sin añadir `adbd`**; el binario no existe. |
| ¿Se puede activar SSH? | **No**, no hay `sshd` ni `dropbear`. |
| ¿Se puede usar el WiFi? | Hay binarios y configuraciones, pero los arranques estan comentados. |
| ¿Hay un firewall que abrir? | **No.** No hay `iptables`, ni config de firewall, ni reglas DROP. |
| ¿Hay hardware desactivado? | **Sí**, el DTB tiene 48 nodos con `status = "disabled"`. |

Dato importante: `/etc/init.d/rc.final:15-34` ejecuta **todos** los scripts `/etc/init.d/S??*`, aunque no esten enlazados en `/etc/rc.d`. Que un script no este en `rc.d` **no** significa que se salte.

---

## 2. Scripts de inicio desactivados con `exit`

| Script | Linea | Codigo | Lo que haria si se activara |
|---|---:|---|---|
| `etc/init.d/S40network` | 5 | `exit` | `ifup -a`, `ifconfig eth0`, `udhcpc -b -R &` |
| `etc/init.d/S50telnet` | 5 | `exit` | `start-stop-daemon ... -x /usr/sbin/telnetd -- -F` |
| `etc/init.d/S50wifidaemon` | 5 | `exit` | `wifi_daemon`, `wifi -o sta` |
| `etc/init.d/S50adb` (solo variante backup) | 2 | `exit` | `setusbconfig adb`, `adbd > /dev/null &` |

Desactivados además, pero no funcionarian aunque se activaran:

| Elemento | Ubicacion | Problema |
|---|---|---|
| `webapp` | `S01app:93` (comentado) | Binario ausente |
| `log_guardian` | `S01app:94` (comentado) | Binario ausente |
| `hwclock -s` y ajuste de fecha | `S01app:96-100` (comentado) | El DTB tiene el RTC desactivado |
| Rol OTG `usb_host` | `S00mpp:12` (comentado) | Romperia el gadget USB/ADB |
| GPIO ACC-DET 239 | `S00mpp:19-20` (comentado) | Especifico de hardware |
| Sensores front/AHD | `S00mpp:7-8` | `FRONTSENSOR="none.ko"`, `AHDSENSOR="none.ko"` |
| Modulos WiFi antiguos | `rc.final:4-9`, `rc.modules:10-12` | Faltan los `.ko` |
| Consola serie | `etc/inittab:31` | `#ttyS0::respawn:/sbin/getty ...` comentado; bootargs con `console=` vacio |
| Auto-mount generico USB/SD | `usr/bin/hotplug.sh:2,41` | Bloque envuelto en `: <<'COMMENTBLOCK'` |

---

## 3. Binarios presentes vs. ausentes

### Presentes (se pueden lanzar)

```text
/bin/busybox                 v1.27.2, 87 symlinks
/sbin/ifconfig, route, udhcpc, getty, insmod, hwclock, syslogd
/usr/sbin/hostapd            AP WiFi
/usr/sbin/wpa_supplicant     STA / P2P
/usr/sbin/wpa_cli            control de wpa_supplicant
/usr/sbin/udhcpd             servidor DHCP
/usr/sbin/crond              cron (BusyBox)
/sbin/netifd, /sbin/ubusd    componentes OpenWrt, pero sin UCI
/usr/bin/setusbconfig        gadget USB: adb / mtp / uvc / uac1 / mass_storage / none
/usr/bin/sdvcam              app principal de camara, con muchas cadenas de test
/lib/modules/4.9.191/8733bs.ko  driver WiFi real
```

Applets compilados en BusyBox pero sin symlink: `ip`, `tftp`. Se llaman como `/bin/busybox ip addr`.

### Ausentes (no se pueden activar sin aportarlos)

```text
sshd, dropbear      -> no hay SSH
telnetd             -> S50telnet no puede funcionar tal cual
adbd                -> ADB imposible aunque device.xml diga adbEnable="1"
ftpd, tftpd, httpd  -> no hay servidor de archivos/HTTP en el rootfs
nc, wget, ftpget    -> solo en nuestro busybox_net externo de la SD
socat               -> solo en la SD
iptables, ebtables  -> no hay userspace de firewall
dbus-daemon         -> S50dbus existe pero no puede arrancar
wifi, wifi_daemon   -> S50wifidaemon no puede arrancar
webapp, log_guardian, ota_update, healthd, klogd
xradio_*.ko, bcmdhd.ko, 8723ds.ko, sunxi_usb_udc.ko, sunxi_usbc.ko
```

Nuestro ayudante externo `files/busybox_net` añade: `telnetd`, `telnet`, `nc`, `httpd`, `wget`, `ftpget`, `ftpput`, `ntpd`, `klogd`.

---

## 4. Flags de la interfaz (XML)

`data/res/config/device.xml`:

```text
8:  adbEnable="1"     <- ADB solicitado, pero falta adbd
25: flags="0"         <- flag generico apagado
38: devGpsUart="dev/ttyS1"   <- falta la barra inicial Y UART1 esta desactivado en el DTB
41: gpsSearch="0"     <- GPS apagado
42: radaSwitch="0"    <- radar apagado
```

`data/res/param/config_devmng.xml`:

```text
53: wifi_enable="1"
55: wifi_ssid_hide="0"
57: wifi_ap_ssid="M750-"
59: wifi_ap_password="12345678"
104: bFMSend="1"
105: bFMenable="0"       <- FM apagada (tambien en el DTB)
107: AUX_user="1"
108: AUX_enable="0"      <- AUX apagado
109: PBT_user="1"
110: PBT_enable="1"      <- Bluetooth clasico encendido
111: ble_user="0"
112: ble_enable="0"      <- BLE apagado
155: admin_sys_psd="1333"   <- password de administrador en texto plano
156: sys_psd="0000"
157: switch_sys_psd="0"     <- proteccion por password desactivada
```

`data/res/layout/home.xml:407-409`: un grupo de UI `test_board` esta comentado (panel oculto de fabrica/test).

`usr/bin/lt_image.sh:38-49`: la preparacion OTA borra deliberadamente `wpa_supplicant`, `udhcpd`, `hostapd`, `ping`, `ip`, `ifconfig` y `udhcpc` del rootfs de actualizacion.

---

## 5. WiFi: listo pero no lanzado

| Archivo | Estado |
|---|---|
| `etc/firmware/sta_ctrl.sh` | Comandos de `wpa_supplicant` y `udhcpc` comentados en todos los chips |
| `etc/firmware/direct_ctrl.sh` | Configuracion P2P comentada en todos los chips |
| `etc/firmware/ap_ctrl.sh` | Prepara `/var/run/hostapd`, pero nunca ejecuta `hostapd` |
| `etc/udhcpd.conf` | Rango AP `192.168.10.250-254`, interfaz `wlan0` |
| `etc/firmware/p2p_udhcpd.conf` | Rango P2P `192.168.50.20-254`, interfaz `p2p0` |
| `etc/wpa_supplicant.conf` | Credenciales de prueba `AWTest` / `1qaz@WSX` |
| `etc/firmware/ipscan.sh` | Escanea `192.168.10.250-254`; se llama en el backup, **no** en M750 |

Solo `8733bs.ko` existe realmente. Los scripts referencian `8723ds.ko`, `bcmdhd.ko` y `xradio_*.ko`, que faltan.

---

## 6. Hardware desactivado en el DTB

`dtc -I dtb -O dts dtb_descomprimido.bin` muestra **48 nodos** con `status = "disabled"`. Los mas relevantes:

```text
uart1@2500400      -> GPS / puerto serie secundario
spi-nand@0, spi1..3, spif0 -> SPI / NAND
twi0, twi1          -> I2C
fmsend              -> radio FM
rtc@7090000         -> sin reloj con bateria
da380, es8388       -> codecs de audio
dmic_*, daudio0_*   -> audio digital
gmac0               -> Ethernet
sensor0, sensor1, csi2, vinc00..vinc33  -> camaras
actuator0, flash0   -> enfoque/flash de camara
e907_rproc          -> coprocesador
```

USB **no** esta desactivado: `udc-controller@0x4100000` tiene `status = "okay"`.

Los bootargs en runtime tambien limitan la visibilidad:

```text
console=            loglevel=0
```

El DTS tiene otra cadena (`console=ttyS0`, `loglevel=8`), pero manda la command line real de arranque.

---

## 7. Que se puede activar sin regrabar

Todo esto es posible por el hook de la SD (`/mnt/extsd/debug1`) o escribiendo en el overlay `/overlay/upper`. Son **temporales salvo que se persistan en el overlay**.

```sh
# Shell remota / telnet (ya esta en nuestro debug1)
/mnt/extsd/busybox_net telnetd -p 2323 -l /bin/sh &

# Servidor HTTP del contenido de la SD
/mnt/extsd/busybox_net httpd -h /mnt/extsd -p 8080 &

# Herramientas de red ausentes en el rootfs
/mnt/extsd/busybox_net nc -l -p 5555 -e /bin/sh
/bin/busybox ip addr
/bin/busybox ip route

# NTP (el equipo no tiene RTC)
/mnt/extsd/busybox_net ntpd -N -p 0.openwrt.pool.ntp.org &

# AP WiFi manual (requiere que cargue 8733bs.ko)
cat > /tmp/hostapd.conf <<'EOF'
interface=wlan0
driver=nl80211
ssid=M750-TEST
hw_mode=g
channel=6
wpa=2
wpa_passphrase=12345678
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF
ifconfig wlan0 up
ifconfig wlan0 192.168.10.1 netmask 255.255.255.0
/usr/sbin/hostapd /tmp/hostapd.conf &
/usr/sbin/udhcpd /etc/udhcpd.conf &

# Flags de UI (la app puede revertirlos)
cp /data/res/config/device.xml /mnt/extsd/device.xml.bak
sed -i 's/gpsSearch="0"/gpsSearch="1"/' /data/res/config/device.xml
killall sdvcam; /usr/bin/sdvcam &
```

**Riesgos:** `telnetd -l /bin/sh` y `nc -e /bin/sh` dan root sin autenticacion. Los experimentos de WiFi pueden chocar con el AP de producto (`sdvcam` tambien gestiona `192.168.10.1`). GPS necesita el flag XML **y** UART1 activado en el DTB, ademas de una ruta valida en vez de `dev/ttyS1`. FM necesita `fmsend` activo en el DTB. BLE depende de `gocsdk` y de Bluetooth real.

---

## 8. Que requiere regrabar / recompilar

- `adbd`, `telnetd`, `sshd`/`dropbear` permanentes dentro del rootfs.
- `dbus-daemon`, `wifi`/`wifi_daemon`, `webapp`, `log_guardian`, `ota_update`, `klogd`.
- `iptables` / firewall.
- Modulos `.ko` adicionales o ausentes.
- Cambiar nodos del DTB (Ethernet, UART1, camaras, I2C, RTC, audio, e907).
- Cambiar bootargs (`console=`, `loglevel=`).

El rootfs base es un squashfs de solo lectura (`mtdblock2`), asi que los cambios persistentes van al overlay jffs2 (`/overlay/upper`, solo ~320 KB) o a una imagen `mtdblock2` reconstruida (ver doc 05).

---

## 9. Conclusion rapida

El firmware es un build **OpenWrt incompleto**: tiene scripts de inicio de OpenWrt pero no UCI, ni `procd`, ni `validate_data`, ni firewall, ni `/sbin/wifi`. Por eso la mayoria de las "opciones desactivadas" son scripts que no funcionarian aunque se descomentaran, porque faltan sus binarios.

Las palancas reales son:

1. El hook de la SD — ya funcionando, da root en cada arranque.
2. El `busybox_net` externo — añade temporalmente todas las herramientas de red que faltan.
3. El overlay — para sustituciones pequeñas de archivos de forma persistente.
4. Los flags XML — solo si la app los acepta y el hardware esta realmente habilitado.
5. Reconstruir `mtdblock2` + DTB — para cambios reales de funcionalidad.

---

## 10. Ejemplo practico: cambiar el SSID del AP

El XML es solo el valor por defecto. El **SSID real esta en `/data/param.bin`**, en slots de cadena de 64 bytes:

```text
offset 1880: Hunk125r          (nombre del equipo / BT)
offset 1944: M750BT_           (prefijo Bluetooth)
offset 2072: english           (idioma)
offset 2136: M750-60811d4b     <- SSID COMPLETO del AP (prefijo + sufijo MAC)
offset 2200: M750-             <- prefijo del SSID del AP
offset 2264: 12345678          <- password del AP
offset 2328: zlink             <- SSID de estacion
```

Por eso la red de fabrica sale como `M750-xxxx`: `sdvcam` toma el prefijo del offset 2200 y le añade los ultimos bytes de la MAC de `wlan0` (escritos en `/tmp/apmac.txt` por `etc/firmware/apmac.sh`).

Para poner un SSID exacto como `Hunk-125r` hay que parchear **los dos slots** 2136 y 2200, ademas de las dos claves del XML (`wifi_ap_ssid` y `wifiApSsid`). Usa [`files/debug1-wifi-ssid.sh`](../files/debug1-wifi-ssid.sh) con estos archivos en la raiz de la SD:

```text
F:\debug1                     <- el script de SSID renombrado a debug1
F:\param_hunk.bin             <- param.bin parcheado
F:\config_devmng_hunk.xml     <- XML parcheado
```

El script guarda `param.bin.bak` y `config_devmng.xml.bak` en la SD, copia los archivos a `/data` y `/overlay/upper/data`, vuelca `/tmp/apmac.txt` a `firmware_dump/` y crea `wifi_ssid.done`. Como `S01app` ejecuta `debug1` **antes** de arrancar `sdvcam`, la app lee los valores nuevos al iniciarse.

**Rollback:** restaura los `.bak` a sus nombres originales, borra `wifi_ssid.done` y arranca una vez.
