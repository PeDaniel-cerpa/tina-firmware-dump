#!/bin/sh
# ==============================================================================
# debug1 v8 - graba un rootfs (mtdblock2) con las imagenes personalizadas ya
# integradas. No depende de la SD despues de grabar.
#
# Solo actua si:
#   - existe /mnt/extsd/mtdblock2_custom.bin
#   - NO existe /mnt/extsd/rootfs_custom.done
#
# Antes de grabar:
#   - guarda el mtdblock2 original en la SD (una sola vez)
#   - borra del overlay los archivos que instalo el debug1 anterior
#
# Despues de grabar verifica MD5 y crea rootfs_custom.done.
# NO toca bootlogo (mtd5) ni SSID (overlay/data).
# ==============================================================================

LOG=/mnt/extsd/debug1.log
IMG=/mnt/extsd/mtdblock2_custom.bin
BAK=/mnt/extsd/mtdblock2_original_backup.bin
FLAG=/mnt/extsd/rootfs_custom.done
TMP=/tmp/mtdblock2_custom.bin
BB=/mnt/extsd/busybox_net

EXPECTED=4c2936a8c8b81c75a9274f332f975f1d

log() { echo "[debug1] $*" >> "$LOG" 2>/dev/null; }

: > "$LOG"
log "=== INICIO $(date) ==="

if [ ! -f "$IMG" ]; then
    log "ERROR: no existe $IMG"
    exit 0
fi

if [ -f "$FLAG" ]; then
    log "rootfs_custom.done existe -> rootfs ya grabado, omito"
else
    # --- 1) copia de seguridad del rootfs actual ------------------------------
    if [ ! -f "$BAK" ]; then
        log "guardando rootfs original en $BAK"
        dd if=/dev/mtdblock2 of="$BAK" bs=4096 >> "$LOG" 2>&1
        sync
    else
        log "backup del rootfs ya existe"
    fi

    # --- 2) copiar imagen a /tmp y verificar ----------------------------------
    log "copiando imagen personalizada a /tmp"
    cat "$IMG" > "$TMP" 2>>"$LOG"

    A=$(md5sum "$IMG" 2>/dev/null | awk '{print $1}')
    C=$(md5sum "$TMP" 2>/dev/null | awk '{print $1}')
    log "MD5 SD   : $A"
    log "MD5 /tmp : $C"
    log "MD5 esperado: $EXPECTED"

    if [ -z "$A" ] || [ "$A" != "$C" ] || [ "$A" != "$EXPECTED" ]; then
        log "ERROR: la imagen no paso la verificacion. No se graba nada."
    else
        # --- 3) limpiar restos del overlay del debug1 anterior ----------------
        log "limpiando restos del overlay"
        rm -f /data/res/pic/image.bin.lzma 2>/dev/null
        rm -f /tmp/image.bin 2>/dev/null
        for n in hm_bg.jpg hm_auto_icon.png hm_hicar_icon.png \
                 hm_gps_icon_0.png hm_gps_icon_1.png hm_gps_icon_2.png \
                 hm_gps_icon_3.png hm_gps_icon_4.png hm_gps_icon_5.png; do
            rm -f "/data/res/pic/bin/$n" 2>/dev/null
        done
        rm -f /mnt/extsd/ui_custom.done 2>/dev/null

        # --- 4) grabar rootfs -------------------------------------------------
        log "grabando mtdblock2 (13303808 bytes)"
        dd if="$TMP" of=/dev/mtdblock2 bs=4096 >> "$LOG" 2>&1
        sync

        B=$(md5sum /dev/mtdblock2 2>/dev/null | awk '{print $1}')
        log "MD5 leido   : $B"

        if [ -n "$B" ] && [ "$B" = "$EXPECTED" ]; then
            log "ROOTFS GRABADO Y VERIFICADO"
            echo ok > "$FLAG" 2>/dev/null
            log "creado $FLAG"
            log "APAGA Y ENCIENDE para usar el rootfs nuevo"
        else
            log "ERROR: verificacion fallida. No se creo $FLAG."
        fi
    fi
fi

# --- 5) shell root por IP -----------------------------------------------------
if [ -x "$BB" ]; then
    "$BB" telnetd -p 23 -l /bin/sh >> "$LOG" 2>&1 &
    sleep 1
    if pidof busybox_net >/dev/null 2>&1 || ps | grep -q '[t]elnetd'; then
        log "telnetd ACTIVO en puerto 23"
    else
        log "telnetd no quedo activo"
    fi
fi

log "=== FIN $(date) ==="
exit 0
