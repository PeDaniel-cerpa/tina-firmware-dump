#!/usr/bin/env bash
# ==============================================================================
# make_bootlogo_fill.sh - bootlogo recortando para LLENAR 854x480
#
# Igual que make_bootlogo.sh, pero en vez de dejar barras negras escala la
# imagen hasta cubrir todo el panel y recorta el centro. Util para fondos
# panoramicos (por ejemplo 1921x700).
#
# Uso:
#   ./make_bootlogo_fill.sh imagen.webp bootlogo.bin
# ==============================================================================
set -euo pipefail

IN="${1:-}"
OUT="${2:-bootlogo.bin}"
W=854
H=480
SIZE=131072

if [ -z "$IN" ] || [ ! -f "$IN" ]; then
    echo "Uso: $0 <imagen.webp|png|jpg> [bootlogo.bin]" >&2
    exit 1
fi

TMP=$(mktemp --suffix=.jpg)
trap 'rm -f "$TMP"' EXIT

echo "[*] Escalando a ${W}x${H} (crop central) y convirtiendo a JPEG baseline..."
ffmpeg -y -loglevel error -i "$IN" \
    -vf "scale=${W}:${H}:force_original_aspect_ratio=increase,crop=${W}:${H}" \
    -q:v 2 -pix_fmt yuvj420p "$TMP"

JPEG_SIZE=$(stat -c%s "$TMP")
if [ "$JPEG_SIZE" -gt "$SIZE" ]; then
    echo "ERROR: el JPEG ocupa $JPEG_SIZE bytes, mas que la particion ($SIZE)." >&2
    exit 1
fi

echo "[*] Rellenando con 0xFF hasta $SIZE bytes..."
cp "$TMP" "$OUT"
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
