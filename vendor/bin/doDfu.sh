#!/vendor/bin/sh

HALO_PATH=/vendor/bin
[ -f ${HALO_PATH}/halo_common_lib.sh ] && . ${HALO_PATH}/halo_common_lib.sh

LOG_TAG="halo-dfu"

# helper function
help() {
	halo_log_info $LOG_TAG "./doDfu.sh <folder_location> <image_to_flash>"
	halo_log_info $LOG_TAG "image_to_flash : bl  -> bootloader only"
	halo_log_info $LOG_TAG "               : app -> app only"
	halo_log_info $LOG_TAG "               : all -> both bootloader and app"
}
halo_log_info $LOG_TAG "Starting halo dfu"

# basic parameter check
if [ $# -ne 2 ]; then
	help
	exit
fi

HALO_UPD_DIR=$1
HALO_UPD_IMG=$2
HALO_DEV_PATH=/dev/halo0
HALO_APP_BIN=theia_halo_app.bin
HALO_APP_DAT=theia_halo_app.dat
HALO_BL_BIN=theia_sd_bl.bin
HALO_BL_DAT=theia_sd_bl.dat
DFU_MAX_RETRY=2
DFU_MAX_SLEEP=5
DFU_MTU_SIZE=128

do_exit() {
	exit $1
}

# Update nordic bootloader through DFU
bootloader_dfu() {
	setprop vendor.halo.dfu ongoing
	retry_count=0
	while [ $retry_count -le $DFU_MAX_RETRY ]
	do
		halo_log_info $LOG_TAG "Starting BL and SD DFU"
		halodfu -m $DFU_MTU_SIZE -d $HALO_DEV_PATH -b $HALO_UPD_DIR/$HALO_BL_IMG

		if [ "$?" = "0" ]; then
			halo_log_info $LOG_TAG "SD_BL DFU successful"
			break;
		else
			halo_log_error $LOG_TAG "SD_BL DFU failed retrying..."
		fi

		if [ $retry_count = $DFU_MAX_RETRY ]; then
			setprop vendor.halo.dfu failed
		fi
		retry_count=$(($retry_count+1))
		halo_log_error $LOG_TAG "SD_BL DFU failed. Retry count:$retry_count"
		sleep $DFU_MAX_SLEEP
	done
}

# Update nordic app through DFU
app_dfu() {
	setprop vendor.halo.dfu ongoing
	retry_count=0
	while [ $retry_count -le $DFU_MAX_RETRY ]
	do
		halo_log_info $LOG_TAG "Starting APP DFU"
		halodfu -m $DFU_MTU_SIZE -d $HALO_DEV_PATH -a $HALO_UPD_DIR/$HALO_APP_IMG

		if [ "$?" = "0" ]; then
			halo_log_info $LOG_TAG "APP DFU successful"
			setprop vendor.halo.dfu completed
			break;
		else
			halo_log_error $LOG_TAG "APP DFU failed retrying..."
		fi

		if [ $retry_count = $DFU_MAX_RETRY ]; then
			setprop vendor.halo.dfu failed
		fi
		retry_count=$(($retry_count+1))
		halo_log_error $LOG_TAG "APP DFU failed. Retry count:$retry_count"
		sleep $DFU_MAX_SLEEP
	done
}

if [ "$HALO_UPD_IMG" = "bl" ]; then
	# update only the bl
	if [ ! -f "$HALO_UPD_DIR/$HALO_BL_BIN" ] || [ ! -f "$HALO_UPD_DIR/$HALO_BL_DAT" ]; then
		halo_log_error $LOG_TAG "Missing Nordic bl, skipping update"
		exit 1
	fi
	setprop vendor.halo.comm disconnected
	HALO_BL_IMG=`basename $HALO_BL_DAT| cut -d. -f1`
	bootloader_dfu
	do_exit 0
elif [ "$HALO_UPD_IMG" = "app" ]; then
	# update only the app.
	if [  ! -f "$HALO_UPD_DIR/$HALO_APP_BIN" ] || [  ! -f "$HALO_UPD_DIR/$HALO_APP_DAT" ]; then
		halo_log_error $LOG_TAG "Missing Nordic app, skipping update"
		setprop vendor.halo.dfu failed
		exit 1
	fi
	setprop vendor.halo.comm disconnected
	HALO_APP_IMG=`basename $HALO_APP_DAT| cut -d. -f1`
	app_dfu
	do_exit 0
elif [ "$HALO_UPD_IMG" = "all" ]; then
	# update both app and bl
	if [  ! -f "$HALO_UPD_DIR/$HALO_APP_BIN" ] || [  ! -f "$HALO_UPD_DIR/$HALO_APP_DAT" ]; then
		halo_log_error $LOG_TAG "Missing Nordic app, skipping update"
		setprop vendor.halo.dfu failed
		# if the app is missing skip both app and bl update
		exit 1
	else
		setprop vendor.halo.comm disconnected
		if [  ! -f "$HALO_UPD_DIR/$HALO_BL_BIN" ] || [  ! -f "$HALO_UPD_DIR/$HALO_BL_DAT" ]; then
			# if the bl is missing continue to app update
			halo_log_error $LOG_TAG "Missing Nordic bl, skipping bl update"
		else
			HALO_BL_IMG=`basename $HALO_BL_DAT| cut -d. -f1`
			bootloader_dfu
			sleep $DFU_MAX_SLEEP
		fi
		HALO_APP_IMG=`basename $HALO_APP_DAT| cut -d. -f1`
		app_dfu
	fi
	do_exit 0
else
	halo_log_error $LOG_TAG "Wrong option"
	help
	exit 2
fi
