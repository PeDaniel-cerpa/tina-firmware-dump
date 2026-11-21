# 11 - Paso crítico: volcado UART de la Podofo A4628 abierta

[English](11-podofo-a4628-uart-dump.md) · [Volver](../README.es.md)

**Keywords:** Podofo A4628, volcado UART, ESP32-S3 USB-UART, consola U-Boot, error sf read, consola ttyS0, SPI NOR 16 MiB, py25q128ha, sun8iw21, mtd0..mtd7, respaldo firmware con dd, extracción squashfs, binwalk

Este es el **paso que inició toda la investigación**. El método principal de este repositorio (docs 01-07) volca el firmware por IP **sin abrir la pantalla**. Antes de que funcionara, el firmware que se analizó se obtuvo de una pantalla de moto **Podofo A4628 ya abierta**: entrando a U-Boot por UART, arrancando Linux con consola y copiando toda la flash SPI NOR de 16 MiB a una microSD.

> Alcance: este procedimiento **requiere abrir el equipo** y rompe el sellado IP67. Es el método de referencia/respaldo, no el método sin desarmar.

Notas de campo originales: `firmware-podofo-a4628.md` · Autor: Daniel · 21 nov 2026.

---

## 1. Equipo encontrado

| Dato | Valor |
|---|---|
| Equipo | Pantalla de moto Podofo A4628 con CarPlay |
| SoC | Allwinner sun8iw21 (familia V85x), 1 núcleo ARM @ 1008 MHz según U-Boot |
| RAM | 64 MiB DDR2 |
| Flash | SPI NOR de 16 MiB, py25q128ha (ID JEDEC `85 20 18`) |
| Bootloader | boot0 + U-Boot 2018.07 (Allwinner) |
| Sistema | Linux, rootfs squashfs de solo lectura |
| UART | 115200 baudios, 8N1, 3,3 V |

Tabla de particiones de `cat /proc/mtd`:

| MTD | Nombre | Offset | Tamaño (bytes) | Archivo |
|---|---|---|---|---|
| mtd0 | uboot | 0x000000 | 393216 | m0.bin |
| mtd1 | boot | 0x060000 | 2228224 | m1.bin |
| mtd2 | rootfs | 0x280000 | 13369344 | m2.bin |
| mtd3 | rootfs_data | 0xF40000 | 327680 | m3.bin |
| mtd4 | env | 0xF90000 | 131072 | m4.bin |
| mtd5 | bootlogo | 0xFB0000 | 131072 | m5.bin |
| mtd6 | private | 0xFD0000 | 65536 | m6.bin |
| mtd7 | UDISK | 0xFE0000 | 131072 | m7.bin |

Los tamaños suman `0x1000000` (16 MiB): las ocho particiones cubren toda la flash, incluidos boot0 y U-Boot.

---

## 2. Material

- ESP32-S3 N16R8 como puente USB-UART, cables Dupont y soldador para los pads.
- Multímetro.
- PC con Windows (Tera Term); Kali Linux para el análisis.
- microSDHC de **32 GB o menos**, en FAT **sin tabla de particiones** (superfloppy). Se usó una de 3,8 GiB.
- Alimentar la pantalla con su fuente normal de 12 V o una fuente estable. **Nunca alimentarla desde el adaptador USB-UART.**

---

## 3. Procedimiento

### 3.1 Localizar los pads UART

1. Abrir la pantalla (se pierde el sellado IP67: guardar y reponer la junta).
2. Con la pantalla encendida, medir el voltaje en reposo de cada pad candidato. Un TX en reposo está en alto; un RX suele tener pull-up (aquí, 3,2 V).
3. Un pad con 3,7 V supera lo que admite un GPIO del ESP32-S3: usar divisor de 1 kΩ y 10 kΩ, o no usarlo.
4. Conectar el GND del ESP32-S3 al GND de la pantalla **antes** que las señales. Nunca conectar el 3V3 ni el 5V del ESP a la pantalla.

Conexión final (cruzada):

