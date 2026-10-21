#!/bin/bash
# FOX_LOCAL_CALLBACK_SCRIPT dispatcher.
# Runs every other *.sh in this folder, in alphabetical order.

RAMDISK_PATH="$1"
CALL_TYPE="$2"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SELF="$(basename "$0")"

log() { echo "[scripts.sh] $*"; }

if [ "$CALL_TYPE" != "--first-call" ]; then
    log "CALL_TYPE=$CALL_TYPE — nothing to do, skipping"
    exit 0
fi

if [ ! -d "$RAMDISK_PATH" ]; then
    log "ERROR: ramdisk path $RAMDISK_PATH not found"
    exit 1
fi

for w in "$SCRIPT_DIR"/*.sh; do
    [ -f "$w" ] || continue
    [ "$(basename "$w")" = "$SELF" ] && continue

    log "--- running $(basename "$w") ---"
    bash "$w" "$RAMDISK_PATH" || { log "ERROR: $(basename "$w") failed"; exit 1; }
done

log "=== all workers done ==="
