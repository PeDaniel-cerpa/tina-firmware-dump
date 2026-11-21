# 12 - Auditoría offline: nodos DTB desactivados y flags de la interfaz

[English](12-offline-dtb-and-flags-audit.md) · [Volver](../README.es.md)

**Keywords:** auditoría DTB, status disabled, sun8iw21, v837s, flags config_devmng.xml, wifi_ssid_hide, bFMenable, ble_enable, gps_info, UART1, dtc, análisis offline del firmware

Esta es la auditoría pedida tras corregir los whiteouts. Se hizo **offline**, directamente desde el firmware extraído, así que no hacen falta la SD ni la pantalla encendida. El script opcional de verificación en vivo es [`files/debug1-audit-dtb.sh`](../files/debug1-audit-dtb.sh).

---

## 1. Fuentes

| Fuente | Qué aportó |
|---|---|
| `dtb_descomprimido.bin` → descompilado a `m750.dts` | 48 nodos con `status = "disabled"` |
| `m750root/data/res/param/config_devmng.xml` | más de 130 flags de configuración |
| `m750root/data/res/layout/*.xml` | interruptores y estados de visibilidad de la UI |
| `m750root/etc/init.d/` | scripts de servicios desactivados (ver doc 07) |

El DTB **no** aparece como archivo independiente dentro de `mtdblock0..7`: ni su magic ni sus primeros 64 bytes están en ninguna partición volcada. Probablemente va incrustado o comprimido en la imagen de arranque (`mtdblock1`). **No grabes un DTB modificado hasta localizar su posición real en la cadena de arranque.** Editar el `.dts` es seguro; escribirlo en flash todavía no.

---

## 2. Nodos desactivados por subsistema

| Subsistema | Cantidad | Ejemplos | Valoración |
|---|---:|---|---|
| UART | 1 | `uart1` | **Útil**: GPS / segundo serie. Requiere flag y corregir la ruta |
| SPI / NAND / NOR | 7 | `spi0..spi3`, `spif`, `spif-nor`, `spi_board1` | No tocar: flash de arranque y bus de pantalla |
| I2C / PMU / chips de audio | 8 | `twi0`, `twi1`, `da380`, `es8388`, `fmsend`, `pmu`, `powerkey`, `axp_gpio` | Algunos podrían ser seguros, pero PMU/cargador afectan a la alimentación |
| MMC | 1 | `sdc2` | Poco útil; la SD ya es `sdc0` |
| RTC | 1 | `rtc@7090000` | **Bajo riesgo**, reloj con batería |
| Audio | 4 | `dmic_*`, `daudio0_*` | Solo si el hardware existe realmente |
| Wiegand | 1 | `wiegand@0x02020000` | Interface de control de acceso, sin uso aquí |
| Ethernet | 1 | `gmac0` | Necesita PHY y pines; probablemente sin conectar |
| Cámara / VIN | 15 | `sensor0/1`, `csi2`, `vinc00..vinc33` | No hay sensores; activarlos no sirve |
| Coprocesador / BT / cargador | 4 | `e907_rproc`, `e907_standby`, `btlpm`, `gpio_charger` | **Evitar**: necesita firmware extra o altera la alimentación |

USB **no** está desactivado: `udc-controller@0x4100000` está `okay`.

Los bootargs en ejecución siguen ganando sobre el DTS:

```text
console=            loglevel=0
```

El DTS contiene `console=ttyS0`, `loglevel=8`, pero esa no es la cadena que recibe el kernel.

---

## 3. Lista completa de los 48 nodos desactivados

La ruta es relativa a `/soc@03000000` salvo que empiece por `/e907_rproc`.