| ESP32-S3 | Pantalla |
|---|---|
| GPIO18 (RX) | pad TX de la pantalla (el que mostró actividad) |
| GPIO17 (TX) | pad RX de la pantalla (3,2 V), con 1 kΩ en serie |
| GND | GND |

### 3.2 Medir la velocidad del UART

Un sketch del ESP32-S3 midió el ancho de cada pulso con el contador de ciclos de la CPU y armó un histograma mientras se cortaba y reconectaba la alimentación:

- Pulso dominante: 8,50 µs (3126 pulsos) = un bit.
- Los demás grupos eran múltiplos exactos: 17,25 µs, 26 µs y 34,5 µs.
- Velocidad: `1.000.000 / 8,6 ≈ 115200` baudios.

Un primer intento con `micros()` dio un valor falso de 500000 por estar en el límite de resolución del temporizador.

### 3.3 Puente USB-UART con el ESP32-S3 (sketch real usado)

Placa: **ESP32S3 Dev Module**, **USB CDC On Boot: Enabled**, puerto USB nativo (COM). Las credenciales WiFi se sustituyeron por marcadores de posición.

> **IMPORTANTE: usar solo el puerto serie USB (COM).** La parte WiFi/Telnet se conserva como referencia, pero **no funcionó de forma fiable**: Tera Term conectaba a la IP del ESP en el puerto 23, sin embargo los comandos escritos en el terminal no se mostraban (eco) ni llegaban correctamente a la consola. Todos los comandos de este volcado se enviaron por el COM de USB. No usar WiFi para este procedimiento.

