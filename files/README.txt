COMO ENTRAR POR IP EN LA PANTALLA TF811 (Allwinner / Tina Linux)
================================================================

ARCHIVOS QUE HAY EN ESTA CARPETA
--------------------------------
  debug1   -> script que el firmware ejecuta como root al arrancar
  socat    -> servidor TCP armhf (musl) para obtener shell interactiva


PREPARACION DE LA MICROSD
-------------------------
1) Formatea una microSD en FAT32 (MBR, no GPT).
2) Copia los DOS archivos "debug1" y "socat" a la RAIZ de la SD.
   Importante: el nombre debe ser exactamente "debug1" (sin extension).
3) Si editas debug1 en Windows, guardalo con saltos de linea UNIX (LF),
   no CRLF. En Linux:  sed -i 's/\r$//' debug1

Por que funciona: /etc/init.d/S01app monta /dev/mmcblk0(p1) en /mnt/extsd
y hace:  if [ -f /mnt/extsd/debug1 ]; then /mnt/extsd/debug1; fi
=> se ejecuta como root sin desarmar y sin regrabar el firmware.


CONEXION
--------
- La pantalla levanta un AP WiFi con SSID "TF811-xxxx" y clave "12345678".
  Conecta tu PC a esa red y ponle IP fija 192.168.10.250
  (mascara 255.255.255.0, gateway 192.168.10.1).
- Si la pantalla esta en modo station (conectada a tu WiFi), la IP sera
  otra: la encuentras en el archivo firmware_dump/info.txt de la SD
  (seccion "ifconfig").

Procedimiento:
  1) SD puesta, enciende la pantalla y espera ~30-40 s.
  2) En el PC:  nc 192.168.10.1 4444
     (o:  nc <IP_DE_LA_PANTALLA> 4444 )
  3) Debe aparecer un prompt root. Si no conecta, revisa
     /mnt/extsd/debug1.log en la SD.


QUE DEJA EL SCRIPT EN LA SD
---------------------------
  /debug1.log                  -> log de ejecucion
  /firmware_dump/info.txt      -> mtd, particiones, mounts, ifconfig, route
  /firmware_dump/mtdblockN.bin -> volcado de cada particion (firmware)
  /firmware_dump/etc/          -> copia de /etc
  /firmware_dump/overlay/      -> copia del overlay (cambios del usuario)
  /firmware_dump/data/         -> copia de /data (configuracion de la app)

Saca la SD y leela en el PC para obtener el firmware completo.


NOTAS
-----
- socat es un binario ARM EABI hard-float (interprete
  /lib/ld-musl-armhf.so.1), compatible con la libc de este firmware.
  No necesita librerias adicionales: usa las del propio equipo.
- El script termina rapido y no bloquea el arranque: socat queda en
  segundo plano escuchando el puerto 4444.
- Para dejar el acceso permanente sin la SD, una vez dentro puedes copiar
  socat a /usr/bin y anadir su linea a /etc/init.d/rc.final (sobre overlay).
- Si prefieres no usar socat, el volcado a SD ya se hace igual: las
  particiones quedan en /firmware_dump/ aunque no haya red.