| Nodo | Label | Compatible |
|---|---|---|
| `uart@2500400` | `uart1` | `allwinner,sun8i-uart` |
| `spi@04025000/spi-nand@0` | `spi0` | `spi-nand` |
| `spi@04026000` | `spi1` | `allwinner,sun8i-spi` |
| `spi@04026000/spi_board1@0` | `spi1` | `sunxi,spidbi` |
| `spi@04027000` | `spi2` | `allwinner,sun8i-spi` |
| `spi@04028000` | `spi3` | `allwinner,sun8i-spi` |
| `spif@04f00000` | `spif0` | `allwinner,sun8i-spif` |
| `spif@04f00000/spif-nor` | `spif0` | `spi-nor` |
| `twi@0x02502000` | `twi0` | `allwinner,sun8i-twi` |
| `twi@0x02502400` | `twi1` | `allwinner,sun8i-twi` |
| `twi@0x02502c00/da380` | `twi3` | `allwinner,sun8i-twi` |
| `twi@0x02502c00/es8388@10` | `es8388` | `everest,es8388` |
| `twi@0x02503000/fmsend` | `twi4` | `allwinner,sun8i-twi` |
| `twi@0x02503000/pmu@0` | `pmu0` | `x-powers,axp2101` |
| `twi@0x02503000/pmu@0/powerkey@0` | `powerkey0` | `x-powers,axp2101` |
| `twi@0x02503000/pmu@0/axp_gpio@0` | `axp_gpio0` | `x-powers,axp2101` |
| `sdmmc@4022000` | `sdc2` | `allwinner,sunxi-mmc-v4p6x` |
| `rtc@7090000` | `rtc` | `allwinner,sunxi-rtc` |
| `dmic_plat@0x02031000` | `dmic_plat` | `allwinner,sunxi-snd-plat-dmic` |
| `dmic_mach` | `dmic_mach` | `allwinner,sunxi-snd-mach` |
| `daudio0_plat@0x02032000` | `daudio0_plat` | `allwinner,sunxi-snd-plat-daudio` |
| `daudio0_mach` | `daudio0_mach` | `allwinner,sunxi-snd-mach` |
| `wiegand@0x02020000` | `wiegand` | `allwinner,sunxi-wiegand` |
| `eth@4500000` | `gmac0` | `allwinner,sunxi-gmac` |
| `vind@0/csi@2` | `csi2` | `allwinner,sunxi-csi` |
| `vind@0/actuator@0` | `actuator0` | `allwinner,sunxi-actuator` |
| `vind@0/flash@0` | `flash0` | `allwinner,sunxi-flash` |
| `vind@0/sensor@0` | `sensor0` | `allwinner,sunxi-sensor` |
| `vind@0/sensor@1` | `sensor1` | `allwinner,sunxi-sensor` |
| `vind@0/vinc@0` | `vinc00` | `allwinner,sunxi-vin-core` |
| `vind@0/vinc@1` | `vinc01` | `allwinner,sunxi-vin-core` |
| `vind@0/vinc@2` | `vinc02` | `allwinner,sunxi-vin-core` |
| `vind@0/vinc@3` | `vinc03` | `allwinner,sunxi-vin-core` |
| `vind@0/vinc@5` | `vinc11` | `allwinner,sunxi-vin-core` |
| `vind@0/vinc@6` | `vinc12` | `allwinner,sunxi-vin-core` |
| `vind@0/vinc@7` | `vinc13` | `allwinner,sunxi-vin-core` |
| `vind@0/vinc@8` | `vinc20` | `allwinner,sunxi-vin-core` |
| `vind@0/vinc@9` | `vinc21` | `allwinner,sunxi-vin-core` |
| `vind@0/vinc@10` | `vinc22` | `allwinner,sunxi-vin-core` |
| `vind@0/vinc@11` | `vinc23` | `allwinner,sunxi-vin-core` |
| `vind@0/vinc@12` | `vinc30` | `allwinner,sunxi-vin-core` |
| `vind@0/vinc@13` | `vinc31` | `allwinner,sunxi-vin-core` |
| `vind@0/vinc@14` | `vinc32` | `allwinner,sunxi-vin-core` |
| `vind@0/vinc@15` | `vinc33` | `allwinner,sunxi-vin-core` |
| `e907_standby@0` | `e907_standby` | `allwinner,sunxi-e907-standby` |
| `btlpm` | `btlpm` | `allwinner,sunxi-btlpm` |
| `gpio_charger@0` | `gpio_charger` | `gpio-charger` |
| `/e907_rproc@0` | `e907_rproc` | `allwinner,sun8iw21p1-e907-rproc` |

Nota: `da380`, `es8388`, `fmsend`, `pmu`, `powerkey` y `axp_gpio` son hijos de controladores I2C que **no** están desactivados; su `status = "disabled"` simplemente indica que no hay dispositivo en esa dirección.

---

## 4. Flags de configuración que merecen un cambio

Abajo solo están el nombre del flag y la acción recomendada. Contraseñas, SSID y campos MAC **no** se reproducen aquí.