```cpp
// Puente USB (COM) <-> UART para ESP32-S3 N16R8
// Pantalla TX -> GPIO18 (RX del ESP)
// ESP GPIO17 (TX) -> RX de la pantalla (con 1k en serie)
// GND del ESP -> GND de la pantalla
//
// SOLO USB SERIE (COM). El modo WiFi/Telnet se conserva como referencia, pero
// no funciono: Tera Term conectaba por WiFi, no mostraba los comandos
// escritos y la consola no respondia de forma fiable. Usar siempre el COM.
//
// IMPORTANTE: sustituir los valores de WiFi SOLO si se quiere experimentar.
// No son las credenciales reales y no son necesarias para el volcado.

#include <WiFi.h>

// --- CONFIGURACION WIFI (NO USAR; solo referencia) ---
const char* ssid     = "TU_WIFI_SSID";
const char* password = "TU_WIFI_PASSWORD";
const uint16_t PUERTO_TCP = 23;

WiFiServer server(PUERTO_TCP);
WiFiClient client;

#define PIN_RX   18
#define PIN_TX   17
#define PIN_BOOT 0

const unsigned long BAUDS[] = {115200, 921600, 1500000, 57600, 230400, 9600};
const int N_BAUDS = sizeof(BAUDS) / sizeof(BAUDS[0]);
int idx = 0;                      // 115200 por defecto
uint8_t buf[512];
bool autoStopUboot = true;        // se apaga al recibir cualquier tecla desde el PC

void abrirUart() {
  Serial1.end();
  Serial1.setRxBufferSize(16384);
  Serial1.begin(BAUDS[idx], SERIAL_8N1, PIN_RX, PIN_TX);
}

void logDual(const char* msg) {
  Serial.print(msg);
  if (client && client.connected()) client.print(msg);
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_BOOT, INPUT_PULLUP);
  abrirUart();

  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);
  unsigned long inicio = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - inicio < 15000) delay(250);
  if (WiFi.status() == WL_CONNECTED) {
    server.begin();
    server.setNoDelay(true);
  }
}

void loop() {
  static bool conectadoUSB = false;
  if (Serial && !conectadoUSB) {
    conectadoUSB = true;
    delay(200);
    Serial.printf("\r\n[UART a %lu baudios - AutoStop U-Boot ACTIVO]\r\n", BAUDS[idx]);
    if (WiFi.status() == WL_CONNECTED)
      Serial.printf("[WiFi LISTO -> %s:%d] (NO USAR: solo COM)\r\n",
                    WiFi.localIP().toString().c_str(), PUERTO_TCP);
    else
      Serial.println("[WiFi ERROR -> no se pudo conectar; usar COM]");
  }
  if (!Serial) conectadoUSB = false;

  if (server.hasClient()) {
    if (!client || !client.connected()) {
      if (client) client.stop();
      client = server.available();
      client.setNoDelay(true);
      client.printf("\r\n[Conectado por WiFi | UART a %lu baudios | AutoStop: %s]\r\n",
                    BAUDS[idx], autoStopUboot ? "ACTIVO" : "DETENIDO");
    } else {
      WiFiClient rechazo = server.available();
      rechazo.println("\r\n[Ocupado: ya hay otra sesion conectada]");
      rechazo.stop();
    }
  }

  // Ráfaga cada 10 ms para atrapar U-Boot antes de "Starting kernel"
  static unsigned long tBurst = 0;
  if (autoStopUboot && (millis() - tBurst >= 10)) {
    Serial1.write(' ');
    tBurst = millis();
  }

  // UART -> PC (USB y WiFi)
  int n = Serial1.available();
  if (n > 0) {
    n = Serial1.readBytes(buf, min(n, (int)sizeof(buf)));
    Serial.write(buf, n);
    if (client && client.connected()) client.write(buf, n);
  }

  // PC (USB) -> UART
  n = Serial.available();
  if (n > 0) {
    if (autoStopUboot) {
      autoStopUboot = false;
      logDual("\r\n[AutoStop detenido - Consola libre]\r\n");
    }
    n = Serial.readBytes(buf, min(n, (int)sizeof(buf)));
    Serial1.write(buf, n);
  }

  // PC (WiFi) -> UART (solo referencia)
  if (client && client.connected()) {
    n = client.available();
    if (n > 0) {
      if (autoStopUboot) {
        autoStopUboot = false;
        logDual("\r\n[AutoStop detenido - Consola libre]\r\n");
      }
      n = client.read(buf, min(n, (int)sizeof(buf)));
      Serial1.write(buf, n);
    }
  }

  // BOOT: cambiar velocidad con pulsación larga (1,5 s)
  static unsigned long tPress = 0;
  static bool cambiado = false;
  if (digitalRead(PIN_BOOT) == LOW) {
    if (tPress == 0) tPress = millis();
    if (!cambiado && millis() - tPress >= 1500) {
      cambiado = true;
      idx = (idx + 1) % N_BAUDS;
      abrirUart();
      char msg[64];
      snprintf(msg, sizeof(msg), "\r\n[UART a %lu baudios]\r\n", BAUDS[idx]);
      logDual(msg);
    }
  } else {
    tPress = 0;
    cambiado = false;
  }
}
```

El sketch sanitizado también está disponible como [`files/esp32_uart_bridge.ino`](../files/esp32_uart_bridge.ino).

Notas:

- En Tera Term: **Serial port**, **Flow control: none**. DTR/RTS pueden arrastrar GPIO0 (BOOT) y cambiar la velocidad si el sketch la cambia con el botón.
- Abrir el terminal antes de encender la pantalla para capturar todo el log de arranque.
- Activar el log a archivo en el terminal.
- El sketch imprime `[UART a 115200 baudios - AutoStop U-Boot ACTIVO]` al abrir el USB.

### 3.4 Entrar a la consola de U-Boot

1. Con el puerto COM de USB abierto en Tera Term, cortar y volver a conectar la alimentación.
2. El sketch envía un espacio cada **10 ms** (`autoStopUboot`) hasta que llega la primera tecla desde el PC. Esa ráfaga interrumpe el autoboot aunque `bootdelay=0`. En cuanto escribes el primer carácter, AutoStop se apaga y la consola queda libre.
3. Aparece el prompt `=>`. Comandos de solo lectura: `help`, `printenv`, `bdinfo`.

