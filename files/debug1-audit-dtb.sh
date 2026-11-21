#!/bin/sh
# ==============================================================================
# debug1 v10 - AUDIT READ-ONLY desde la pantalla
#
# No modifica el firmware. Solo escribe en la SD:
#   /mnt/extsd/audit/
#     device-tree/      copia de /proc/device-tree
#     node_status.txt   todos los nodos con su status (disabled/okay/...)
#     disabled.txt      solo los nodos status="disabled"
#     layout/           copia de /data/res/layout/*.xml
#     xml_flags.txt     lineas con flags enable/disable/visible/...
#     init.d/           copia de /etc/init.d
#     inittab.txt       /etc/inittab
#     binaries.txt      ejecutables en /bin /sbin /usr/bin /usr/sbin
#     system.txt        cmdline, mtd, mounts, uname, ps, ifconfig
#     param.bin         copia del parametro (SSID, etc.) - privado
#     audit.log         log de ejecucion
#
# Deja telnetd activo en el puerto 23 para inspeccion en vivo.
# Crea /mnt/extsd/audit.done al terminar.
# ==============================================================================

LOG=/mnt/extsd/audit/audit.log
AUDIT=/mnt/extsd/audit
FLAG=/mnt/extsd/audit.done
BB=/mnt/extsd/busybox_net

mkdir -p "$AUDIT" 2>/dev/null
: > "$LOG" 2>/dev/null

log() { echo "[audit] $*" >> "$LOG" 2>/dev/null; }

log "=== INICIO $(date) ==="

# --- 1) Informacion general ---------------------------------------------------
{
    echo "===== uname ====="; uname -a 2>/dev/null
    echo "===== cmdline ====="; cat /proc/cmdline 2>/dev/null
    echo "===== mtd ====="; cat /proc/mtd 2>/dev/null
    echo "===== partitions ====="; cat /proc/partitions 2>/dev/null
    echo "===== mounts ====="; cat /proc/mounts 2>/dev/null
    echo "===== ps ====="; ps w 2>/dev/null
    echo "===== ifconfig ====="; ifconfig 2>/dev/null
} > "$AUDIT/system.txt" 2>>"$LOG"
log "system.txt escrito"

# --- 2) Device Tree -----------------------------------------------------------
DT=/proc/device-tree
[ -d "$DT" ] || DT=/sys/firmware/devicetree/base

if [ -d "$DT" ]; then
    mkdir -p "$AUDIT/device-tree" 2>/dev/null
    cp -R "$DT"/. "$AUDIT/device-tree/" 2>>"$LOG"
    log "device-tree copiado desde $DT"

    find "$DT" -name status -type f 2>/dev/null | sort | while read -r f; do
        p=${f%/status}
        s=$(cat "$f" 2>/dev/null)
        echo "$s | $p"
    done > "$AUDIT/node_status.txt" 2>>"$LOG"

    grep '^disabled' "$AUDIT/node_status.txt" > "$AUDIT/disabled.txt" 2>/dev/null
    log "nodos con status: $(wc -l < "$AUDIT/node_status.txt" 2>/dev/null)"
    log "nodos disabled: $(grep -c '^disabled' "$AUDIT/node_status.txt" 2>/dev/null)"
else
    log "ERROR: no se encontro device-tree"
fi

# --- 3) XML de la interfaz ----------------------------------------------------
if [ -d /data/res/layout ]; then
    mkdir -p "$AUDIT/layout" 2>/dev/null
    cp -R /data/res/layout/. "$AUDIT/layout/" 2>>"$LOG"
    grep -RInE 'enable|disable|visible|show|hide|switch|open|close|flag|status' \
        /data/res/layout/*.xml 2>/dev/null | head -800 \
        > "$AUDIT/xml_flags.txt" 2>>"$LOG"
    log "layout copiado; flags: $(wc -l < "$AUDIT/xml_flags.txt" 2>/dev/null) lineas"
fi

# --- 4) Servicios, inittab y binarios -----------------------------------------
if [ -d /etc/init.d ]; then
    mkdir -p "$AUDIT/init.d" 2>/dev/null
    cp -R /etc/init.d/. "$AUDIT/init.d/" 2>>"$LOG"
    log "init.d copiado"
fi
[ -f /etc/inittab ] && cp /etc/inittab "$AUDIT/inittab.txt" 2>>"$LOG"

{
    for d in /bin /sbin /usr/bin /usr/sbin; do
        [ -d "$d" ] || continue
        find "$d" -maxdepth 1 -type f -perm -u+x 2>/dev/null
        find "$d" -maxdepth 1 -type l 2>/dev/null
    done
} | sort > "$AUDIT/binaries.txt" 2>>"$LOG"
log "binarios: $(wc -l < "$AUDIT/binaries.txt" 2>/dev/null)"

# --- 5) Parametros (contiene SSID; no subir a internet) -----------------------
for f in /data/param.bin /data/config_devmng.xml /data/res/config/config_devmng.xml; do
    [ -f "$f" ] && cp "$f" "$AUDIT/" 2>>"$LOG"
done
log "parametros copiados"

# --- 6) Resumen ---------------------------------------------------------------
sync
echo ok > "$FLAG" 2>/dev/null
log "creado $FLAG"
log "=== FIN $(date) ==="

# --- 7) Shell root por IP -----------------------------------------------------
if [ -x "$BB" ]; then
    "$BB" telnetd -p 23 -l /bin/sh >> "$LOG" 2>&1 &
    sleep 1
    if pidof busybox_net >/dev/null 2>&1 || ps | grep -q '[t]elnetd'; then
        log "telnetd ACTIVO en puerto 23"
    fi
fi

exit 0
