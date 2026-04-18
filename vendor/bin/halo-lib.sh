#!/vendor/bin/sh

HALO_PATH=/vendor/bin
[ -f ${HALO_PATH}/halo_common_lib.sh ] && . ${HALO_PATH}/halo_common_lib.sh

HUB_CORE_CONNECTION_TIMEOUT=30 # seconds
SEND_STATUS="send-status-to-asset-services"
LOG_TAG="halo-status"

HALO_STATUS_ONLINE=0
HALO_STATUS_PROVISIONING=1
#2-4 reserved
HALO_STATUS_ERROR=5 # CommonError

send_asset_status() {
       halo_log_info $LOG_TAG "send_asset_status: [$1]"
       ${SEND_STATUS} ${1}
}

wait_hub_core_connected() {
    local count=0

    while [ $count -lt $HUB_CORE_CONNECTION_TIMEOUT ]; do
        local status=$(check-hub-core-status)
        halo_log_info $LOG_TAG "Checking Hub-Core status: ${status}"
        [ "$status" = "connected" ] && return 0
        count=$(($count + 1))
        sleep 1
    done

    halo_log_warning $LOG_TAG "Timeout waiting for Hub-Core connection"
    return 1
}

