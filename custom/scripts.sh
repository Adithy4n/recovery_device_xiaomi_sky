#!/bin/bash
# FOX_LOCAL_CALLBACK_SCRIPT dispatcher.
# Runs every other *.sh in this folder, alphabetically, each one independently:
# a failing or missing-input worker is logged and skipped, never stops the rest.
# Always exits 0 so a worker problem can't abort the build; check the summary.
#
# Usage (build):  scripts.sh RAMDISK_PATH --first-call
# Usage (manual): scripts.sh RAMDISK_PATH            (CALL_TYPE omitted = run)

RAMDISK_PATH="$1"
CALL_TYPE="$2"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SELF="$(basename "$0")"

log() { echo "[scripts.sh] $*"; }

if [ -n "$CALL_TYPE" ] && [ "$CALL_TYPE" != "--first-call" ]; then
    log "CALL_TYPE=$CALL_TYPE - nothing to do, skipping"
    exit 0
fi

if [ ! -d "$RAMDISK_PATH" ]; then
    log "ERROR: ramdisk path '$RAMDISK_PATH' not found"
    exit 0
fi

ok=(); failed=()

for w in "$SCRIPT_DIR"/*.sh; do
    [ -f "$w" ] || continue
    name="$(basename "$w")"
    [ "$name" = "$SELF" ] && continue

    log "--- running $name ---"
    # own bash process: its exit/set -e/set -u can't affect this loop or other workers
    if bash "$w" "$RAMDISK_PATH"; then
        ok+=("$name")
    else
        log "WARNING: $name failed (exit $?), continuing"
        failed+=("$name")
    fi
done

log "=== done. ok: ${ok[*]:-none} | failed: ${failed[*]:-none} ==="
exit 0
