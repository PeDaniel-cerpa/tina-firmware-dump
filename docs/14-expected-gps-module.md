# 14 - What GPS module does this board expect?

[Español](14-modulo-gps-esperado.es.md) · [Back](../README.md)

**Keywords:** GPS module, NMEA 0183, UART1 ttyS1, PE6 PE7, 9600 baud, u-blox NEO-6M, active GPS antenna, devGpsUart, gps_baud, gps_info, sun8iw21, v837s

**Short answer:** the firmware expects a cheap **NMEA 0183 serial GPS module with 3.3 V TTL UART at 9600 baud**, connected to `UART1` (`/dev/ttyS1`) on pins `PE6` (TX) and `PE7` (RX). The board does not appear to have it fitted, but the software support is already there: it can be added. It is **not** RS232, and it is **not** plug-and-play because `UART1` is disabled in the DTB.

---

## 1. Evidence found in the firmware

| Source | Finding | Meaning |
|---|---|---|
| `data/res/config/device.xml` | `devGpsUart="dev/ttyS1"` | The app expects the GPS on UART1. Note the missing leading slash (see doc 07) |
| `data/res/param/config_devmng.xml` | `gps_baud="9600"` | Serial speed expected from the module |
| `data/res/param/config_devmng.xml` | `gps_info="0"`, `gps_speed_unit="0"`, `gps_speed_adj="0"` | GPS info page and speed correction flags |
| `usr/lib/eyesee-mpp/libCoreUtils.so` | Parses `GPRMC`, `GPGGA`, `GPGLL`, `GPGSA`, `GPGSV`, `GPHDT`, `GPVTG`, `GPZDA` | Standard **NMEA 0183** strings, checksum-validated |
| `usr/lib/eyesee-mpp/libltcdr.so` | `LT_GPSMNG_Init/Start/GetData/Search`, reads `devGpsUart`, `gpsSearch` | The UI/GPS manager reads that serial port |
| `data/res/layout/gpsinfo.xml` | Fields `gps_status`, `gps_utc`, `gps_lat`, `gps_lon`, `gps_speed`, `gps_bearing`, `gps_accuracy` | Exactly the data a normal NMEA module provides |
| `m750.dts` | `uart1@2500400` has `status = "disabled"` | The port exists but is off in the device tree |
| `m750.dts` | `uart1_pins_active`: `PE6`, `PE7`, function `uart1`, mux `0x06` | Physical pins reserved for GPS UART |
| `m750.dts` | No `gps-power` / regulator node | No software-controlled GPS power pin; module must be powered from a board rail |

The library `libXGCGps.so` / `libSunAlgorithm.so` contains `sunGpsGXDecode`, which formats a timestamp plus `N:... E:... km/h x y z`. That is for embedding GPS data into recordings, not for the serial protocol.

---

## 2. What to buy

Any module that outputs **NMEA 0183 at 9600 baud over TTL UART** will work. Typical choices:

- u-blox **NEO-6M**, **NEO-7M** or **NEO-8M** breakout boards (e.g. GY-NEO6MV2 style).
- A GPS + GNSS module that can be configured to 9600 baud and NMEA output.
- An **active GPS antenna** (SMA or U.FL pigtail) with clear sky view. GPS will not fix indoors.

Avoid:

- **RS232 GPS modules** (±12 V): they will damage the SoC UART.
- **5 V TTL** modules powered from 5 V without a level shifter on their TX line.
- Modules that only speak proprietary binary protocols (u-blox UBX-only mode); set them to NMEA.

Most NEO-6M breakouts default to 9600 baud and 3.3 V TTL, which matches this firmware. Power the module at 3.3 V if possible; if the breakout needs 5 V, power it at 5 V but shift its TX down to 3.3 V before `PE7`.

---

## 3. Wiring

| SoC / board | GPS module | Notes |
|---|---|---|
| `PE6` = UART1_TX | RX | SoC sends to module (usually only config commands) |
| `PE7` = UART1_RX | TX | Connect module TX here; use a divider/level shifter if it is 5 V |
| GND | GND | Common ground mandatory |
| 3.3 V rail | VCC | Check current draw; do not feed from a GPIO |
| Antenna connector | Active antenna | Place with clear sky |

`PE6`/`PE7` are the pins named in the DTB for `uart1`. If the board has unpopulated pads or a 4-pin header, verify with a multimeter/continuity test before soldering. Opening the enclosure breaks the IP67 seal.

---

## 4. Software checklist (all required)

The hardware alone is not enough. As of doc 12, the following must be fixed:

1. **Enable `uart1` in the DTB**: change `status = "disabled"` → `"okay"` for `uart1@2500400`, keeping `PE6`/`PE7` mux `0x06`. The DTB is not a standalone file in `mtdblock0..7`, so its exact location in the boot image still has to be found. Do not flash a guessed DTB.
2. **Fix the path**: `devGpsUart="dev/ttyS1"` → `"/dev/ttyS1"` in `device.xml`.
3. **Show the page**: `gps_info="0"` → `"1"` in `config_devmng.xml`.
4. **Baud**: keep `gps_baud="9600"`, or set the module to 9600.
5. **Optional**: `gpsSearch="0"` → `"1"` if you want the manager to actively search at boot.
6. **Menu**: `i_gps_info` is already active; `i_gps_osd` and `i_gps_info`-related extras are commented in `model.xml` (doc 13).
7. Rebuild the rootfs and flash `mtdblock2` following docs 09-10; do not delete files from `/data` before flashing (overlayfs whiteouts).

Until step 1 is solved, connecting a module will produce no data: `/dev/ttyS1` will not exist or will not be driven.

---

## 5. How to test the module first

Before touching the screen, plug the GPS into a USB-UART adapter on a PC and open a terminal at **9600 8N1**:

```text
$GPRMC,092750.000,A,5321.6802,N,00630.3372,W,0.02,31.66,280511,,,A*43
$GPGGA,092750.000,5321.6802,N,00630.3372,W,1,8,1.03,61.7,M,55.2,M,,*5F
```

If you see `$GP...` sentences with a valid `*XX` checksum, the module is correct. Cold-lock can take 30 s to several minutes; wait outdoors.

---

## 6. Feasibility verdict

| Question | Answer |
|---|---|
| Does the firmware support a GPS? | **Yes**, full NMEA parser and UI page |
| Is the module fitted? | Apparently **no**; there is no visible hardware support in this unit |
| Can one be bought and added? | **Yes**, any 3.3 V TTL NMEA module at 9600 baud |
| Is it plug-and-play? | **No**: `uart1` is disabled in the DTB and the path in `device.xml` is wrong |
| Biggest risk | Wrong voltage on `PE7`, or flashing an unverified DTB |

The software side is ready; the remaining work is hardware access plus locating/patching the real DTB.
