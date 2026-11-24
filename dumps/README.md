# Volcados completos de las dos placas

Dos imágenes **crudas de 16 MiB** de SPI NOR, copiadas byte a byte de cada placa. Se incluyen porque permiten repetir exactamente la recuperación documentada en [docs/18-recuperacion-m750-por-uart.es.md](../docs/18-recuperacion-m750-por-uart.es.md).

| Placa | Archivo | Tamaño | MD5 | SHA256 | CRC32 |
|---|---|---:|---|---|---|
| TF811 / Podofo A4628 | [`TF811/TF811_16MB_stock.bin`](TF811/TF811_16MB_stock.bin) | 16777216 | `f27afaa19483040e18aa6a03b5a9b339` | `a35950c009939ffa471e54a5994c4acc08b46cd0c0a160d0ffcd11ba6dd0e167` | `bcad5ce4` |
| M750 | [`M750/M750_16MB_stock.bin`](M750/M750_16MB_stock.bin) | 16777216 | `8c0abbd6e0f327e5d9ab38146a90f5ca` | `f0bd763cff93f829b2cdabc026489c30b922b754c2a32053645ae90ac7f26dea` | `aed73153` |

Verificación rápida:

```bash
cd dumps
sha256sum -c CHECKSUMS.sha256
```

## Origen

- **TF811**: volcado de la unidad abierta (Podofo A4628) por UART/U-Boot + consola Linux. Target en el firmware: `v837s-perf1/generic v2.1`. Es la base de la [doc 11](../docs/11-volcado-podofo-a4628-uart.es.md).
- **M750**: volcado por el hook `debug1` de la SD (`/mnt/extsd/debug1`), luego verificado y regrabado por UART. Coincide byte a byte con la concatenación de `mtdblock0.bin` … `mtdblock7.bin` de esa placa (MD5 `8c0abbd6…`).

## Aviso

Estos archivos contienen **identificadores únicos del dispositivo** (MAC, `id.txt`, `tyre.txt`/TPMS, calibraciones). Son necesarios para una restauración fiel, pero revisa las políticas de privacidad antes de redistribuirlos. `examples/info-M750.txt` ya contiene datos del equipo y se conserva por el mismo motivo.

## Particiones

La M750 usa este layout (erase block `0x10000`):

| MTD | Offset | Tamaño | Nombre | CRC32 en el dump |
|---|---:|---:|---|---|
| mtd0 | `0x000000` | `0x060000` | uboot / boot0 + U-Boot | `5560ecb6` (boot0 `0x0..0x10000`) |
| mtd1 | `0x060000` | `0x230000` | boot | `43260230` |
| mtd2 | `0x290000` | `0xcb0000` | rootfs | `3038e714` |
| mtd3 | `0xf40000` | `0x050000` | rootfs_data | — |
| mtd4 | `0xf90000` | `0x020000` | env | `a3293403` |
| mtd5 | `0xfb0000` | `0x020000` | bootlogo | `ce3c4937` |
| mtd6 | `0xfd0000` | `0x010000` | private | — |
| mtd7 | `0xfe0000` | `0x020000` | UDISK | — |

Para dividir un dump en particiones:

```bash
mkdir -p mtd
dd if=M750/M750_16MB_stock.bin of=mtd/mtdblock0.bin bs=64K skip=0   count=6
dd if=M750/M750_16MB_stock.bin of=mtd/mtdblock1.bin bs=64K skip=6   count=35
dd if=M750/M750_16MB_stock.bin of=mtd/mtdblock2.bin bs=64K skip=41  count=203
dd if=M750/M750_16MB_stock.bin of=mtd/mtdblock3.bin bs=64K skip=244 count=5
dd if=M750/M750_16MB_stock.bin of=mtd/mtdblock4.bin bs=64K skip=249 count=2
dd if=M750/M750_16MB_stock.bin of=mtd/mtdblock5.bin bs=64K skip=251 count=2
dd if=M750/M750_16MB_stock.bin of=mtd/mtdblock6.bin bs=64K skip=253 count=1
dd if=M750/M750_16MB_stock.bin of=mtd/mtdblock7.bin bs=64K skip=254 count=2
```

El `rootfs` de fábrica de la M750 (`mtdblock2`) tiene MD5 `43acc068c9d79de63e480970d2ff72e3`; el bootlogo vigente (`mtdblock5`) tiene MD5 `d105460a6164c8d5e861f337b429f873`.
