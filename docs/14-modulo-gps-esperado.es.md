# 14 - ¿Qué módulo GPS espera esta placa?

[English](14-expected-gps-module.md) · [Volver](../README.es.md)

**Keywords:** módulo GPS, NMEA 0183, UART1 ttyS1, PE6 PE7, 9600 baudios, u-blox NEO-6M, antena GPS activa, devGpsUart, gps_baud, gps_info, sun8iw21, v837s

**Respuesta corta:** el firmware espera un **módulo GPS serie NMEA 0183 con UART TTL de 3,3 V a 9600 baudios**, conectado a `UART1` (`/dev/ttyS1`) en los pines `PE6` (TX) y `PE7` (RX). Esta unidad parece no llevarlo montado, pero el soporte de software ya existe: se puede añadir. **No** es RS232 y **no** es plug-and-play porque `UART1` está desactivado en el DTB.

---

## 1. Pruebas encontradas en el firmware

| Fuente | Hallazgo | Significado |
|---|---|---|
| `data/res/config/device.xml` | `devGpsUart="dev/ttyS1"` | La app espera el GPS en UART1. Falta la barra inicial (doc 07) |
| `data/res/param/config_devmng.xml` | `gps_baud="9600"` | Velocidad serie esperada del módulo |
| `data/res/param/config_devmng.xml` | `gps_info="0"`, `gps_speed_unit="0"`, `gps_speed_adj="0"` | Página de info GPS y corrección de velocidad |
| `usr/lib/eyesee-mpp/libCoreUtils.so` | Parsea `GPRMC`, `GPGGA`, `GPGLL`, `GPGSA`, `GPGSV`, `GPHDT`, `GPVTG`, `GPZDA` | Cadenas estándar **NMEA 0183**, con checksum |
| `usr/lib/eyesee-mpp/libltcdr.so` | `LT_GPSMNG_Init/Start/GetData/Search`, lee `devGpsUart`, `gpsSearch` | El gestor GPS lee ese puerto serie |
| `data/res/layout/gpsinfo.xml` | Campos `gps_status`, `gps_utc`, `gps_lat`, `gps_lon`, `gps_speed`, `gps_bearing`, `gps_accuracy` | Exactamente lo que da un módulo NMEA normal |
| `m750.dts` | `uart1@2500400` con `status = "disabled"` | El puerto existe pero está apagado |
| `m750.dts` | `uart1_pins_active`: `PE6`, `PE7`, función `uart1`, mux `0x06` | Pines físicos reservados al UART del GPS |
| `m750.dts` | No hay nodo `gps-power` ni regulador | No hay pin de alimentación controlado por software; el módulo debe alimentarse de un rail de la placa |

Las librerías `libXGCGps.so` / `libSunAlgorithm.so` contienen `sunGpsGXDecode`, que formatea fecha/hora y `N:... E:... km/h x y z`. Eso sirve para incrustar datos GPS en las grabaciones, no para el protocolo serie.

---

## 2. Qué comprar

Cualquier módulo que saque **NMEA 0183 a 9600 baudios por UART TTL** servirá. Opciones típicas:

- Placas con u-blox **NEO-6M**, **NEO-7M** o **NEO-8M** (tipo GY-NEO6MV2).
- Un módulo GPS/GNSS configurable a 9600 baudios y salida NMEA.
- **Antena GPS activa** (SMA o pigtail U.FL) con vista despejada al cielo. Dentro de casa no habrá fix.

Evitar:

- Módulos **RS232** (±12 V): destruyen el UART del SoC.
- Módulos **TTL de 5 V** alimentados a 5 V sin adaptador de nivel en su TX.
- Módulos que solo hablen protocolo binario propietario (modo u-blox UBX-only); hay que ponerlos en NMEA.

La mayoría de las placas NEO-6M vienen por defecto a 9600 y TTL de 3,3 V, justo lo que espera este firmware. Alimenta el módulo a 3,3 V si puedes; si la placa exige 5 V, dale 5 V pero baja su TX a 3,3 V antes de `PE7`.

---

## 3. Cableado

| SoC / placa | Módulo GPS | Notas |
|---|---|---|
| `PE6` = UART1_TX | RX | El SoC envía al módulo (normalmente solo comandos de config) |
| `PE7` = UART1_RX | TX | Conectar aquí el TX del módulo; divisor/adaptador si es de 5 V |
| GND | GND | Masa común imprescindible |
| Rail de 3,3 V | VCC | Comprobar consumo; no alimentar desde un GPIO |
| Conector de antena | Antena activa | Colocar con cielo despejado |

`PE6`/`PE7` son los pines que el DTB asigna a `uart1`. Si la placa tiene pads sin poblar o un conector de 4 pines, verifícalos con multímetro/continuidad antes de soldar. Abrir la carcasa rompe el sellado IP67.

---

## 4. Checklist de software (todo necesario)

El hardware solo no basta. A fecha de la doc 12 hay que corregir:

1. **Activar `uart1` en el DTB**: cambiar `status = "disabled"` → `"okay"` en `uart1@2500400`, manteniendo `PE6`/`PE7` con mux `0x06`. El DTB no está como archivo suelto en `mtdblock0..7`, así que aún hay que localizar su posición real en la imagen de arranque. No grabes un DTB a ciegas.
2. **Corregir la ruta**: `devGpsUart="dev/ttyS1"` → `"/dev/ttyS1"` en `device.xml`.
3. **Mostrar la página**: `gps_info="0"` → `"1"` en `config_devmng.xml`.
4. **Baudios**: mantener `gps_baud="9600"` o configurar el módulo a 9600.
5. **Opcional**: `gpsSearch="0"` → `"1"` si quieres que el gestor busque activamente al arrancar.
6. **Menú**: `i_gps_info` ya está activo; `i_gps_osd` y otros extras están comentados en `model.xml` (doc 13).
7. Reconstruir el rootfs y grabar `mtdblock2` siguiendo docs 09-10; no borrar archivos de `/data` antes de grabar (whiteouts de overlayfs).

Hasta resolver el paso 1, conectar el módulo no dará datos: `/dev/ttyS1` no existirá o no estará activo.

---

## 5. Cómo probar el módulo antes

Antes de tocar la pantalla, conecta el GPS a un adaptador USB-UART en un PC y abre un terminal a **9600 8N1**:

```text
$GPRMC,092750.000,A,5321.6802,N,00630.3372,W,0.02,31.66,280511,,,A*43
$GPGGA,092750.000,5321.6802,N,00630.3372,W,1,8,1.03,61.7,M,55.2,M,,*5F
```

Si ves frases `$GP...` con checksum `*XX` válido, el módulo es correcto. El primer fix en frío puede tardar desde 30 s hasta varios minutos; hazlo en exteriores.

---

## 6. Veredicto

| Pregunta | Respuesta |
|---|---|
| ¿El firmware soporta GPS? | **Sí**, parser NMEA completo y página de UI |
| ¿Lleva el módulo montado? | Aparentemente **no** |
| ¿Se puede comprar y añadir? | **Sí**, cualquier módulo NMEA TTL de 3,3 V a 9600 |
| ¿Es plug-and-play? | **No**: `uart1` está desactivado en el DTB y la ruta en `device.xml` está mal |
| Mayor riesgo | Tensión incorrecta en `PE7` o grabar un DTB sin verificar |

La parte de software está lista; falta el acceso físico y localizar/parchear el DTB real.
