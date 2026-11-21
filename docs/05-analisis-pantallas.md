# 05 - Analisis de las dos pantallas

[English](05-screen-analysis.en.md) · [Volver](../README.md)

Se aplico el procedimiento a **dos pantallas fisicas distintas**. Este documento recoge las diferencias reales encontradas en los volcados y sirve para no mezclar firmwares.

---

## Resumen comparativo

| Dato | Pantalla 1 - TF811 | Pantalla 2 - M750 |
|---|---|---|
| SSID WiFi | `TF811-xxxx` | `M750-xxxx` |
| Bluetooth | `TF811BT_` | `M750BT_` |
| Software (config_devmng.xml) | `TF811 2026-08-01 8733` | `M750 2026-08-15` |
| Build ID | `tina.zengfu.20260302.022659` | `tina.zhangxiangpu.20260815.011909` |
| Target | `v837s-perf1/generic v2.1` | `v853-perf1/generic v2.1` |
| U-Boot | `2018.07-g49ba65b-dirty (01/14/2026)` | `2018.07-g7572878-dirty (06/15/2026)` |
| DRAM | 64 MB (`dramfreq=528`) | 128 MB (`dramfreq=648`) |
| Panel LCD | `R0H 854x480` | `RX 854x480` |
| Sensor / IQ camara | `Nx 2025-02-27` | `Nx 2025-07-04` |
| Hardware string | `SW;V533;DC01;DC01;00;cdr;01;01` | (vacio) |
| Resolucion device.xml | 854x480 | 854x480 |
| `adbEnable` | 1 | 1 |
| Kernel | 4.9.191 | 4.9.191 |
| Tina / OpenWrt | 4.0.0 Neptune (`5C1C9C53`) | 4.0.0 Neptune (`5C1C9C53`) |
| WiFi | rtl8733bs / rtl8821cs | rtl8733bs / rtl8821cs |
| `bootreason` | (no aparece) | `usb` |

Ambas comparten la familia de software, el kernel, la resolucion y los drivers WiFi. **Pero no son el mismo hardware.**

---

## Particiones MTD

| Particion | TF811 | M750 | Nombre |
|---|---|---|---|
| mtd0 | 393 216 B | 393 216 B | uboot |
| mtd1 | 2 228 224 B | 2 293 760 B | boot |
| mtd2 | 13 369 344 B | 13 303 808 B | rootfs |
| mtd3 | 327 680 B | 327 680 B | rootfs_data |
| mtd4 | 131 072 B | 131 072 B | env |
| mtd5 | 131 072 B | 131 072 B | bootlogo |
| mtd6 | 65 536 B | 65 536 B | private |
| mtd7 | 131 072 B | 131 072 B | UDISK |

Total: 16 MB en ambos casos. El `boot` de la M750 es 64 KB mas grande y el `rootfs` 64 KB mas pequeno.

---

## Archivos de identidad del dispositivo

En la SD de la M750 aparecieron tres archivos propios del equipo, que tambien estan duplicados en el overlay (`overlay/upper/etc/` y `overlay/upper/mnt/extsd/`):

```text
id.txt      60811d4b00c4057000004c4000000000
config.txt  spanish:0,0:0,0,0,0:0,0,0,0:0,0,0,0:0,0:20260101_120101:1:0:1:0:0:0:1:1:35:20:0:95:0:0:1:0:1
tyre.txt    19:21:67:70:E1A0002B7713:E1A0007BD68C
```

- `id.txt`: ID unico de 32 caracteres hexadecimales.
- `config.txt`: configuracion del cliente (idioma español en este caso) con fecha `20260101_120101`.
- `tyre.txt`: dos codigos largos (`E1A0002B7713`, `E1A0007BD68C`), probablemente identificadores de sensor/TPMS.

Estos archivos son la forma en la que el firmware guarda la configuracion del cliente en la SD. **Sirven para distinguir pantallas** si tienes varias y todas usan el mismo `debug1`.

---

## Contenido del overlay (M750)

```text
data/param.bin
etc/zlink.txt
etc/rtl8733bs.txt
etc/blink/sc_db.db
etc/blink/.btlicense
etc/blink/bt_conf.ini
etc/config.txt
etc/tyre.txt
etc/firmware/p2pmac.sh
etc/firmware/ipscan.sh
etc/firmware/ap_ctrl.sh
etc/firmware/apmac.sh
etc/firmware/sta_ctrl.sh
etc/firmware/direct_ctrl.sh
etc/firmware/checkip.sh
etc/random-seed
mnt/extsd/hitlittlev1.0.exe
mnt/extsd/config.txt
mnt/extsd/tyre.txt
usr/lib/eyesee-mpp/libcrypto.so
usr/lib/eyesee-mpp/libssl.so
usr/bin/chroot_ota.sh
usr/bin/lt_image.sh
usr/bin/memtool
```

Los scripts de `etc/firmware/` gestionan los modos de la WiFi (AP, station, directo, MAC, etc.). Son un buen punto de partida si quieres entender como se configura la red del equipo.

---

## Cual es "mejor"

**La M750 (pantalla 2) es superior en especificaciones:**

| Criterio | Gana |
|---|---|
| Chip `v853` (mas nuevo, con NPU) vs `v837s` | M750 |
| 128 MB RAM vs 64 MB | M750 |
| DRAM 648 MHz vs 528 MHz | M750 |
| U-Boot jun/2026 vs ene/2026 | M750 |
| Build ago/2026 vs mar/2026 | M750 |
| Calibracion de camara 2025-07 vs 2025-02 | M750 |
| Kernel, Tina, resolucion, WiFi | Empate |
| Calidad visual del panel `R0H` vs `RX` | No se puede determinar sin verlos |

---

## Advertencia critica: no son intercambiables

Aunque compartan kernel 4.9.191 y resolucion 854x480, **no flashees el firmware de una pantalla en la otra**:

- Distinto SoC (`v837s` vs `v853`) -> distinto DTB y `sys_config.fex`
- Distinta cantidad de RAM (64 vs 128 MB) -> distinta configuracion de memoria
- Distinto panel (`R0H` vs `RX`) -> distinta inicializacion y calibracion de pantalla
- Distinta calibracion de camara (`Nx 2025-02-27` vs `Nx 2025-07-04`)

El metodo de volcado **si es comun** a ambas; las imagenes resultantes, **no**.

---

## Organizacion recomendada de los volcados

```text
firmware_dumps/
├── TF811/
│   ├── podofo_full.bin
│   ├── info.txt
│   ├── mtdblock0.bin ... mtdblock7.bin
│   ├── etc/
│   ├── overlay/
│   └── data/
└── M750/
    ├── info.txt
    ├── mtdblock0.bin ... mtdblock7.bin
    ├── etc/
    ├── overlay/
    └── data/
```

Guarda siempre el `info.txt` junto a los `mtdblock*.bin`: es la unica forma de saber de que equipo concreto salio el volcado si se mezclan.
