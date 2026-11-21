# 12 - Offline audit: disabled DTB nodes and UI flags

[Español](12-auditoria-dtb-y-flags.es.md) · [Back](../README.md)

**Keywords:** DTB audit, status disabled, sun8iw21, v837s, config_devmng.xml flags, wifi_ssid_hide, bFMenable, ble_enable, gps_info, UART1, dtc, offline firmware analysis

This is the audit requested after the whiteout fix. It was done **offline**, directly from the extracted firmware, so no SD or powered screen is needed. The optional live verification script is [`files/debug1-audit-dtb.sh`](../files/debug1-audit-dtb.sh).

---

## 1. Sources

| Source | What it gave |
|---|---|
| `dtb_descomprimido.bin` → decompiled to `m750.dts` | 48 nodes with `status = "disabled"` |
| `m750root/data/res/param/config_devmng.xml` | 130+ configuration flags |
| `m750root/data/res/layout/*.xml` | UI switches and visibility states |
| `m750root/etc/init.d/` | Disabled service scripts (already covered in doc 07) |

The DTB was **not** found as a standalone file inside `mtdblock0..7`; neither its raw magic nor its first 64 bytes appear in any dumped partition. It is probably embedded or compressed in the boot image (`mtdblock1`). **Do not flash a modified DTB until its real location in the boot chain is identified.** Editing the `.dts` is safe; writing it to flash is not yet.

---

## 2. Disabled nodes by subsystem

| Subsystem | Count | Examples | Assessment |
|---|---:|---|---|
| UART | 1 | `uart1` | **Useful**: GPS / second serial. Needs flag + path fix |
| SPI / NAND / NOR | 7 | `spi0..spi3`, `spif`, `spif-nor`, `spi_board1` | Leave alone: boot flash and display bus |
| I2C / PMU / audio chips | 8 | `twi0`, `twi1`, `da380`, `es8388`, `fmsend`, `pmu`, `powerkey`, `axp_gpio` | Some may be safe, but PMU/charger changes can affect power |
| MMC | 1 | `sdc2` | Low value; SD is already `sdc0` |
| RTC | 1 | `rtc@7090000` | **Low risk**, enables battery-backed clock |
| Audio | 4 | `dmic_*`, `daudio0_*` | Only if the hardware is actually present |
| Wiegand | 1 | `wiegand@0x02020000` | Access-control interface, not useful here |
| Ethernet | 1 | `gmac0` | Needs PHY and pins; likely unconnected |
| Camera / VIN | 15 | `sensor0/1`, `csi2`, `vinc00..vinc33` | No sensors fitted; enabling is pointless |
| Coprocessor / BT / charger | 4 | `e907_rproc`, `e907_standby`, `btlpm`, `gpio_charger` | **Avoid**: needs extra firmware or can alter power |

USB is **not** disabled: `udc-controller@0x4100000` is `okay`.

Runtime bootargs still override the DTS:

```text
console=            loglevel=0
```

The DTS contains `console=ttyS0`, `loglevel=8`, but that string is not what the kernel receives.

---

## 3. Full list of the 48 disabled nodes

Path is relative to `/soc@03000000` unless it starts with `/e907_rproc`.

| Node path | Label | Compatible |
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

Note: `da380`, `es8388`, `fmsend`, `pmu`, `powerkey` and `axp_gpio` are children of I2C controllers that are **not** disabled; their own `status = "disabled"` simply means no device is populated on that address.

---

## 4. Configuration flags worth changing

Values below are only the flag names and recommended action. Passwords, SSID and MAC fields are deliberately **not reproduced** here.

| Flag | Current | Meaning / proposed change |
|---|---|---|
| `wifi_ssid_hide` | `0` | Set `1` to hide the AP name. Safe, no DTB needed |
| `wifi_enable` / `wifi_mode` | `1` / `1` | AP enabled. Leave as is unless you want station mode |
| `wifi_channel` | `6` | 2.4 GHz AP channel; change to 1/6/11 if crowded |
| `wifi_code` / `wifi_chn` | `US` / `36` | Regulatory domain / 5 GHz channel |
| `gps_info` | `0` | Show GPS info. Needs `uart1` enabled **and** the path fix (`dev/ttyS1` → `/dev/ttyS1`) |
| `gps_baud` | `9600` | Match your GPS module |
| `bFMenable` | `0` | FM off. Enabling alone will not work: `fmsend` is disabled in the DTB |
| `bFMSend` | `1` | FM transmit side; same DTB dependency |
| `AUX_enable` | `0` | AUX input |
| `ble_enable` / `ble_user` | `0` / `0` | BLE off; also depends on `btlpm` and real BT hardware |
| `PBT_enable` / `bUserBluetooth` | `1` / `1` | Classic Bluetooth already on |
| `car_osd` | `0` | Overlay for camera guidelines |
| `stream_cam` | `0` | Camera streaming |
| `screen_filp` | `0` | Rotates/flips the display image |
| `switch_sys_psd` | `0` | Password prompt. Separate `admin_sys_psd` / `sys_psd` fields exist |
| `boot_voice` / `touchtone` / `voice_ctl` | `1` | Startup sound, touch sound, voice control |
| `hour24` / `date_format` / `zone` | `1` / `0` / `480` | Time format and timezone |
| `language` | `english` | UI language |
| `lcd_info` | `RX 854x480` | Panel description; confirms 854×480 |
| `software` | `M750 2026-08-15` | Version string shown in settings |

---

## 5. XML switches found

These are UI controls in `data/res/layout/`. Changing their XML attributes can hide/show options without touching the app binary:

| File | Switch / status |
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

## 6. Recommended order of changes

1. **Hide the WiFi SSID** — one XML flag, reversible, no firmware rebuild.
2. **Enable the UART console** via `/etc/inittab` (`ttyS0`) — not a DTB change, low risk, gives permanent serial access.
3. **Enable `uart1` for GPS** — DTB edit **plus** fix `dev/ttyS1` → `/dev/ttyS1` in `config_devmng.xml`.
4. **Enable `rtc@7090000`** — low risk, useful for correct dates.
5. **Enable `twi0` / `twi1`** — only if you actually plan to attach I2C devices.
6. **Show/hide UI switches** — XML only, fully reversible from the overlay.

Do **not** enable: PMU/charger nodes, `e907_rproc`, camera/VIN nodes, SPI boot controllers, or `gmac0` without wiring and a verified DTB location.

---

## 7. How to apply a DTB change (once located)

```sh
dtc -I dtb -O dts dtb_descomprimido.bin > board.dts
# edit only the chosen status lines: "disabled" -> "okay"
dtc -I dts -O dtb board.dts > board_patched.dtb
```

Then find where `board_patched.dtb` belongs in the boot image and rebuild that partition. Until then, keep the change in the `.dts` as documentation only.

For live confirmation on the device, copy [`files/debug1-audit-dtb.sh`](../files/debug1-audit-dtb.sh) as `debug1`; it writes the same data to `F:\audit\` without modifying the firmware.
