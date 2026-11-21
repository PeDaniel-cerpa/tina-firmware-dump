#!/usr/bin/env bash
# ==============================================================================
# verify_sd.sh - verifica una imagen o una SD ya escrita
#
# Uso:
#   ./verify_sd.sh firmware_dump.img     # verificar imagen
#   ./verify_sd.sh /dev/sdb              # verificar SD (requiere root)
#   ./verify_sd.sh /mnt/f                # verificar SD montada
# ==============================================================================
set -euo pipefail

TARGET="${1:-firmware_dump.img}"

echo "=== Verificando: $TARGET ==="
echo

if [ -b "$TARGET" ]; then
    echo "[*] Es un dispositivo de bloques, montando temporalmente..."
    MNT="$(mktemp -d)"
    mount -t vfat "$TARGET" "$MNT" 2>/dev/null || \
        mount -t vfat "${TARGET}1" "$MNT" 2>/dev/null || {
            echo "ERROR: no se pudo montar. Prueba a usar la imagen .img" >&2
            exit 1
        }
    CONTENT="$MNT"
elif [ -d "$TARGET" ]; then
    CONTENT="$TARGET"
elif [ -f "$TARGET" ]; then
    if command -v mdir >/dev/null 2>&1; then
        mdir -i "$TARGET" ::/
        echo
        echo "[OK] Imagen FAT32 leible"
        exit 0
    else
        echo "ERROR: para imagenes .img necesitas mtools (sudo apt install mtools)" >&2
        exit 1
    fi
else
    echo "ERROR: '$TARGET' no existe" >&2
    exit 1
fi

echo "[*] Contenido:"
ls -la "$CONTENT"

echo
STATUS=0
for f in debug1 busybox_net; do
    if [ -f "$CONTENT/$f" ]; then
        SZ="$(stat -c%s "$CONTENT/$f")"
        echo "[OK] $f presente ($SZ bytes)"
    else
        echo "[FALTA] $f" >&2
        STATUS=1
    fi
done

if [ -f "$CONTENT/debug1" ]; then
    CRLF="$(grep -c $'\r' "$CONTENT/debug1" || true)"
    if [ "$CRLF" -eq 0 ]; then
        echo "[OK] debug1 usa saltos de linea LF"
    else
        echo "[AVISO] debug1 tiene $CRLF lineas con CR: ejecuta sed -i 's/\\r$//' debug1" >&2
        STATUS=1
    fi
fi

exit "$STATUS"
