#!/system/bin/sh
# Boot WPSS (Wi-Fi) before decryption so Wi-Fi works from the decrypt screen
PATH=/system/bin:/sbin:/vendor/bin; export PATH
LOG=/tmp/aera_wlan_early.log
log() { echo "[aera-wlan-early] $*" >> "$LOG"; echo "[aera-wlan-early] $*" > /dev/kmsg 2>/dev/null; }
fail() { log "STOP: $*"; exit 1; }
prop() { getprop "$1" 2>/dev/null; }
ready() { [ "$(prop wifi.driver.ready)" = true ] || setprop wifi.driver.ready true; }
loaded() { grep -q "^$1 " /proc/modules 2>/dev/null; }

if [ -e /sys/class/net/wlan0 ]; then log "wlan0 present"; ready; exit 0; fi
[ "$(prop twrp.modules.loaded)" = true ] || fail "modules not loaded yet"
[ "$(prop ro.twrp.fastbootd)" = 1 ] && { log "fastbootd: skip"; exit 0; }

# Retry modules the first pass may have missed (dependency order)
for mod in rfkill cfg80211 qca_cld3_adrastea; do
    loaded "$mod" && continue
    for p in /lib/modules /tmp/vendor/lib/modules /tmp/vendor_dlkm/lib/modules /vendor/lib/modules /vendor_dlkm/lib/modules; do
        [ -f "$p/$mod.ko" ] && { insmod "$p/$mod.ko" 2>>"$LOG" && log "loaded $mod"; break; }
    done
done
i=0
while [ $i -lt 120 ]; do
    loaded cfg80211 && loaded qca_cld3_adrastea && break
    sleep 0.1; i=$((i+1))
done
loaded qca_cld3_adrastea || fail "qca_cld3_adrastea not loaded"
[ -w /sys/kernel/icnss/wpss_boot ] || fail "missing WPSS boot node"

if [ ! -e /tmp/aera_wlan_wpss_requested ]; then
    : > /tmp/aera_wlan_wpss_requested
    log "requesting WPSS boot"
    printf '1000\n' > /sys/kernel/icnss/wlan_en_delay
    printf '1\n' > /sys/kernel/icnss/wpss_boot
else
    log "WPSS already requested; waiting"
fi
i=0
while [ $i -lt 45 ] && [ ! -e /sys/class/net/wlan0 ]; do sleep 1; i=$((i+1)); done
[ -e /sys/class/net/wlan0 ] || fail "wlan0 absent after 45s"
log "wlan0 up after ${i}s"
ready