| Flag | Valor actual | Significado / cambio propuesto |
|---|---|---|
| `wifi_ssid_hide` | `0` | Poner `1` para ocultar el nombre del AP. Seguro, sin depender del DTB |
| `wifi_enable` / `wifi_mode` | `1` / `1` | AP activo. Dejar salvo que quieras modo estación |
| `wifi_channel` | `6` | Canal AP 2,4 GHz; cambiar a 1/6/11 si está saturado |
| `wifi_code` / `wifi_chn` | `US` / `36` | Dominio regulatorio / canal 5 GHz |
| `gps_info` | `0` | Mostrar info GPS. Necesita `uart1` activo **y** corregir la ruta (`dev/ttyS1` → `/dev/ttyS1`) |
| `gps_baud` | `9600` | Igualar al módulo GPS |
| `bFMenable` | `0` | FM apagado. Activar el flag solo no sirve: `fmsend` está desactivado en el DTB |
| `bFMSend` | `1` | Parte de emisión FM; misma dependencia del DTB |
| `AUX_enable` | `0` | Entrada AUX |
| `ble_enable` / `ble_user` | `0` / `0` | BLE apagado; también depende de `btlpm` y de hardware BT real |
| `PBT_enable` / `bUserBluetooth` | `1` / `1` | Bluetooth clásico ya activo |
| `car_osd` | `0` | Guías de cámara |
| `stream_cam` | `0` | Streaming de cámara |
| `screen_filp` | `0` | Gira/invierte la imagen |
| `switch_sys_psd` | `0` | Petición de contraseña. Existen `admin_sys_psd` / `sys_psd` |
| `boot_voice` / `touchtone` / `voice_ctl` | `1` | Sonido de arranque, tacto y control por voz |
| `hour24` / `date_format` / `zone` | `1` / `0` / `480` | Formato de hora y zona horaria |
| `language` | `english` | Idioma de la interfaz |
| `lcd_info` | `RX 854x480` | Descripción del panel; confirma 854×480 |
| `software` | `M750 2026-08-15` | Cadena de versión en ajustes |

---

## 5. Interruptores XML encontrados

Controles de la UI en `data/res/layout/`. Cambiar sus atributos permite mostrar/ocultar opciones sin tocar el binario:

| Archivo | Interruptor / estado |
|---|---|
| `eye_mode.xml` | `em_switch`, `tc_switch`, `lp_switch` |
| `fmbluetooth.xml` | `fmswitch`, `bt_switch`, `connect_status` |
| `gpsinfo.xml` | `gps_status`, `status_txt` |
| `hm_setting_time.xml`, `setting_time.xml` | `switch_24h`, `switch_ampm`, `switch_zs` |
| `setting_carosd.xml` | `switch_car_osd` |
| `setting_channel.xml` | `cam0_filp_switch`, `cam0_mirror_switch`, `cam1_*`, `cam2_*`, `cam3_*` |
| `setting_sys_switch.xml` | `switch_sys_psd` |
| `zlink_mode.xml`, `zlink_mode_zh.xml` | `switch_wifi`, `zm_bt_switch`, `zm_connect_status` |
| `home.xml`, `home_main.xml` | `status_gpsinfo`, `status_brightness`, `status_wifi_*`, `status_bt_*` |

---

## 6. Orden recomendado de cambios

1. **Ocultar el SSID WiFi** — un flag XML, reversible, sin regrabar firmware.
2. **Activar la consola UART** desde `/etc/inittab` (`ttyS0`) — no es cambio de DTB, bajo riesgo, da acceso serie permanente.
3. **Activar `uart1` para GPS** — edición del DTB **más** corregir `dev/ttyS1` → `/dev/ttyS1` en `config_devmng.xml`.
4. **Activar `rtc@7090000`** — bajo riesgo, fechas correctas.
5. **Activar `twi0` / `twi1`** — solo si vas a conectar dispositivos I2C.
6. **Mostrar/ocultar interruptores de la UI** — solo XML, reversible desde el overlay.

No actives: nodos PMU/cargador, `e907_rproc`, cámara/VIN, controladores SPI de arranque ni `gmac0` sin cableado y sin haber localizado el DTB real.

---

## 7. Cómo aplicar un cambio del DTB (cuando se localice)

```sh
dtc -I dtb -O dts dtb_descomprimido.bin > board.dts
# editar solo las líneas status elegidas: "disabled" -> "okay"
dtc -I dts -O dtb board.dts > board_patched.dtb
```

Después hay que averiguar dónde va `board_patched.dtb` dentro de la imagen de arranque y reconstruir esa partición. Hasta entonces, guarda el cambio en el `.dts` solo como documentación.

Para confirmarlo en vivo, copia [`files/debug1-audit-dtb.sh`](../files/debug1-audit-dtb.sh) como `debug1`; escribe los mismos datos en `F:\audit\` sin modificar el firmware.
