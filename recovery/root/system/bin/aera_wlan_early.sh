#!/system/bin/sh
# Boot WPSS (Wi-Fi) before decryption so Wi-Fi works from the decrypt screen (sky / adrastea)
PATH=/system/bin:/sbin:/vendor/bin; export PATH
LOG=/tmp/aera_wlan_early.log
DRV=qca_cld3_adrastea
FWDIR=/firmware/image/adrastea

log() {
    echo "[aera-wlan-early] uptime=$(cut -d ' ' -f 1 /proc/uptime) $*" >> "$LOG"
    echo "[aera-wlan-early] $*" > /dev/kmsg 2>/dev/null || true
}
fail() { log "STOP: $*"; exit 1; }
prop() { getprop "$1" 2>/dev/null; }
ready() { [ "$(prop wifi.driver.ready)" = true ] || setprop wifi.driver.ready true; }
loaded() {
    # the driver may register as "wlan" after init
    if [ "$1" = "$DRV" ]; then
        grep -Eq "^($DRV|wlan) " /proc/modules 2>/dev/null
    else
        grep -q "^$1 " /proc/modules 2>/dev/null
    fi
}

# Called by the early trigger and by the post-decrypt retry; must be idempotent
if [ -e /sys/class/net/wlan0 ]; then log "wlan0 already present; no WPSS re-boot"; ready; exit 0; fi
[ "$(prop ro.twrp.fastbootd)" = 1 ] && { log "fastbootd: skipping WLAN"; exit 0; }
[ "$(prop twrp.modules.loaded)" = true ] || fail "modules not loaded yet"
log "early WLAN requested; post.decrypt.modules=$(prop post.decrypt.modules)"

# Retry modules the first pass may have missed (dependency order)
for mod in rfkill cfg80211 $DRV; do
    loaded "$mod" && continue
    found=""
    for p in /lib/modules /tmp/vendor/lib/modules /tmp/vendor_dlkm/lib/modules /vendor/lib/modules /vendor_dlkm/lib/modules; do
        if [ -f "$p/$mod.ko" ]; then found="$p/$mod.ko"; break; fi
    done
    if [ -z "$found" ]; then log "module missing on disk: $mod"; continue; fi
    if insmod "$found" 2>> "$LOG"; then log "loaded $mod"; else log "could not load $mod from $found"; fi
done

# Hard prerequisites: cfg80211 + the driver. Everything else is waited for (max 12s)
# but only warned about, so a missing optional piece never blocks Wi-Fi.
count=0
while [ "$count" -lt 120 ]; do
    hard=1; soft=1
    loaded cfg80211 || hard=0
    loaded "$DRV" || hard=0
    for mod in gsim rmnet_mem ipam; do loaded "$mod" || soft=0; done
    grep -q ' /firmware ' /proc/mounts 2>/dev/null || soft=0
    [ "$(prop init.svc.aera-pd-mapper)" = running ] || soft=0
    [ "$(prop init.svc.vendor.gatekeeper_default)" = running ] || soft=0
    [ -r "$FWDIR/bdwlan.bin" ] || soft=0
    [ "$hard" = 1 ] && [ "$soft" = 1 ] && break
    sleep 0.1
    count=$((count+1))
done
loaded cfg80211 || fail "cfg80211 not loaded"
loaded "$DRV" || fail "$DRV not loaded"
if [ "$count" -ge 120 ]; then
    for mod in gsim rmnet_mem ipam; do loaded "$mod" || log "WARN: $mod not loaded"; done
    grep -q ' /firmware ' /proc/mounts 2>/dev/null || log "WARN: /firmware not mounted"
    [ "$(prop init.svc.aera-pd-mapper)" = running ] || log "WARN: aera-pd-mapper not running"
    [ "$(prop init.svc.vendor.gatekeeper_default)" = running ] || log "WARN: gatekeeper not running"
    [ -r "$FWDIR/bdwlan.bin" ] || log "WARN: $FWDIR/bdwlan.bin not readable"
    log "continuing after 12s despite warnings"
else
    log "modules, firmware, pd-mapper and gatekeeper ready"
fi

[ -w /sys/kernel/icnss/wlan_en_delay ] || fail "missing WLAN delay node"
[ -w /sys/kernel/icnss/wpss_boot ] || fail "missing WPSS boot node"

# The driver requests wlan_mac.bin shortly after WPSS boots. Provide AERA's
# per-device identity before requesting WPSS, instead of relying on recovery's
# later Wi-Fi setup to generate the file; otherwise the driver falls back to a
# shared MAC, which changes the device identity and burns a DHCP lease each boot.
# This modifies only the recovery ramdisk
if [ ! -e /tmp/aera_wlan_wpss_requested ]; then
    [ -x /system/bin/aera-sky-wlan-mac ] || fail "missing recovery MAC helper"
    /system/bin/aera-sky-wlan-mac >> "$LOG" 2>&1 || \
        fail "failed to generate the deterministic MAC before WPSS"
    log "prepared per-device WLAN MAC file before WPSS boot"
fi

# Marker survives the post-decrypt retry but not a recovery reboot
if [ ! -e /tmp/aera_wlan_wpss_requested ]; then
    : > /tmp/aera_wlan_wpss_requested || fail "cannot save WPSS boot marker"
    log "requesting WPSS boot"
    printf '1000\n' > /sys/kernel/icnss/wlan_en_delay || fail "cannot set WLAN delay"
    printf '1\n' > /sys/kernel/icnss/wpss_boot || fail "cannot start WPSS"
else
    log "WPSS already requested; waiting without repeating boot"
fi

count=0
while [ "$count" -lt 45 ] && [ ! -e /sys/class/net/wlan0 ]; do sleep 1; count=$((count+1)); done
[ -e /sys/class/net/wlan0 ] || fail "wlan0 absent after 45s"
log "wlan0 up after ${count}s; publishing wifi.driver.ready"
ready
