#!/bin/sh
# ==============================================================================
# debug1 - ejecutado como root desde /mnt/extsd al arrancar (TF811 / Tina Linux)
# Se activa automáticamente porque /etc/init.d/S01app ejecuta /mnt/extsd/debug1
# ==============================================================================

LOG=/mnt/extsd/debug1.log
DUMP=/mnt/extsd/firmware_dump
SHELL_PORT=4444

log() {
    echo "[debug1] $*" >> "$LOG" 2>/dev/null
}

: > "$LOG"
log "=== INICIO $(date) ==="

mkdir -p "$DUMP" 2>/dev/null

# --- 1) Info del sistema (para saber la IP real del equipo) -------------------
{
    echo "FECHA: $(date)"
    echo "CMDLINE: $(cat /proc/cmdline 2>/dev/null)"
    echo "--- /proc/mtd ---"
    cat /proc/mtd 2>/dev/null
    echo "--- /proc/partitions ---"
    cat /proc/partitions 2>/dev/null
    echo "--- /proc/mounts ---"
    cat /proc/mounts 2>/dev/null
    echo "--- ifconfig ---"
    ifconfig 2>/dev/null
    echo "--- route ---"
    route -n 2>/dev/null
} > "$DUMP/info.txt" 2>&1
log "info.txt escrito (revisa aqui la IP del equipo)"

# --- 2) Volcar particiones MTD a la SD ---------------------------------------
for m in /dev/mtdblock*; do
    [ -e "$m" ] || continue
    n=${m##*/}
    log "volcando $m -> $DUMP/$n.bin"
    dd if="$m" of="$DUMP/$n.bin" bs=64k >> "$LOG" 2>&1
done

# --- 3) Copiar configuracion / overlay / datos -------------------------------
for d in /etc /overlay /data; do
    [ -d "$d" ] || continue
    n=${d##*/}
    mkdir -p "$DUMP/$n" 2>/dev/null
    log "copiando $d -> $DUMP/$n"
    cp -Rp "$d"/. "$DUMP/$n/" >> "$LOG" 2>&1
done

# --- 4) Shell interactivo por IP (requiere el binario socat en la SD) --------
# Se lanza en background: S01app ejecuta este script de forma sincronica,
# asi que no debemos bloquear el arranque. El puerto queda enlazado al instante
# y funciona en cuanto la WiFi/eth0 levanta.
if [ -x /mnt/extsd/socat ]; then
    /mnt/extsd/socat TCP-LISTEN:$SHELL_PORT,fork,reuseaddr \
        EXEC:'/bin/sh -i',pty,stderr,setsid,sigint,sane \
        >> "$LOG" 2>&1 &
    log "socat escuchando TCP $SHELL_PORT -> nc <IP_DEL_EQUIPO> $SHELL_PORT"
else
    log "AVISO: /mnt/extsd/socat no existe -> no habra shell por IP"
fi

log "=== FIN $(date) ==="
exit 0
