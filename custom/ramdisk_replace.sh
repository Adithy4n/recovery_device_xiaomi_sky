#!/bin/bash
# Finds every file in custom/ (flat, top-level only) and replaces any
# file with the same name anywhere in the ramdisk.

RAMDISK_PATH="$1"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEVICE_ETC="$SCRIPT_DIR"

log() { echo "[ramdisk_replace] $*"; }

log "=== Ramdisk root : $RAMDISK_PATH"
log "=== Source etc   : $DEVICE_ETC"

if [ ! -d "$RAMDISK_PATH" ]; then
    log "ERROR: ramdisk path $RAMDISK_PATH not found"
    exit 1
fi

found_any=0

for src_file in "$DEVICE_ETC"/*; do
    [ -f "$src_file" ] || continue

    filename="$(basename "$src_file")"

    # Don't try to "replace" the dispatcher scripts themselves against
    # the ramdisk — they're tooling, not ramdisk content.
    case "$filename" in
        scripts.sh|ramdisk_replace.sh|make_bootstrap_link.sh)
            continue
            ;;
    esac

    matches=()
    while IFS= read -r -d '' match; do
        matches+=("$match")
    done < <(find "$RAMDISK_PATH" -type f -name "$filename" -print0)

    if [ "${#matches[@]}" -eq 0 ]; then
        log "SKIP (not found in ramdisk): $filename"
        continue
    fi

    for dst in "${matches[@]}"; do
        rel="${dst#"$RAMDISK_PATH"/}"
        log "Replacing: $rel  <--  etc/$filename"
        cp -f "$src_file" "$dst"
        found_any=1
    done
done

[ "$found_any" -eq 0 ] && log "WARNING: no files were replaced"
log "=== Done ==="
