#!/bin/bash
# Creates /system/bin/bootstrap/linker64 as a relative symlink to the
# real linker64, so binaries that request the bootstrap-linker as their
# PT_INTERP (hwservicemanager, servicemanager, e2fsck, fsck.f2fs) can
# still exec() in recovery, where APEX activation order doesn't matter.

RAMDISK_PATH="$1"

log() { echo "[make_bootstrap_link] $*"; }

BIN_DIR="$RAMDISK_PATH/system/bin"
BOOTSTRAP_DIR="$BIN_DIR/bootstrap"
REAL_LINKER="$BIN_DIR/linker64"
LINK_PATH="$BOOTSTRAP_DIR/linker64"

if [ ! -f "$REAL_LINKER" ]; then
    log "ERROR: $REAL_LINKER not found — nothing to link to, aborting"
    exit 1
fi

mkdir -p "$BOOTSTRAP_DIR"

if [ -L "$LINK_PATH" ] && [ "$(readlink "$LINK_PATH")" = "../linker64" ]; then
    log "already correct, skipping"
    exit 0
fi

ln -sf ../linker64 "$LINK_PATH"

if [ -L "$LINK_PATH" ]; then
    log "OK: $LINK_PATH -> $(readlink "$LINK_PATH")"
else
    log "ERROR: symlink creation failed"
    exit 1
fi
