#!/vendor/bin/sh

HALO_PATH=/vendor/bin
[ -f ${HALO_PATH}/halo_common_lib.sh ] && . ${HALO_PATH}/halo_common_lib.sh

LOG_TAG="halo-provision-retry"

# Retry delays in seconds
delay_array=(30 60 300 900 1800 3600 28800 57600 86400)
delay_array_len=$((${#delay_array[@]} - 1))

state=`getprop vendor.halo.prov.retry`
if [ "$state" = "true" ]; then
    delay_idx=`getprop vendor.halo.prov.retry.idx`
    if [ -z "$delay_idx" ]; then
        halo_log_info $LOG_TAG "Starting provisioning retries"
        delay_idx=$FIRST_RETRY_IDX
    elif [ $delay_idx -gt $delay_array_len ]; then
        delay_idx=$delay_array_len
    fi

    delay=${delay_array[$delay_idx]}
    halo_log_info $LOG_TAG "Next provision retry after $delay secs"
    sleep $delay
    setprop vendor.halo.prov.retry false
    delay_idx=$((delay_idx+1))
else
    halo_log_info $LOG_TAG "Next provision retry after $REBOOT_DELAY secs"
    sleep $REBOOT_DELAY
    delay_idx=$FIRST_RETRY_IDX
fi

setprop vendor.halo.prov.retry.idx $delay_idx
halo_log_info $LOG_TAG "Retrying provisioning"
local status=`getprop persist.vendor.halo.prov.status`
if [ "$status" = "provisioned" ]; then
    halo_log_info $LOG_TAG "Device provisioned. Exiting"
    exit 0
else
    setprop persist.vendor.halo.prov.status trigger_provision
fi
