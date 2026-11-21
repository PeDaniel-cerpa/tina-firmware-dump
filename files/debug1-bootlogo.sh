#!/bin/sh
# ==============================================================================
# debug1 v3 - ejecutado como root desde /mnt/extsd al arrancar
# Igual que debug1 v2, pero SI hay /mnt/extsd/bootlogo.bin lo graba en la
# particion bootlogo (mtdblock5) antes de levantar telnetd.
#
# Uso:
#   - copiar este archivo a la SD con el nombre exacto "debug1" (sin extension)
#   - copiar bootlogo.bin a la raiz de la SD
#   - arrancar la pantalla con la SD puesta
#   - al terminar, leer F:\debug1.log desde el PC
#
# El archivo F:\bootlogo.done se crea solo cuando la escritura verifico bien.
# Borralo si quieres volver a grabar el logo en otro arranque.
#
# IMPORTANTE: LF (UNIX), no CRLF. Se ejecuta de forma sincronica desde S01app.
# ==============================================================================

LOG=/mnt/extsd/debug1.log
DUMP=/mnt/extsd/firmware_dump
IMG=/mnt/extsd/bootlogo.bin
FLAG=/mnt/extsd/bootlogo.done

log() { echo "[debug1] $*" >> "$LOG" 2>/dev/null; }

: > "$LOG"
log "=== INICIO $(date) ==="

mkdir -p "$DUMP" 2>/dev/null

# --- 1) Informacion del sistema -----------------------------------------------
{
    echo "FECHA: $(date)"
    echo "CMDLINE: $(cat /proc/cmdline 2>/dev/null)"
    echo "--- /proc/mtd ---";   cat /proc/mtd 2>/dev/null
    echo "--- partitions ---";  cat /proc/partitions 2>/dev/null
    echo "--- mounts ---";      cat /proc/mounts 2>/dev/null
    echo "--- ifconfig ---";    ifconfig 2>/dev/null
    echo "--- route ---";       route -n 2>/dev/null
} > "$DUMP/info.txt" 2>&1
log "info.txt listo"

# --- 2) Volcar todas las particiones MTD --------------------------------------
for m in /dev/mtdblock*; do
    [ -e "$m" ] || continue
    n=${m##*/}
    log "volcando $m"
    dd if="$m" of="$DUMP/$n.bin" bs=64k >> "$LOG" 2>&1
done

# --- 3) Copiar configuracion --------------------------------------------------
for d in /etc /overlay /data; do
    [ -d "$d" ] || continue
    n=${d##*/}
    mkdir -p "$DUMP/$n" 2>/dev/null
    log "copiando $d"
    cp -RpL "$d"/. "$DUMP/$n/" >> "$LOG" 2>&1
done

# --- 4) Grabar el bootlogo desde la SD ----------------------------------------
if [ -f "$IMG" ] && [ ! -f "$FLAG" ]; then
    cp "$IMG" /tmp/bootlogo.bin 2>/dev/null
    SIZE=$(wc -c < /tmp/bootlogo.bin 2>/dev/null | tr -d '[:space:]')

    if [ "$SIZE" != "131072" ]; then
        log "ERROR: bootlogo.bin mide '$SIZE' bytes, se esperaban 131072. No se grabo nada."
    else
        if [ -e /dev/mtd_name/bootlogo ]; then
            TGT=/dev/mtd_name/bootlogo
        else
            TGT=/dev/mtdblock5
        fi
        log "grabando bootlogo en $TGT (131072 bytes)"

        dd if=/dev/zero of="$TGT" bs=1024 count=128 >> "$LOG" 2>&1
        dd if=/tmp/bootlogo.bin of="$TGT" bs=1024 count=128 >> "$LOG" 2>&1
        sync

        A=$(md5sum /tmp/bootlogo.bin 2>/dev/null | awk '{print $1}')
        B=$(md5sum "$TGT" 2>/dev/null | awk '{print $1}')
        log "MD5 esperado: $A"
        log "MD5 leido   : $B"

        if [ -n "$A" ] && [ "$A" = "$B" ]; then
            log "BOOTLOGO GRABADO Y VERIFICADO"
            echo ok > "$FLAG" 2>/dev/null
            log "creado $FLAG (borralo para repetir la grabacion)"
        else
            log "ERROR: verificacion fallida. No se creo $FLAG."
        fi
    fi
elif [ -f "$FLAG" ]; then
    log "bootlogo.done existe -> omito grabacion del logo"
else
    log "no hay bootlogo.bin en la SD -> omito grabacion del logo"
fi

# --- 5) Shell root por IP -----------------------------------------------------
if [ -x /mnt/extsd/busybox_net ]; then
    /mnt/extsd/busybox_net telnetd -p 23 -l /bin/sh >> "$LOG" 2>&1 &
    sleep 1
    if pidof busybox_net >/dev/null 2>&1 || ps | grep -q '[t]elnetd'; then
        log "telnetd ACTIVO en puerto 23 -> Tera Term: 192.168.10.1:23"
    else
        log "telnetd no quedo activo; ver errores arriba"
    fi
else
    log "AVISO: no existe /mnt/extsd/busybox_net -> sin shell por IP"
fi

log "=== FIN $(date) ==="
exit 0
