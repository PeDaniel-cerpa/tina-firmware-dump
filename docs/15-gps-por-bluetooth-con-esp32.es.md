# 15 - ¿Puede un ESP32 enviar datos GPS por Bluetooth?

[English](15-bluetooth-gps-with-esp32.md) · [Volver](../README.es.md)

**Keywords:** ESP32 GPS, Bluetooth SPP GPS, inyección NMEA, devBtUart, rf_serial, ttyS0, ttyS1, UART1, phone_gps_info, CarPlay GPS, Zlink

**Respuesta corta:** **no directamente por Bluetooth SPP.** El firmware no tiene una entrada genérica de "GPS por Bluetooth". Lee NMEA desde un **dispositivo serie** indicado por `devGpsUart`. Un ESP32 sí puede hacer el trabajo, pero debe sacar **NMEA por UART TTL** hacia alguno de los puertos serie de la pantalla. Hay dos rutas prácticas y una especulativa.

---

## 1. Lo que el firmware soporta realmente

| Prueba | Conclusión |
|---|---|
| `device.xml`: `devGpsUart="dev/ttyS1"` | El gestor GPS lee una **ruta UART** |
| `config_devmng.xml`: `gps_baud="9600"` | Espera NMEA 8N1 a 9600 |
| `libltcdr.so`: `LT_GPSMNG_Init/Start/GetData/Search`, `OpenSerialPort`, `CloseSerialPort` | El GPS viene de un puerto serie, no de Bluetooth |
| `libCoreUtils.so`: `NMEAParse`, `SerialStreamCreate`, `Opening serial port '%s'` | Parser NMEA estándar alimentado por un stream serie |
| `device.xml`: `devBtUart="dev/rf_serial"` | Existe la clave de configuración, pero... |
| Ningún init script crea `/dev/rf_serial` ni arranca `rfcomm` | ...no hay nodo RFCOMM/SPP por defecto |
| El nodo DTB `btlpm` está `status = "disabled"` | La gestión de alimentación Bluetooth también está desactivada |
| `libzlink-main.so`: `phone_gps_info`, `mirror_phone_gps_info_parse` | Existe GPS del móvil, pero solo dentro del protocolo propietario Zlink / CarPlay / Android Auto |

No hay **ninguna evidencia** de una ruta Bluetooth SPP → parser NMEA. Los mensajes `phone_gps_info` son protobuf de CarPlay/AA de un móvil emparejado; un ESP32 no puede imitarlos sin reimplementar un stack propietario enorme.

---

## 2. Ruta A (la correcta): ESP32 → UART1 (`ttyS1`)

Es para lo que el firmware fue escrito.

1. Conectar el TX del ESP32 a `PE7` (UART1_RX de la pantalla), GND a GND.
2. ESP32 emite NMEA a **9600 8N1**.
3. Parchear el firmware:
   - activar `uart1@2500400` en el DTB (`status = "okay"`, PE6/PE7 mux 6),
   - `devGpsUart="/dev/ttyS1"`,
   - `gps_info="1"`,
   - `gps_baud="9600"`.

Ventajas: coincide con el diseño original. Inconveniente: sigue haciendo falta localizar y parchear el DTB real (docs 12/14).

---

## 3. Ruta B (atajo): ESP32 → UART0 existente (`ttyS0`)

Los pads de UART0 son los que ya usamos para el volcado, así que son físicamente accesibles y el driver está activo. `ttyS0` existe aunque el cmdline tenga `console=` vacío.

1. Conectar el TX del ESP32 al **pad RX de UART0** (el que conectamos como "RX de la pantalla" en la doc 11).
2. Emitir NMEA a **115200** (o ejecutar `stty -F /dev/ttyS0 9600` y usar 9600).
3. Parchear solo la configuración:
   - `devGpsUart="/dev/ttyS0"`
   - `gps_baud="115200"` (o 9600 tras `stty`)
   - `gps_info="1"`
4. Revisar `/etc/inittab`: tiene `/dev/console::respawn:-/bin/sh` y el getty de `ttyS0` está comentado. Si el shell acaba en `ttyS0` y se come los bytes NMEA, quita esa línea de respawn o redirige `/dev/console`.

Ventajas: **no necesita cambiar el DTB**. Inconvenientes: compartes/pierdes la consola de depuración en esos pads; hay que comprobar en vivo que nadie más lee `ttyS0`.

---

## 4. Ruta C (especulativa): ESP32 como Bluetooth SPP

En teoría: emparejar el ESP32 con la pantalla como dispositivo de puerto serie, enlazar un nodo RFCOMM como `/dev/rf_serial` y poner `devGpsUart="/dev/rf_serial"`.

Por qué **no se recomienda**:

- ningún init script crea ese nodo;
- `btlpm` está desactivado en el DTB;
- el Bluetooth de la pantalla lo usa Zlink para el handshake de CarPlay/Android Auto, así que emparejar un ESP32 puede chocar;
- nunca se ha verificado en hardware real.

Solo intentarlo tras conseguir shell root en vivo y confirmar que existen las herramientas `rfcomm` y un stack Bluetooth funcional. Es un experimento, no un procedimiento documentado.

---

## 5. Sketch mínimo del ESP32 (rutas A/B)

```cpp
// TX del módulo GPS -> RX del ESP32 (GPIO16)
// TX del ESP32 (GPIO17) -> pad RX de la pantalla
//   (PE7 para ttyS1, pad RX de UART0 para ttyS0)
// Masa común. Adaptador de nivel si el TX del GPS es de 5 V.

void setup() {
  Serial1.begin(9600, SERIAL_8N1, 16, 17);   // módulo GPS
  Serial.begin(115200);                      // hacia pantalla; 9600 para ttyS1
}

void loop() {
  while (Serial1.available()) Serial.write((uint8_t)Serial1.read());
}
```

Si el ESP32 lleva el GPS integrado, basta con generar/reenviar las frases `$GP...`. Para probar en banco sin antena, inyecta frases válidas tomadas de los propios tests del parser del firmware:

```text
$GPRMC,092750.000,A,5321.6802,N,00630.3372,W,0.02,31.66,280511,,,A*43
$GPGGA,092750.000,5321.6802,N,00630.3372,W,1,8,1.03,61.7,M,55.2,M,,*5F
```

Tienen checksum válido y harán que la UI muestre una posición fija sin satélites reales.

---

## 6. Veredicto

| Ruta | ¿Bluetooth? | ¿Cambiar DTB? | Viabilidad |
|---|---|---|---|
| A: ESP32 UART → `ttyS1` | No | **Sí** | Alta, cuando se localice el DTB |
| B: ESP32 UART → `ttyS0` | No | **No** | Alta; probar conflicto con consola |
| C: ESP32 SPP → `rf_serial` | Sí | No, pero hay que arreglar BT | Baja / sin verificar |
| GPS del móvil vía Zlink | Sí (CarPlay/AA) | No | Impractico desde ESP32 |

**Recomendación:** la ruta B para una prueba rápida con los pads que ya conoces, y la A para la instalación final correcta. Bluetooth no es la interfaz adecuada para este firmware.
