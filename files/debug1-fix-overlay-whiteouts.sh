#!/bin/sh
# ==============================================================================
# debug1 v9 - limpia los whiteouts del overlay que ocultan las imagenes del
# rootfs nuevo grabado en mtdblock2.
#
# El script de grabacion borro /data/res/pic/image.bin.lzma y las 9 imagenes
# desde el overlay (upperdir). En overlayfs eso crea whiteouts que siguen
# ocultando los archivos del rootfs recien grabado. Hay que borrar esos
# whiteouts en /overlay/upper, no en /data.
#
# No copia nada al overlay: las imagenes ya estan en el squashfs nuevo.
# ==============================================================================

LOG=/mnt/extsd/debug1.log
FLAG=/mnt/extsd/overlay_fix.done
BB=/mnt/extsd/busybox_net
UP=/overlay/upper/data/res/pic

log() { echo "[debug1] $*" >> "$LOG" 2>/dev/null; }

: > "$LOG"
log "=== INICIO $(date) ==="

if [ -d /overlay/upper ]; then
    log "limpiando whiteouts en $UP"
    for p in image.bin.lzma \
             bin/hm_bg.jpg \
             bin/hm_auto_icon.png \
             bin/hm_hicar_icon.png \
             bin/hm_gps_icon_0.png \
             bin/hm_gps_icon_1.png \
             bin/hm_gps_icon_2.png \
             bin/hm_gps_icon_3.png \
             bin/hm_gps_icon_4.png \
             bin/hm_gps_icon_5.png; do
        if [ -e "$UP/$p" ] || [ -c "$UP/$p" ] || [ -L "$UP/$p" ]; then
            if rm -f "$UP/$p" 2>>"$LOG"; then
                log "  borrado upper: $p"
            else
                log "  ERROR borrando upper: $p"
            fi
        else
            log "  sin entrada upper: $p"
        fi
    done

    # Por si quedaron copias sueltas o whiteouts en el directorio padre
    rm -f /overlay/upper/data/res/pic/bin/hm_bg.jpg 2>/dev/null
else
    log "ERROR: no existe /overlay/upper"
fi

# Forzar a sdvcam a extraer de nuevo el paquete desde el rootfs
rm -f /tmp/image.bin 2>/dev/null
sync

log "=== verificacion ==="
if [ -f /data/res/pic/image.bin.lzma ]; then
    log "image.bin.lzma visible: $(md5sum /data/res/pic/image.bin.lzma 2>/dev/null | awk '{print $1}')"
else
    log "ERROR: image.bin.lzma NO visible"
fi
for n in hm_bg.jpg hm_auto_icon.png hm_gps_icon_0.png; do
    if [ -f "/data/res/pic/bin/$n" ]; then
        log "$n visible: $(md5sum "/data/res/pic/bin/$n" 2>/dev/null | awk '{print $1}')"
    else
        log "ERROR: $n NO visible"
    fi
done

echo ok > "$FLAG" 2>/dev/null
log "creado $FLAG - apaga y enciende SIN SD"

if [ -x "$BB" ]; then
    "$BB" telnetd -p 23 -l /bin/sh >> "$LOG" 2>&1 &
    sleep 1
    if pidof busybox_net >/dev/null 2>&1 || ps | grep -q '[t]elnetd'; then
        log "telnetd ACTIVO en puerto 23"
    fi
fi

log "=== FIN $(date) ==="
exit 0
