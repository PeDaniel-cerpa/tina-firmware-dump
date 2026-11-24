#!/bin/sh
# ==============================================================================
# debug1 - modo SD-only para la M750
#
# Se ejecuta como root desde /mnt/extsd al arrancar con la SD puesta.
# Graba, sin UART:
#   1) /dev/mtdblock2 (rootfs)  <- mtdblock2_custom.bin  (final: layout2 + fix zlink, sin TPMS)
#   2) /dev/mtdblock5 (bootlogo) <- bootlogo.bin         (Proyecto nuevo)
#
# Hace backup de lo anterior en la SD, verifica MD5 antes y despues de dd,
# limpia whiteouts del overlay y deja telnetd por si hace falta debug.
#
# Al terminar: APAGA, SACA LA SD Y ENCIENDE SIN SD.
# ==============================================================================

LOG=/mnt/extsd/debug1.log
IMG=/mnt/extsd/mtdblock2_custom.bin
LOGO=/mnt/extsd/bootlogo.bin
BAK=/mnt/extsd/mtdblock2_original_backup.bin
LOGO_BAK=/mnt/extsd/bootlogo_original_backup.bin
FLAG=/mnt/extsd/rootfs_final.done
LOGO_FLAG=/mnt/extsd/bootlogo.done
TMP=/tmp/mtdblock2_custom.bin
TMP_LOGO=/tmp/bootlogo.bin
BB=/mnt/extsd/busybox_net
UP=/overlay/upper/data/res/pic
UPL=/overlay/upper/data/res/layout
UPP=/overlay/upper/data/res/param

EXPECTED_ROOT=2a3fb11dfe526948908e2a5e9148f855
EXPECTED_LOGO=d105460a6164c8d5e861f337b429f873

log() { echo "[debug1] $*" >> "$LOG" 2>/dev/null; }

: > "$LOG"
log "=== INICIO $(date) ==="

# ------------------------------------------------------------------ rootfs ---
if [ ! -f "$IMG" ]; then
    log "ERROR: no existe $IMG -> no se graba rootfs"
else
    if [ -f "$FLAG" ]; then
        log "rootfs_final.done existe -> rootfs ya grabado, omito"
    else
        if [ ! -f "$BAK" ]; then
            log "guardando rootfs original en $BAK"
            dd if=/dev/mtdblock2 of="$BAK" bs=4096 >> "$LOG" 2>&1
            sync
        else
            log "backup del rootfs ya existe"
        fi

        log "copiando rootfs a /tmp"
        cat "$IMG" > "$TMP" 2>>"$LOG"

        A=$(md5sum "$IMG" 2>/dev/null | awk '{print $1}')
        C=$(md5sum "$TMP" 2>/dev/null | awk '{print $1}')
        log "rootfs MD5 SD      : $A"
        log "rootfs MD5 /tmp    : $C"
        log "rootfs MD5 esperado: $EXPECTED_ROOT"

        if [ -z "$A" ] || [ "$A" != "$C" ] || [ "$A" != "$EXPECTED_ROOT" ]; then
            log "ERROR: rootfs no verificado. No se graba nada."
        else
            # Quitar restos del overlay SOLO en upper (nunca tocar /data).
            if [ -d /overlay/upper ]; then
                log "limpiando restos del overlay (upper)"
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
                        rm -f "$UP/$p" 2>>"$LOG"
                        log "  borrado upper: $p"
                    fi
                done
                for p in home_main.xml zlink.xml tyre_warn.xml; do
                    if [ -e "$UPL/$p" ] || [ -c "$UPL/$p" ] || [ -L "$UPL/$p" ]; then
                        rm -f "$UPL/$p" 2>>"$LOG"
                        log "  borrado upper: layout/$p"
                    fi
                done
                if [ -d "$UPP" ]; then
                    if [ -e "$UPP/config_devmng.xml" ] || [ -c "$UPP/config_devmng.xml" ] || [ -L "$UPP/config_devmng.xml" ]; then
                        rm -f "$UPP/config_devmng.xml" 2>>"$LOG"
                        log "  borrado upper: param/config_devmng.xml"
                    fi
                fi
            fi
            rm -f /tmp/image.bin 2>/dev/null

            log "grabando /dev/mtdblock2 (13303808 bytes)"
            dd if="$TMP" of=/dev/mtdblock2 bs=4096 >> "$LOG" 2>&1
            sync

            B=$(md5sum /dev/mtdblock2 2>/dev/null | awk '{print $1}')
            log "rootfs MD5 leido  : $B"
            if [ -n "$B" ] && [ "$B" = "$EXPECTED_ROOT" ]; then
                log "ROOTFS FINAL (zlink sin hueco) GRABADO Y VERIFICADO"
                echo ok > "$FLAG" 2>/dev/null
                log "creado $FLAG"
            else
                log "ERROR: verificacion del rootfs fallida. No se creo $FLAG."
            fi
        fi
    fi
fi

# ---------------------------------------------------------------- bootlogo ---
if [ ! -f "$LOGO" ]; then
    log "ERROR: no existe $LOGO -> no se graba bootlogo"
else
    if [ -f "$LOGO_FLAG" ]; then
        log "bootlogo.done existe -> bootlogo ya grabado, omito"
    else
        if [ ! -f "$LOGO_BAK" ]; then
            log "guardando bootlogo original en $LOGO_BAK"
            dd if=/dev/mtdblock5 of="$LOGO_BAK" bs=4096 >> "$LOG" 2>&1
            sync
        else
            log "backup del bootlogo ya existe"
        fi

        log "copiando bootlogo a /tmp"
        cat "$LOGO" > "$TMP_LOGO" 2>>"$LOG"

        L=$(md5sum "$LOGO" 2>/dev/null | awk '{print $1}')
        M=$(md5sum "$TMP_LOGO" 2>/dev/null | awk '{print $1}')
        log "bootlogo MD5 SD      : $L"
        log "bootlogo MD5 /tmp    : $M"
        log "bootlogo MD5 esperado: $EXPECTED_LOGO"

        if [ -z "$L" ] || [ "$L" != "$M" ] || [ "$L" != "$EXPECTED_LOGO" ]; then
            log "ERROR: bootlogo no verificado. No se graba nada."
        else
            log "grabando /dev/mtdblock5 (131072 bytes)"
            dd if="$TMP_LOGO" of=/dev/mtdblock5 bs=4096 >> "$LOG" 2>&1
            sync

            N=$(md5sum /dev/mtdblock5 2>/dev/null | awk '{print $1}')
            log "bootlogo MD5 leido  : $N"
            if [ -n "$N" ] && [ "$N" = "$EXPECTED_LOGO" ]; then
                log "BOOTLOGO GRABADO Y VERIFICADO"
                echo ok > "$LOGO_FLAG" 2>/dev/null
                log "creado $LOGO_FLAG"
            else
                log "ERROR: verificacion del bootlogo fallida. No se creo $LOGO_FLAG."
            fi
        fi
    fi
fi

# ------------------------------------------------------------------ telnet ---
if [ -x "$BB" ]; then
    "$BB" telnetd -p 23 -l /bin/sh >> "$LOG" 2>&1 &
    sleep 1
    if pidof busybox_net >/dev/null 2>&1 || ps | grep -q '[t]elnetd'; then
        log "telnetd ACTIVO en puerto 23 (debug)"
    else
        log "telnetd no quedo activo"
    fi
fi

log "=== FIN $(date) ==="
log "Si todo salio bien: APAGA, SACA LA SD Y ENCIENDE SIN SD"
exit 0
