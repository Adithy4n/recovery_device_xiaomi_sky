#
#	This file is part of the OrangeFox Recovery Project
# 	Copyright (C) 2024-2026 The OrangeFox Recovery Project
#
#	OrangeFox is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 3 of the License, or
#	any later version.
#
#	OrangeFox is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
# 	This software is released under GPL version 3 or any later version.
#	See <http://www.gnu.org/licenses/>.
#
# 	Please maintain this if you use this script or any part of it
#

# screen settings
AERA_SCREEN_H := 2460
AERA_STATUS_H := 100
AERA_STATUS_INDENT_LEFT := 50
AERA_STATUS_INDENT_RIGHT := 48
AERA_ALLOW_DISABLE_NAVBAR := 0
AERA_CLOCK_POS := 1
AERA_HIDE_NOTCH := 1
AERA_UI_ADAPTIVE_RESOLUTION := true

# other stuff
AERA_USE_GREEN_LED := 0
AERA_QUICK_BACKUP_LIST := /boot;
AERA_ENABLE_LPTOOLS := 1
AERA_NO_TREBLE_COMPATIBILITY_CHECK := 1

# flashlight
AERA_FL_PATH1 := /tmp/flashlight

# ensure that sdcard is unmount before reboot
AERA_UNMOUNT_SDCARDS_BEFORE_REBOOT := 1

# ensure that /sdcard is bind-unmounted before f2fs data repair or format
AERA_UNBIND_SDCARD_F2FS := 1

# number of list options before scrollbar creation
AERA_OPTIONS_LIST_NUM := 15

# A/B with recovery partition
AERA_AB_DEVICE_WITH_RECOVERY_PARTITION := 1

# build all the partition tools
AERA_ENABLE_ALL_PARTITION_TOOLS := 1

# automatically wipe /metadata after formatting /data
AERA_WIPE_METADATA_AFTER_DATAFORMAT := 1

# use lz4 compression
AERA_USE_LZ4_COMPRESSION := 1

# ofox maintainer
AERA_MAINTAINER := ADITHYAN

# Timezone
AERA_DEFAULT_TIMEZONE := IST-5:30

# add dmctl
AERA_USE_DMCTL := 1

# use AIDL boot hal instead of HIDL
AERA_USE_AIDL_BOOT_CONTROL := 1

# avoid MTP issues after data format
AERA_BIND_MOUNT_SDCARD_ON_FORMAT := 1

# force casefolding props to true
AERA_FORCE_CASEFOLDING := 1

# block operations after flashing a ROM
AERA_BLOCK_OPERATIONS_AFTER_ROM_FLASH := 1
