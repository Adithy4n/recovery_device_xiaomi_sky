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
OF_SCREEN_H := 2460
OF_STATUS_H := 100
OF_STATUS_INDENT_LEFT := 50
OF_STATUS_INDENT_RIGHT := 48
OF_ALLOW_DISABLE_NAVBAR := 0
OF_CLOCK_POS := 1
OF_HIDE_NOTCH := 1

# other stuff
OF_USE_GREEN_LED := 0
OF_QUICK_BACKUP_LIST := /boot;
OF_ENABLE_LPTOOLS := 1
OF_NO_TREBLE_COMPATIBILITY_CHECK := 1

# flashlight
OF_FL_PATH1=/tmp/flashlight

# ensure that sdcard is unmount before reboot
OF_UNMOUNT_SDCARDS_BEFORE_REBOOT=1

# ensure that /sdcard is bind-unmounted before f2fs data repair or format
OF_UNBIND_SDCARD_F2FS := 1

# number of list options before scrollbar creation
OF_OPTIONS_LIST_NUM := 15

# A/B with recovery partition
OF_AB_DEVICE_WITH_RECOVERY_PARTITION := 1

# build all the partition tools
OF_ENABLE_ALL_PARTITION_TOOLS := 1

# automatically wipe /metadata after formatting /data
OF_WIPE_METADATA_AFTER_DATAFORMAT := 1

# use lz4 compression 
OF_USE_LZ4_COMPRESSION := 1

# ofox maintainer
OF_MAINTAINER=ADITHYAN

# Timezone
OF_DEFAULT_TIMEZONE=IST-5:30 

# add dmctl
OF_USE_DMCTL := 1

#
