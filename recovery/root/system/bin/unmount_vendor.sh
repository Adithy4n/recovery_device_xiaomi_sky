#!/system/bin/sh

TEE_SVC="qteeconnector-hal-1-0"
KM_SVC="keymaster-4-0"
KS_SVC="keystore2"
DECRYPT_CMD=""
INTERVAL=1
ROUNDS=30

LOG=/tmp/unmount_vendor.log

log() {
    echo "[$(date +%T)] $*" >> "$LOG"
}

is_mounted() {
    grep -q " $1 " /proc/mounts
}

svc_up() {
    [ "$(getprop init.svc.$1)" = "running" ]
}

svc_stop() {
    setprop ctl.stop "$1" 2>/dev/null
}

svc_start() {
    setprop ctl.start "$1" 2>/dev/null
}

unmount_vendor() {
    for m in /vendor_dlkm /vendor; do
        n=0
        while is_mounted "$m" && [ "$n" -lt 5 ]; do
            umount -l "$m" 2>>"$LOG"
            log "unmounted $m (round $round)"
            n=$((n + 1))
        done
    done
}

log "== start =="
round=0

for s in "$KS_SVC" "$KM_SVC" "$TEE_SVC"; do
    svc_stop "$s"
done
unmount_vendor

# start services once
for s in "$TEE_SVC" "$KM_SVC" "$KS_SVC"; do
    if ! svc_up "$s"; then
        svc_start "$s"
        sleep 2
    fi
    if svc_up "$s"; then
        log "$s running"
    else
        log "$s down"
    fi
done

if [ -n "$DECRYPT_CMD" ]; then
    sh -c "$DECRYPT_CMD" >> "$LOG" 2>&1
fi

# keep unmounting for the rest of the window
round=1
while [ "$round" -le "$ROUNDS" ]; do
    unmount_vendor
    round=$((round + 1))
    sleep "$INTERVAL"
done

log "== done =="
exit 0
