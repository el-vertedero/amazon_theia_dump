#!/vendor/bin/sh

HALO_CLI=/vendor/bin/halo_cli
MAX_RETRY=20
retry_count=0
PROTOCOL_ON=1

HALO_PATH=/vendor/bin
[ -f ${HALO_PATH}/halo_common_lib.sh ] && . ${HALO_PATH}/halo_common_lib.sh

LOG_TAG="halo-protocol-status"

while [ $retry_count -le $MAX_RETRY ]
do
    local prov_status=`getprop persist.vendor.halo.prov.status`
    if [ "$prov_status" = "provisioned" ]; then
        local prot_status=`$HALO_CLI get_protocol_on 2>/dev/null`
        halo_log_debug $LOG_TAG "prot_status=$prot_status"
        if [ "$prot_status" = "on" ]; then
            halo_log_info $LOG_TAG "Protocol turned on. Exiting"
            exit 0
        else
            halo_log_info $LOG_TAG "Turning on the protocol. Check again in 5 secs"
            $HALO_CLI set_protocol_on $PROTOCOL_ON
            sleep 5
        fi
    else
        halo_log_info $LOG_TAG "Device not provisioned. Should not get here. Exiting"
        exit 0
    fi
done
