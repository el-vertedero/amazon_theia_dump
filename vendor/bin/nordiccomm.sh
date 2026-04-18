#!/vendor/bin/sh
#Script to test communication with the nordic
set -u

HALO_PATH=/vendor/bin
[ -f ${HALO_PATH}/halo_common_lib.sh ] && . ${HALO_PATH}/halo_common_lib.sh

LOG_TAG="halo-nordiccomm"
HALO_CLI=/vendor/bin/halo_cli
PLD=10
FW_VERSION_ADDR=FFFFF400
retry_count=1
TOTAL_RETRIES=10


setprop vendor.halo.comm connecting
sleep 5
halo_log_info $LOG_TAG "Test if nordic is ready"
while [ $retry_count -le $TOTAL_RETRIES ]
do
	app_version=`$HALO_CLI get_fw_version 2>/dev/null`
	if [ "$?" = "0" ]; then
		halo_log_info $LOG_TAG "Nordic is ready"
		setprop vendor.halo.comm ready
		break;
	else
		version_string=`$HALO_CLI -T 0 $FW_VERSION_ADDR $PLD 2>/dev/null`
		if [[ "$version_string" = *pld* ]]; then
			halo_log_info $LOG_TAG "Nordic is ready"
			setprop vendor.halo.comm ready
			break;
		else
			halo_log_error $LOG_TAG "Nordic is not ready. Retry..."
			sleep 5
		fi
	fi
	retry_count=$((retry_count+1))
done

if [ ${retry_count} == $(($TOTAL_RETRIES+1)) ]; then
	halo_log_info $LOG_TAG "Nordic connection failed"
	setprop vendor.halo.comm failed
fi
