#!/usr/bin/env bash
# ==============================================================================
# make_sd_image.sh - crea una imagen FAT32 "superfloppy" para la pantalla
#
# La imagen NO tiene tabla de particiones (no MBR). El firmware monta
# /dev/mmcblk0 (disco entero), por lo que una SD MBR normal no funciona.
#
# Uso:
#   ./make_sd_image.sh [archivo.img] [tamano_MB]
#
# Ejemplo:
#   ./make_sd_image.sh firmware_dump.img 1024
#
# Requisitos:
#   sudo apt install -y dosfstools mtools
# ==============================================================================
set -euo pipefail

IMG="${1:-firmware_dump.img}"
SIZE_MB="${2:-1024}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="$SCRIPT_DIR/../files"

for tool in mkfs.fat mcopy mdir; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: falta '$tool'. Instalalo con:" >&2
        echo "  sudo apt install -y dosfstools mtools" >&2
        exit 1
    fi
done

for f in debug1 busybox_net; do
    if [ ! -f "$FILES_DIR/$f" ]; then
        echo "ERROR: no encuentro $FILES_DIR/$f" >&2
        exit 1
    fi
done

echo "[*] Creando imagen de ${SIZE_MB} MB: $IMG"
rm -f "$IMG"
truncate -s "${SIZE_MB}M" "$IMG"

echo "[*] Formateando como FAT32 (sin MBR)"
mkfs.fat -F 32 -s 4 -n "FIRMWARE" "$IMG" >/dev/null

echo "[*] Copiando archivos a la raiz"
mcopy -i "$IMG" -o "$FILES_DIR/debug1"      ::/debug1
mcopy -i "$IMG" -o "$FILES_DIR/busybox_net" ::/busybox_net

echo "[*] Contenido de la imagen:"
mdir -i "$IMG" ::/

echo
echo "[OK] Imagen lista: $IMG"
echo
echo "Ahora escribela en la SD:"
echo "  sudo dd if=$IMG of=/dev/sdX bs=4M status=progress conv=fsync"
echo "(sustituye /dev/sdX por tu SD; compruebalo con lsblk)"
