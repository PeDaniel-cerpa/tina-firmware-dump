#!/bin/sh
# ==============================================================================
# debug1 v6 - tema rojo Marlboro para el menu de la pantalla
#
# Aplica:
#   - XML de la interfaz: verde -> 210|20|20
#   - imagenes sueltas del fondo/secuencia GPS -> versiones rojas
#   - /data/res/pic/image.bin.lzma -> paquete parcheado (usado por sdvcam)
#
# Todo se sirve desde /mnt/extsd/ui_red mediante enlaces simbolicos, para no
# agotar los 320 KB del overlay jffs2. La SD debe quedar insertada.
# NO toca el bootlogo ni el SSID WiFi.
# ==============================================================================

LOG=/mnt/extsd/debug1.log
D=/mnt/extsd/ui_red
FLAG=/mnt/extsd/ui_red.done
BB=/mnt/extsd/busybox_net

log() { echo "[debug1] $*" >> "$LOG" 2>/dev/null; }

: > "$LOG"
log "=== INICIO $(date) ==="

if [ -d "$D" ]; then
    if [ -f "$FLAG" ]; then
        log "ui_red.done existe -> tema rojo ya aplicado, omito"
    else
        log "aplicando tema rojo Marlboro desde $D"

        # --- 1) XML de la interfaz -------------------------------------------
        nxml=0
        err=0
        for f in "$D"/xml/*.xml; do
            [ -f "$f" ] || continue
            name=${f##*/}
            if cp "$f" "/data/res/layout/$name" 2>>"$LOG"; then
                nxml=$((nxml + 1))
            else
                log "ERROR copiando XML $name"
                err=1
            fi
        done
        log "XML parcheados: $nxml"

        # --- 2) imagenes sueltas (fondo + secuencia GPS + demas verdes) ------
        mkdir -p /data/res/pic/bin 2>/dev/null
        npic=0
        for f in "$D"/pic/*; do
            [ -f "$f" ] || continue
            name=${f##*/}
            rm -f "/data/res/pic/bin/$name" 2>/dev/null
            ln -s "$f" "/data/res/pic/bin/$name" 2>>"$LOG"
            npic=$((npic + 1))
        done
        log "imagenes enlazadas: $npic"

        # --- 3) paquete de imagenes que usa sdvcam ---------------------------
        if [ -f "$D/image.bin.lzma" ]; then
            rm -f /data/res/pic/image.bin.lzma 2>/dev/null
            ln -s "$D/image.bin.lzma" /data/res/pic/image.bin.lzma 2>>"$LOG"
            rm -f /tmp/image.bin 2>/dev/null
            log "image.bin.lzma parcheado enlazado; /tmp/image.bin borrado"
        else
            log "ERROR: falta $D/image.bin.lzma"
            err=1
        fi

        sync
        if [ "$err" -eq 0 ]; then
            echo ok > "$FLAG" 2>/dev/null
            log "TEMA ROJO APLICADO (creado $FLAG)"
        else
            log "TEMA NO APLICADO: hubo errores; revise debug1.log"
        fi
    fi
else
    log "ERROR: no existe $D; no se aplica el tema"
fi

# --- 4) Shell root por IP (como en versiones anteriores) ---------------------
if [ -x "$BB" ]; then
    "$BB" telnetd -p 23 -l /bin/sh >> "$LOG" 2>&1 &
    sleep 1
    if pidof busybox_net >/dev/null 2>&1 || ps | grep -q '[t]elnetd'; then
        log "telnetd ACTIVO en puerto 23"
    else
        log "telnetd no quedo activo; ver errores arriba"
    fi
fi

log "=== FIN $(date) ==="
exit 0
