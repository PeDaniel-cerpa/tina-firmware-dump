#!/usr/bin/env bash
# ==============================================================================
# make_bootlogo.sh - convierte una imagen en el bootlogo de la pantalla
#
# La particion "bootlogo" (mtdblock5) es un JPEG baseline de 854x480 rellenado
# con 0xFF hasta 131072 bytes (128 KB). No hay cabecera especial.
#
# Uso:
#   ./make_bootlogo.sh imagen_entrada.png bootlogo.bin
#
# Requisitos: ffmpeg (o ImageMagick convert)
# ==============================================================================
set -euo pipefail

IN="${1:-}"
OUT="${2:-bootlogo.bin}"
W=854
H=480
SIZE=131072

if [ -z "$IN" ] || [ ! -f "$IN" ]; then
    echo "Uso: $0 <imagen.png|jpg> [bootlogo.bin]" >&2
    exit 1
fi

TMP=$(mktemp --suffix=.jpg)
trap 'rm -f "$TMP"' EXIT

echo "[*] Redimensionando a ${W}x${H} y convirtiendo a JPEG baseline..."
if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -y -loglevel error -i "$IN" \
        -vf "scale=${W}:${H}:force_original_aspect_ratio=decrease,pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2:black" \
        -q:v 2 -pix_fmt yuvj420p "$TMP"
elif command -v convert >/dev/null 2>&1; then
    convert "$IN" -resize "${W}x${H}" -background black -gravity center \
        -extent "${W}x${H}" -quality 92 "$TMP"
else
    echo "ERROR: necesitas ffmpeg o ImageMagick (convert)" >&2
    exit 1
fi

JPEG_SIZE=$(stat -c%s "$TMP")
if [ "$JPEG_SIZE" -gt "$SIZE" ]; then
    echo "ERROR: el JPEG ocupa $JPEG_SIZE bytes, mas que la particion ($SIZE)." >&2
    echo "Baja la calidad (-q:v 4 en ffmpeg / -quality 80 en convert)." >&2
    exit 1
fi

echo "[*] Rellenando con 0xFF hasta $SIZE bytes..."
cp "$TMP" "$OUT"
# truncar/expandir a 131072 bytes (los bytes nuevos salen a 0; los rellenamos)
truncate -s "$SIZE" "$OUT"
python3 - "$OUT" "$JPEG_SIZE" <<'PY'
import sys
p, start = sys.argv[1], int(sys.argv[2])
with open(p, 'r+b') as f:
    f.seek(start)
    f.write(b'\xff' * (131072 - start))
PY

echo "[OK] $OUT generado ($(stat -c%s "$OUT") bytes)"
file "$OUT"
echo
echo "Copialo a la SD:  cp $OUT /mnt/extsd/bootlogo.bin"
echo "y escribelo desde la shell de la pantalla con los comandos del manual."
