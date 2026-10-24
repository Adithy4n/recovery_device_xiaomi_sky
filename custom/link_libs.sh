#!/usr/bin/env bash
# Usage: bash link_libs.sh RAMDISK_DIR [lib ...]   (default: libprocinfo.so)
# Creates RAMDISK/system/lib64/<lib> -> /vendor/lib64/<lib>.

set -u
R="${1:?usage: bash link_libs.sh RAMDISK_DIR [lib ...]}"; shift
R="${R%/}"; LIBS=("$@"); [ ${#LIBS[@]} -eq 0 ] && LIBS=(libprocinfo.so)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/../recovery/root/vendor/lib64"
[ -d "$SRC" ] || [ -d "$R/vendor/lib64" ] || { echo "no vendor/lib64 in tree ($SRC) or ramdisk ($R)"; exit 1; }

t="$R/.lnk_test_$$"
ln -s /nonexistent "$t" 2>/dev/null || { echo "!! no symlink support here. cp -a \"$R\" ~/ramdisk and run on that"; exit 1; }
rm -f "$t"

mkdir -p "$R/system/lib64"
for l in "${LIBS[@]}"; do
  if [ ! -f "$SRC/$l" ] && [ ! -f "$R/vendor/lib64/$l" ]; then echo "skip   $l (not in tree or ramdisk vendor/lib64)"; continue; fi
  if [ -e "$R/system/lib64/$l" ] && [ ! -L "$R/system/lib64/$l" ]; then echo "skip   $l (real file already in system/lib64)"; continue; fi
  ln -sfn "/vendor/lib64/$l" "$R/system/lib64/$l" && echo "linked /system/lib64/$l -> /vendor/lib64/$l"
done
