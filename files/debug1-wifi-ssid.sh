#!/bin/sh
# ==============================================================================
# debug1 v5 - cambia el SSID del AP WiFi a "Hunk-125r" desde la SD
#
# El SSID real esta en /data/param.bin (offset 2136, slot de 64 bytes), no solo
# en el XML. Este script:
#   - guarda copias de seguridad en la SD (una sola vez)
#   - copia param_hunk.bin y config_devmng_hunk.xml a /data y al overlay
#   - vuelca /tmp/apmac.txt a la SD para diagnosticar el sufijo de MAC
#   - crea wifi_ssid.done solo al terminar
#   - deja el volcado de firmware y telnetd como en las versiones anteriores
#
# IMPORTANTE: nombre exacto "debug1" en la raiz de la SD, saltos LF.
# ==============================================================================

LOG=/mnt/extsd/debug1.log
DUMP=/mnt/extsd/firmware_dump
IMG=/mnt/extsd/bootlogo.bin
FLAG=/mnt/extsd/bootlogo.done
PARAM=/data/param.bin
PARAM_SRC=/mnt/extsd/param_hunk.bin
XML=/data/res/param/config_devmng.xml
XML_SRC=/mnt/extsd/config_devmng_hunk.xml
SSIDFLAG=/mnt/extsd/wifi_ssid.done
NEWSSID=Hunk-125r

log() { echo "[debug1] $*" >> "$LOG" 2>/dev/null; }

: > "$LOG"
log "=== INICIO $(date) ==="

mkdir -p "$DUMP" 2>/dev/null

# --- 1) Informacion -----------------------------------------------------------
{
    echo "FECHA: $(date)"
    echo "CMDLINE: $(cat /proc/cmdline 2>/dev/null)"
    echo "--- /proc/mtd ---";   cat /proc/mtd 2>/dev/null
    echo "--- mounts ---";      cat /proc/mounts 2>/dev/null
    echo "--- ifconfig ---";    ifconfig 2>/dev/null
} > "$DUMP/info.txt" 2>&1
log "info.txt listo"

# --- 2) Volcado MTD -----------------------------------------------------------
for m in /dev/mtdblock*; do
    [ -e "$m" ] || continue
    n=${m##*/}
    dd if="$m" of="$DUMP/$n.bin" bs=64k >> "$LOG" 2>&1
done
log "volcado MTD listo"

# --- 3) Bootlogo (se salta porque bootlogo.done ya existe) --------------------
if [ -f "$IMG" ] && [ ! -f "$FLAG" ]; then
    log "AVISO: bootlogo.done no existe; se omite el logo para no interferir"
else
    log "bootlogo.done existe -> no se toca bootlogo"
fi

# --- 4) Cambiar SSID del AP ---------------------------------------------------
if [ -f "$PARAM_SRC" ] && [ ! -f "$SSIDFLAG" ]; then
    log "cambiando SSID del AP a $NEWSSID"

    # Backups una sola vez
    if [ -f "$PARAM" ] && [ ! -f /mnt/extsd/param.bin.bak ]; then
        cp "$PARAM" /mnt/extsd/param.bin.bak 2>/dev/null
    fi
    if [ -f "$XML" ] && [ ! -f /mnt/extsd/config_devmng.xml.bak ]; then
        cp "$XML" /mnt/extsd/config_devmng.xml.bak 2>/dev/null
    fi

    # param.bin: slot 2136 = SSID completo, slot 2200 = prefijo
    cat "$PARAM_SRC" > /tmp/param.bin 2>>"$LOG"
    ls -l /tmp/param.bin >> "$LOG" 2>&1

    cp /tmp/param.bin "$PARAM" 2>>"$LOG"
    mkdir -p /overlay/upper/data 2>/dev/null
    cp /tmp/param.bin /overlay/upper/data/param.bin 2>>"$LOG"

    # XML: copiar version parcheada y ademas forzar los dos nombres por si acaso
    if [ -f "$XML_SRC" ]; then
        mkdir -p /data/res/param 2>/dev/null
        cp "$XML_SRC" "$XML" 2>>"$LOG"
        mkdir -p /overlay/upper/data/res/param 2>/dev/null
        cp "$XML_SRC" /overlay/upper/data/res/param/config_devmng.xml 2>>"$LOG"
    fi
    sed -i "s/wifi_ap_ssid=\"[^\"]*\"/wifi_ap_ssid=\"$NEWSSID\"/g" "$XML" 2>>"$LOG"
    sed -i "s/wifiApSsid=\"[^\"]*\"/wifiApSsid=\"$NEWSSID\"/g" "$XML" 2>>"$LOG"
    sed -i "s/wifi_ap_ssid=\"[^\"]*\"/wifi_ap_ssid=\"$NEWSSID\"/g" /overlay/upper/data/res/param/config_devmng.xml 2>>"$LOG"
    sed -i "s/wifiApSsid=\"[^\"]*\"/wifiApSsid=\"$NEWSSID\"/g" /overlay/upper/data/res/param/config_devmng.xml 2>>"$LOG"

    # Diagnostico: MAC del AP y valores finales del XML
    cp /tmp/apmac.txt "$DUMP/apmac.txt" 2>/dev/null
    log "apmac.txt: $(cat /tmp/apmac.txt 2>/dev/null)"
    grep -n 'wifi_ap_ssid\|wifiApSsid\|wifi_ap_password' "$XML" >> "$LOG" 2>&1

    echo ok > "$SSIDFLAG" 2>/dev/null
    log "SSID CONFIGURADO -> $NEWSSID (creado $SSIDFLAG)"
else
    if [ -f "$SSIDFLAG" ]; then
        log "wifi_ssid.done existe -> omito cambio de SSID"
    else
        log "no hay param_hunk.bin en la SD -> omito cambio de SSID"
    fi
fi

# --- 5) Shell root por IP -----------------------------------------------------
if [ -x /mnt/extsd/busybox_net ]; then
    /mnt/extsd/busybox_net telnetd -p 23 -l /bin/sh >> "$LOG" 2>&1 &
    sleep 1
    if pidof busybox_net >/dev/null 2>&1 || ps | grep -q '[t]elnetd'; then
        log "telnetd ACTIVO en puerto 23"
    else
        log "telnetd no quedo activo; ver errores arriba"
    fi
fi

log "=== FIN $(date) ==="
exit 0
