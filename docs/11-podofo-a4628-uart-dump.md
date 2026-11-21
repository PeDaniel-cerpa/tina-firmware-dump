# 11 - Critical baseline: UART dump of the opened Podofo A4628

[Español](11-volcado-podofo-a4628-uart.es.md) · [Back](../README.md)

**Keywords:** Podofo A4628, UART dump, ESP32-S3 USB-UART, U-Boot console, sf read error, ttyS0 console, SPI NOR 16 MiB, py25q128ha, sun8iw21, mtd0..mtd7, dd firmware backup, squashfs extraction, binwalk

This is the **step that started the whole investigation**. The main method of this repository (docs 01-07) dumps the firmware over IP **without opening the screen**. Before that worked, the firmware used for analysis was obtained from an already-opened **Podofo A4628** motorcycle display by entering U-Boot over UART, booting Linux with a console, and copying the whole 16 MiB SPI NOR to a microSD.

> Scope: this procedure **requires opening the unit** and breaks the IP67 seal. It is the reference/fallback method, not the no-teardown method.

Original field notes: `firmware-podofo-a4628.md` · Author: Daniel · 21 Nov 2026.

---

## 1. Hardware found

| Item | Value |
|---|---|
| Device | Podofo A4628 motorcycle CarPlay display |
| SoC | Allwinner sun8iw21 (V85x family), 1 ARM core @ 1008 MHz per U-Boot |
| RAM | 64 MiB DDR2 |
| Flash | 16 MiB SPI NOR, py25q128ha (JEDEC ID `85 20 18`) |
| Bootloader | boot0 + U-Boot 2018.07 (Allwinner) |
| OS | Linux, read-only squashfs rootfs |
| UART | 115200 baud, 8N1, 3.3 V |

Partition table from `cat /proc/mtd`:

| MTD | Name | Offset | Size (bytes) | File |
|---|---|---|---|---|
| mtd0 | uboot | 0x000000 | 393216 | m0.bin |
| mtd1 | boot | 0x060000 | 2228224 | m1.bin |
| mtd2 | rootfs | 0x280000 | 13369344 | m2.bin |
| mtd3 | rootfs_data | 0xF40000 | 327680 | m3.bin |
| mtd4 | env | 0xF90000 | 131072 | m4.bin |
| mtd5 | bootlogo | 0xFB0000 | 131072 | m5.bin |
| mtd6 | private | 0xFD0000 | 65536 | m6.bin |
| mtd7 | UDISK | 0xFE0000 | 131072 | m7.bin |

The sizes add up to `0x1000000` (16 MiB): all eight partitions cover the whole flash, including boot0 and U-Boot.

---

## 2. Materials

- ESP32-S3 N16R8 used as USB-UART bridge, Dupont wires and solder for the pads.
- Multimeter.
- PC with Windows (Tera Term); Kali Linux for analysis.
- microSDHC **32 GB or less**, FAT with **no partition table** (superfloppy). A 3.8 GiB card was used.
- Power the display from its normal 12 V supply or a stable bench supply. **Never power it from the USB-UART adapter.**

---

## 3. Procedure

### 3.1 Find the UART pads

1. Open the display (the IP67 seal is lost: preserve and replace the gasket).
2. With the unit on, measure the idle voltage of each candidate pad. An idle TX sits high; an RX usually has a pull-up (here, 3.2 V).
3. A pad at 3.7 V is above what an ESP32-S3 GPIO tolerates: use a 1 kΩ / 10 kΩ divider, or do not use it.
4. Connect ESP32-S3 GND to display GND **before** the signal lines. Never connect the ESP's 3V3 or 5V to the display.

Final crossover wiring:

| ESP32-S3 | Display |
|---|---|
| GPIO18 (RX) | display TX pad (the active one) |
| GPIO17 (TX) | display RX pad (3.2 V), with 1 kΩ in series |
| GND | GND |

### 3.2 Measure the baud rate

An ESP32-S3 sketch measured each pulse width with the CPU cycle counter and built a histogram while power-cycling the display:

