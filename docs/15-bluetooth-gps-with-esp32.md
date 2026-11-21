# 15 - Can an ESP32 send GPS data over Bluetooth?

[Español](15-gps-por-bluetooth-con-esp32.es.md) · [Back](../README.md)

**Keywords:** ESP32 GPS, Bluetooth SPP GPS, NMEA injection, devBtUart, rf_serial, ttyS0, ttyS1, UART1, phone_gps_info, CarPlay GPS, Zlink

**Short answer:** **not directly over Bluetooth SPP.** The firmware has no generic "Bluetooth GPS input". It reads NMEA from a **serial device** configured by `devGpsUart`. An ESP32 can still do the job, but it should output **NMEA over UART TTL** into one of the screen's serial ports. Two practical routes exist, plus a speculative Bluetooth one.

---

## 1. What the firmware actually supports

| Evidence | Conclusion |
|---|---|
| `device.xml`: `devGpsUart="dev/ttyS1"` | The GPS manager reads a **UART device path** |
| `config_devmng.xml`: `gps_baud="9600"` | It expects 9600 8N1 NMEA |
| `libltcdr.so`: `LT_GPSMNG_Init/Start/GetData/Search`, `OpenSerialPort`, `CloseSerialPort` | GPS comes from a serial port, not from Bluetooth |
| `libCoreUtils.so`: `NMEAParse`, `SerialStreamCreate`, `Opening serial port '%s'` | Standard NMEA parser fed by a serial stream |
| `device.xml`: `devBtUart="dev/rf_serial"` | A Bluetooth UART path **exists as a config key**, but... |
| No init script creates `/dev/rf_serial` or starts `rfcomm` | ...there is no RFCOMM/SPP node by default |
| DTB node `btlpm` is `status = "disabled"` | Bluetooth power management is disabled too |
| `libzlink-main.so`: `phone_gps_info`, `mirror_phone_gps_info_parse` | Phone GPS exists, but only inside the proprietary Zlink / CarPlay / Android Auto protocol |

So there is **no evidence of a Bluetooth SPP → NMEA parser path**. The `phone_gps_info` messages are CarPlay/AA protobuf data from a paired phone; an ESP32 cannot simply impersonate that without reimplementing a large proprietary stack.

---

## 2. Route A (design-correct): ESP32 → UART1 (`ttyS1`)

This is what the firmware was written for.

1. Wire the ESP32 TX to the screen's `PE7` (UART1_RX), GND to GND.
2. ESP32 outputs NMEA at **9600 8N1**.
3. Patch the firmware:
   - enable `uart1@2500400` in the DTB (`status = "okay"`, PE6/PE7 mux 6),
   - `devGpsUart="/dev/ttyS1"`,
   - `gps_info="1"`,
   - `gps_baud="9600"`.

Pros: matches the original design. Cons: still requires finding and patching the real DTB location (doc 12/14).

---

## 3. Route B (shortcut): ESP32 → existing UART0 (`ttyS0`)

The UART0 pads are the ones we already used for the UART dump, so they are physically accessible and the driver is active. `ttyS0` exists even though the runtime cmdline has `console=` empty.

1. Wire ESP32 TX to the **UART0 RX pad** (the pad we connected as "pantalla RX" in doc 11).
2. Output NMEA at **115200** (or run `stty -F /dev/ttyS0 9600` and use 9600).
3. Patch only the config:
   - `devGpsUart="/dev/ttyS0"`
   - `gps_baud="115200"` (or 9600 after `stty`)
   - `gps_info="1"`
4. Check `/etc/inittab`: it has `/dev/console::respawn:-/bin/sh` and the `ttyS0` getty is commented. If the shell ends up attached to `ttyS0` and eats the NMEA bytes, remove that respawn line or redirect `/dev/console` elsewhere.

Pros: **no DTB change needed**. Cons: you lose/contend with the debug console on those pads; must verify on the live unit that nothing else reads `ttyS0`.

---

## 4. Route C (speculative): ESP32 as Bluetooth SPP

In theory: pair the ESP32 with the screen as a serial-port profile device, bind an RFCOMM node as `/dev/rf_serial`, then set `devGpsUart="/dev/rf_serial"`.

Why this is **not recommended**:

- no init script creates that node;
- `btlpm` is disabled in the DTB;
- the screen's Bluetooth is used by Zlink for CarPlay/Android Auto handshake, so pairing an ESP32 may conflict;
- it has never been verified on real hardware.

Only attempt this after getting a live root shell and confirming `rfcomm` tools and a working Bluetooth stack exist. Treat it as an experiment, not a documented procedure.

---

## 5. Minimal ESP32 bridge sketch (routes A/B)

```cpp
// GPS module TX -> ESP32 RX (GPIO16)
// ESP32 TX (GPIO17) -> screen RX pad (PE7 for ttyS1, UART0 RX for ttyS0)
// GND common. Use a level shifter if the GPS TX is 5 V.

void setup() {
  Serial1.begin(9600, SERIAL_8N1, 16, 17);   // GPS module
  Serial.begin(115200);                      // to screen; use 9600 for ttyS1
}

void loop() {
  while (Serial1.available()) Serial.write((uint8_t)Serial1.read());
}
```

If the ESP32 itself has the GPS, just generate/forward the `$GP...` sentences. For a bench test without antenna, inject known-good sentences from the firmware's own parser tests:

```text
$GPRMC,092750.000,A,5321.6802,N,00630.3372,W,0.02,31.66,280511,,,A*43
$GPGGA,092750.000,5321.6802,N,00630.3372,W,1,8,1.03,61.7,M,55.2,M,,*5F
```

Those lines have valid checksums and will make the UI show a fixed position without real satellites.

---

## 6. Verdict

| Route | Bluetooth? | DTB change? | Feasibility |
|---|---|---|---|
| A: ESP32 UART → `ttyS1` | No | **Yes** | High, once DTB is located |
| B: ESP32 UART → `ttyS0` | No | **No** | High; test console conflict |
| C: ESP32 SPP → `rf_serial` | Yes | No, but BT stack work | Low / unverified |
| Phone GPS via Zlink | Yes (CarPlay/AA) | No | Not practical from ESP32 |

**Recommendation:** route B for a quick test with the pads you already know, then route A for the final, permanently correct installation. Bluetooth is not the right interface for this firmware.