Alternativa sin el sketch de ráfaga: *Control → Broadcast command* de Tera Term con una ráfaga como `ssssssssssssssss`, Enter key = Enter, fin de línea CR, History activado, *Send to this process only* activado, **Realtime mode desactivado**, y pulsar **Submit** al conectar la alimentación. Si el sistema arranca normalmente, cortar y repetir.

Datos relevantes de `printenv`:

- `bootcmd=run setargs_nor boot_normal` (arranca desde NOR).
- `console=${console}` sin definir y `loglevel=0`: tras `Starting kernel` la UART queda muda.
- `rotpk_status=0`, `verify=N`: sin arranque seguro con firma.

### 3.5 Arrancar Linux con consola — el paso clave

1. Cortar la alimentación de la pantalla por completo durante **10 segundos** y volver a conectarla.
2. Interrumpir el autoboot otra vez y escribir directamente, **sin ejecutar ningún comando `sf` antes**:

```text
setenv console ttyS0,115200
setenv loglevel 7
boot
```

3. Aparece el log del kernel y se llega al prompt `/ #`.

Los cambios con `setenv` solo viven en RAM y se pierden al reiniciar. **No ejecutar `saveenv`.**

### 3.6 Montar la tarjeta

Escribir **un comando por línea**: la consola serie corta las líneas largas al pegarlas.

```text
cat /proc/mtd
cat /proc/mounts
```

El rootfs es squashfs de solo lectura, así que `mkdir` falla con `Read-only file system`. Montar la tarjeta sobre la carpeta existente `/tmp`:

```text
mount -t vfat /dev/mmcblk0 /tmp
df /tmp
```

La tarjeta no tiene tabla de particiones, por eso es `/dev/mmcblk0` y no `/dev/mmcblk0p1`. Si un segundo `mount` da `Resource busy`, ya está montada: comprobar con `cat /proc/mounts`.

### 3.7 Copiar las particiones

```text
cd /tmp
dd if=/dev/mtd0 of=m0.bin bs=64k
dd if=/dev/mtd1 of=m1.bin bs=64k
dd if=/dev/mtd2 of=m2.bin bs=64k
dd if=/dev/mtd3 of=m3.bin bs=64k
dd if=/dev/mtd4 of=m4.bin bs=64k
dd if=/dev/mtd5 of=m5.bin bs=64k
dd if=/dev/mtd6 of=m6.bin bs=64k
dd if=/dev/mtd7 of=m7.bin bs=64k
sync
ls -l
```

Los tamaños deben coincidir con la sección 1.

### 3.8 Verificar desde la pantalla

```text
sync
echo 3 > /proc/sys/vm/drop_caches
cmp /dev/mtd0 m0.bin && echo OK0
md5sum /dev/mtd0 m0.bin
```

Repetir para mtd1, mtd2, mtd4, mtd5 y mtd6: deben coincidir exactamente. En mtd3 (`rootfs_data`) y mtd7 (`UDISK`) una diferencia pequeña es normal, porque el sistema escribe ahí mientras corre. Ejemplo real: mtd0 y m0.bin dieron `7465b41e575a08dfd9063e2192f4b89b`.

Terminar con:

```text
cd /
umount /tmp
```

Cortar la alimentación antes de sacar la tarjeta.

### 3.9 Unir y analizar en el PC

Unir las partes en orden (Windows `cmd`, en la carpeta de la tarjeta):

```text
copy /b m0.bin+m1.bin+m2.bin+m3.bin+m4.bin+m5.bin+m6.bin+m7.bin podofo_full.bin
```

Comprobaciones:

- `podofo_full.bin` debe medir exactamente **16777216 bytes**.
- El squashfs empieza en `0x280000` con `hsqs`: `xxd -s 0x280000 -l 4 podofo_full.bin` (Kali).
- Guardar el SHA256 de la imagen completa y de cada parte.

Análisis en Kali (sobre una copia, `chmod 444 podofo_full.bin`):

```sh
sudo apt install -y squashfs-tools binwalk abootimg
sudo unsquashfs -d rootfs m2.bin
binwalk podofo_full.bin
```