- Dominant pulse: 8.50 µs (3126 pulses) = one bit.
- Other groups were exact multiples: 17.25 µs, 26 µs, 34.5 µs.
- Baud rate: `1,000,000 / 8.6 ≈ 115200`.

A first attempt using `micros()` returned a false 500000 because it was at the timer resolution limit.

### 3.3 ESP32-S3 USB-UART bridge (actual sketch used)

Board: **ESP32S3 Dev Module**, **USB CDC On Boot: Enabled**, native USB port (COM). Credentials are replaced with placeholders.

> **IMPORTANT — use USB serial (COM) only.** The WiFi/Telnet part is kept for reference, but it did **not** work reliably: Tera Term connected to the ESP's IP on port 23, yet the commands typed in the terminal were not echoed back and did not reach the console correctly. All commands in this dump were sent through the USB COM port. Do not use WiFi for this procedure.

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

The sanitized sketch is also available as [`files/esp32_uart_bridge.ino`](../files/esp32_uart_bridge.ino).

Notes:

- In Tera Term: **Serial port**, **Flow control: none**. DTR/RTS can drag GPIO0 (BOOT) and change the baud rate if the sketch changes it via the button.
- Open the terminal before powering the display so the full boot log is captured.
- Enable terminal logging to file.
- The sketch prints `[UART a 115200 baudios - AutoStop U-Boot ACTIVO]` when USB is opened.

### 3.4 Enter the U-Boot console

1. With the USB COM port open in Tera Term, power-cycle the display.
2. The sketch sends a space every **10 ms** (`autoStopUboot`) until the first key arrives from the PC. That burst interrupts autoboot reliably even though `bootdelay=0`. As soon as you type the first character, AutoStop turns off and the console is free.
3. The `=>` prompt appears. Read-only commands: `help`, `printenv`, `bdinfo`.

Alternative without the auto-burst sketch: Tera Term *Control → Broadcast command* with a burst such as `ssssssssssssssss`, Enter key = Enter, line ending CR, History on, *Send to this process only* on, **Realtime mode off**, then **Submit** while applying power. If normal boot wins, cut power and repeat.

Relevant `printenv` values:

- `bootcmd=run setargs_nor boot_normal` (boots from NOR flash).
- `console=${console}` undefined and `loglevel=0`: after `Starting kernel` the UART goes silent.
- `rotpk_status=0`, `verify=N`: no signed/secure boot.

### 3.5 Boot Linux with a console — the key step

1. Cut display power completely for **10 seconds**, then reconnect.
2. Interrupt autoboot again and type directly, **without running any `sf` command first**:

```text
setenv console ttyS0,115200
setenv loglevel 7
boot
```

3. The kernel log appears and the Linux prompt `/ #` is reached.

`setenv` changes live only in RAM and are lost on reboot. **Do not run `saveenv`.**

### 3.6 Mount the SD card

Write **one command per line**: the serial console truncates long pasted lines.

```text
cat /proc/mtd
cat /proc/mounts
```

The rootfs is read-only squashfs, so `mkdir` fails with `Read-only file system`. Mount the card on the existing `/tmp` directory:

```text
mount -t vfat /dev/mmcblk0 /tmp
df /tmp
```

The card has no partition table, so it is `/dev/mmcblk0`, not `/dev/mmcblk0p1`. If a second `mount` reports `Resource busy`, it is already mounted: check `cat /proc/mounts`.

### 3.7 Copy the partitions

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

The sizes must match section 1.

### 3.8 Verify on the device

```text
sync
echo 3 > /proc/sys/vm/drop_caches
cmp /dev/mtd0 m0.bin && echo OK0
md5sum /dev/mtd0 m0.bin
```

Repeat for mtd1, mtd2, mtd4, mtd5 and mtd6: they must match exactly. Small differences in mtd3 (`rootfs_data`) and mtd7 (`UDISK`) are normal because the system writes there while running. Real example: mtd0 and m0.bin both gave `7465b41e575a08dfd9063e2192f4b89b`.

Finish with:

```text
cd /
umount /tmp
```

Power off before removing the card.

### 3.9 Join and analyse on the PC

Join the parts in order (Windows `cmd`, in the card folder):

```text
copy /b m0.bin+m1.bin+m2.bin+m3.bin+m4.bin+m5.bin+m6.bin+m7.bin podofo_full.bin
```

Checks:

- `podofo_full.bin` must be exactly **16777216 bytes**.
- The squashfs starts at `0x280000` with `hsqs`: `xxd -s 0x280000 -l 4 podofo_full.bin` (Kali).
- Save the SHA256 of the full image and of each part.

Analysis on Kali (work on a copy; `chmod 444 podofo_full.bin`):

```sh
sudo apt install -y squashfs-tools binwalk abootimg
sudo unsquashfs -d rootfs m2.bin
binwalk podofo_full.bin
```

---

## 4. What failed, and why

| Problem | Probable cause | Fix |
|---|---|---|
| `sunxi_card0_probe: Card did not respond to voltage select` | Card badly inserted or incompatible | Reinsert with the unit off; use SDHC ≤ 32 GB |
| `Unknown partition table type 0` | Card is FAT with no MBR | Use partition 0 in U-Boot (`mmc 0:0`), or reformat with MBR |
| `sf read` → `Read: ERROR -1`, `rx wait_dma_recv_over fail`, `cpu receive data time out` | This U-Boot SPI driver never completes reads | Do **not** use `sf`; copy from Linux |
| `boot` after `sf` errors ends in `undefined instruction` at `0x40008000` | SPI bus left stuck, kernel not read | Cut power 10 s and repeat with **no** `sf` command |
| `mkdir: Read-only file system` | rootfs is squashfs | Mount the card over `/tmp` |
| `mount: Resource busy` | Card already mounted | Check `cat /proc/mounts` |
| Pasted commands arrive truncated | Serial console truncates long lines | Write one command per line |
| Tera Term changed the bridge baud rate | DTR/RTS touched the BOOT pin | Flow control: none; long press to change speed |
| Tera Term connects over WiFi but typed commands are not shown or echoed | ESP WiFi/Telnet bridge unreliable for console I/O | **Use the USB COM port only**; WiFi is kept as reference only |

---

## 5. Precautions

- This is **read-only** with respect to the flash. Never run `sf write`, `sf erase`, `erase`, `protect`, `saveenv`, `efex`, `fastboot`, `flash_erase`, `flashcp` or `dd of=/dev/mtd...`.
- Keep the UART at 3.3 V; do not power the display from the USB-UART adapter.
- `private`, `rootfs_data` and `UDISK` may hold pairing data and settings: review before sharing.
- The firmware is copyrighted; this copy is for personal backup.
- Store the image in two places with its SHA256. Restoring requires programming the flash (SOIC8 clip + programmer) and can brick the unit if done badly.
- Alternative not needed here: read the flash directly with a SOIC8 clip and the ESP32-S3 over SPI with the display unpowered.

---

## 6. Verification record

| File | Expected size | MD5 on display | MD5 on PC |
|---|---|---|---|
| m0.bin (uboot) | 393216 | `7465b41e575a08dfd9063e2192f4b89b` | — |
| m1.bin (boot) | 2228224 | recorded during the dump | — |
| m2.bin (rootfs) | 13369344 | recorded during the dump | — |
| m3.bin (rootfs_data) | 327680 | may vary | — |
| m4.bin (env) | 131072 | recorded during the dump | — |
| m5.bin (bootlogo) | 131072 | recorded during the dump | — |
| m6.bin (private) | 65536 | recorded during the dump | — |
| m7.bin (UDISK) | 131072 | may vary | — |
| podofo_full.bin | 16777216 | n/a | SHA256 recorded with the dump |

---

## 7. Why this step was critical

Every later result in this repository depends on the `m2.bin` / rootfs obtained here:

- the `S01app` boot hook and the no-teardown SD method (docs 01-03),
- the disabled-feature audit (doc 07),
- the UI recolouring and `image.bin.lzma` work (docs 08-09),
- the overlay whiteout diagnosis (doc 10).

Without this UART dump, there would have been no firmware to analyse and no way to design the SD-based method.