---

## 4. Lo que no funcionó (y por qué)

| Problema | Causa probable | Solución |
|---|---|---|
| `sunxi_card0_probe: Card did not respond to voltage select` | Tarjeta mal insertada o no compatible | Reinsertar con la pantalla apagada; SDHC ≤ 32 GB |
| `Unknown partition table type 0` | Tarjeta FAT sin tabla MBR | Usar partición 0 en U-Boot (`mmc 0:0`) o reformatear con MBR |
| `sf read` → `Read: ERROR -1`, `rx wait_dma_recv_over fail`, `cpu receive data time out` | El controlador SPI de este U-Boot no completa lecturas | No usar `sf`; copiar desde Linux |
| `boot` tras errores de `sf` termina en `undefined instruction` en `0x40008000` | Bus SPI trabado, kernel no leído | Cortar alimentación 10 s y repetir sin ningún comando `sf` |
| `mkdir: Read-only file system` | rootfs es squashfs | Montar la tarjeta sobre `/tmp` |
| `mount: Resource busy` | Tarjeta ya montada | Revisar `cat /proc/mounts` |
| Comandos pegados que salen cortados | La consola serie trunca líneas largas | Escribir un comando por línea |
| Tera Term cambió la velocidad del puente | DTR/RTS tocaron el pin BOOT | Flow control: none; pulsación larga para cambiar velocidad |
| Tera Term conecta por WiFi pero no muestra ni hace eco de los comandos escritos | El puente WiFi/Telnet del ESP no es fiable para la consola | **Usar solo el puerto COM de USB**; WiFi queda como referencia |

---

## 5. Precauciones

- Todo el proceso es de **solo lectura** sobre la flash. Nunca ejecutar `sf write`, `sf erase`, `erase`, `protect`, `saveenv`, `efex`, `fastboot`, `flash_erase`, `flashcp` ni `dd of=/dev/mtd...`.
- Mantener la UART a 3,3 V; no alimentar la pantalla desde el adaptador USB-UART.
- `private`, `rootfs_data` y `UDISK` pueden contener datos de emparejamiento: revisar antes de compartirlos.
- El firmware tiene derechos de autor: la copia es para respaldo personal.
- Guardar la imagen en dos sitios con su SHA256. Restaurarla exige programar la flash (pinza SOIC8 y programador) y puede dejar la pantalla inservible si se hace mal.
- Alternativa no necesaria aquí: leer la flash con pinza SOIC8 y el ESP32-S3 por SPI con la pantalla sin alimentación.

---

## 6. Registro de verificación

| Archivo | Tamaño esperado | MD5 en la pantalla | MD5 en el PC |
|---|---|---|---|
| m0.bin (uboot) | 393216 | `7465b41e575a08dfd9063e2192f4b89b` | — |
| m1.bin (boot) | 2228224 | anotado durante el volcado | — |
| m2.bin (rootfs) | 13369344 | anotado durante el volcado | — |
| m3.bin (rootfs_data) | 327680 | puede variar | — |
| m4.bin (env) | 131072 | anotado durante el volcado | — |
| m5.bin (bootlogo) | 131072 | anotado durante el volcado | — |
| m6.bin (private) | 65536 | anotado durante el volcado | — |
| m7.bin (UDISK) | 131072 | puede variar | — |
| podofo_full.bin | 16777216 | no aplica | SHA256 anotado con el volcado |

---

## 7. Por qué este paso fue crítico

Todos los resultados posteriores de este repositorio dependen del `m2.bin` / rootfs obtenido aquí:

- el hook `S01app` y el método de SD sin desarmar (docs 01-03),
- la auditoría de funciones desactivadas (doc 07),
- el recoloreado de la interfaz y el trabajo con `image.bin.lzma` (docs 08-09),
- el diagnóstico de whiteouts del overlay (doc 10).

Sin este volcado UART no habría firmware que analizar ni forma de diseñar el método basado en SD.
