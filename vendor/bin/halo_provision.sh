#!/vendor/bin/sh

REG_PARAM=$1
HALO_PATH=/vendor/bin
[ -f ${HALO_PATH}/halo_common_lib.sh ] && . ${HALO_PATH}/halo_common_lib.sh
[ -f ${HALO_PATH}/halo_ring.sh ] && . ${HALO_PATH}/halo_ring.sh
[ -f ${HALO_PATH}/halo-lib.sh ] && . ${HALO_PATH}/halo-lib.sh

LOG_TAG_PROV=""
halo_provision_mode=""
protocol_on=1
protocol_off=0

exit_provision()
{
    let exit_val=$(( $1 & $GSN_WDD_MASK ))
    exit $exit_val
}

send_asset_status_wrap() {
    local result=`getprop vendor.halo.gw.prov.withoutmsp`
    if [ "$result" = "false" ]; then
        send_asset_status ${1}
    fi
}

check-inet-status()
{
    # The pairing app calls this with an interface arg, but it's not used
    if [ "${1}" = eth -o "${1}" = wifi ]; then
        shift
    fi

    # Default to 10 retries, but go as high as $1 specifies
    [ -z "${1}" ] && MAX=10 || MAX=${1}

    CURL_EXTRA_OPTIONS="--connect-timeout 10 --max-time 30"

    local result=`getprop vendor.halo.gw.prov.withoutmsp`
    if [ "$result" = "true" ]; then
        halo_log_info $LOG_TAG_PROV "Device bypass world/pod check now. Exiting"
        return
    fi

    for i in $(seq 1 ${MAX}); do
        if update_world && update_pod; then
            halo_log_debug $LOG_TAG_PROV "Found hub at $WORLD on pod $POD"
            return
        fi
        sleep 2
    done

    halo_log_error $LOG_TAG_PROV "Failed to ping world or pod"
    echo "$GSN_WDD_AUTH_FAIL_TIMEOUT" > ${PROV_LAST_ERR}
    if [ "$halo_provision_mode" = "keyrefresh" ]; then
        # send_asset_status is used only for provisioning. Since key refresh is called
        # after the device is provisioned, send HALO_STATUS_ONLINE.
        send_asset_status ${HALO_STATUS_ONLINE}
        # Set key refresh to false on failure
        setprop vendor.halo.key.refresh false
        halo_cli set_protocol_on $protocol_on
    else
        setprop persist.vendor.halo.prov.status retry
        setprop vendor.halo.prov.retry true
        setprop persist.vendor.halo.host done
        send_asset_status ${HALO_STATUS_ERROR}
    fi
    exit_provision $GSN_WDD_AUTH_FAIL_TIMEOUT
}

halo_cli_get() {
    halo_cli "$1" > "$2" 2>> $HLOG
    if [ $? -ne 0 ]; then
        halo_log_error  $LOG_TAG_PROV "Failed to request from Nordic: $1"
    rm $2
    fi
}

# Fail safe mechanism
check-mfg-exists()
{
    local prov_without_msp=`getprop vendor.halo.gw.prov.withoutmsp`
    local prov_status=`getprop persist.vendor.halo.prov.status`

    if [ "$prov_without_msp" = "false" ] &&  [ ! -s $MFG/ringnetid ]; then
        halo_log_info $LOG_TAG_PROV "Creating $MFG/ringnetid";
        halo_cli_get get_uuid $MFG/ringnetid;
    fi

    if [ "$prov_without_msp" = "true" ] && [ "$prov_status" != "provisioned" ] && [ ! -s $MFG/5bmsn ]; then
        halo_log_info $LOG_TAG_PROV "Creating $MFG/5bmsn";
        halo_cli_get get_uuid $MFG/5bmsn;
    fi

    if [ "$prov_without_msp" = "true" ] && [ "$prov_status" == "provisioned" ] && [! -s $MFG/ringnetid ]; then
        halo_log_info $LOG_TAG_PROV "Creating $MFG/ringnetid";
        halo_cli_get get_uuid $MFG/ringnetid;
    fi

    if [ ! -s $MFG/serial_no ]; then
        halo_log_info $LOG_TAG_PROV "Creating $MFG/serial_no";
        halo_cli_get get_serial_no $MFG/serial_no;
    fi

    if [ "$prov_without_msp" = "false" ] && [! -s $MFG/authtoken ]; then
        halo_log_info $LOG_TAG_PROV "Creating $MFG/authtoken";
        halo_cli_get get_auth_token $MFG/authtoken;
    fi
    if [ ! -s $MFG/serial ]; then
        halo_log_info $LOG_TAG_PROV "Creating $MFG/serial";
        echo $((0x$(cat $MFG/ringnetid) & 0x1FFFFFFFFF)) > $MFG/serial;
    fi
}

if [ "$REG_PARAM" = "provision" ]; then

    LOG_TAG_PROV="halo-provision"
    halo_provision_mode="provision"
    # Prevent provision of an already provisioned device.
    local status=`getprop persist.vendor.halo.prov.status`
    if [ "$status" = "provisioned" ]; then
        halo_log_info $LOG_TAG_PROV "Device already provisioned. Exiting"
        exit_provision $GSN_WDD_SUCCESS
    fi

    halo_log_info $LOG_TAG_PROV "Stop hub services"
    stop_hub_services

    # Key refresh is not needed since provisioning updates the key.
    setprop vendor.halo.key.refresh false
    halo_cli set_protocol_on $protocol_off

    halo_log_info $LOG_TAG_PROV "Start gateway provision"

    check-mfg-exists
    [ -f ${HALO_PATH}/maintainer ] && . ${HALO_PATH}/maintainer

    halo_log_info $LOG_TAG_PROV "Check inet status"
    check-inet-status

    # Add sync for assure that WORLD and POD files are available on FS for subsequent usage
    sync

    halo_log_info $LOG_TAG_PROV "Check inet status successful"

    $HALO_PATH/halo_register_gateway.sh provision || {
        halo_log_error $LOG_TAG_PROV "Register gateway failed"
        echo "$GSN_WDD_PROV_ASSET_FAIL" > ${PROV_LAST_ERR}
        setprop persist.vendor.halo.prov.status retry
        setprop vendor.halo.prov.retry true
        setprop persist.vendor.halo.host done
        exit_provision $GSN_WDD_PROV_ASSET_FAIL
    }

    halo_log_info $LOG_TAG_PROV "Provision gateway successful"
    setprop persist.vendor.halo.prov.status provisioned
    setprop persist.vendor.halo.host done

    # For new gateway registratino flow, populate ringnetid after registration is done
    local prov_without_msp=`getprop vendor.halo.gw.prov.withoutmsp`
    if [ "$prov_without_msp" = "true" ]; then
        halo_log_info $LOG_TAG_PROV "Creating $MFG/ringnetid";
        halo_cli_get get_uuid $MFG/ringnetid;
        ringnetid=`cat $MFG/ringnetid`
        setprop vendor.halo.ringnetid $ringnetid
    fi

    halo_cli set_protocol_on $protocol_on

    start_hub_services
    # Notify the cloud that we're provisioned & ready
    send_asset_status_wrap ${HALO_STATUS_ONLINE}

    # Reset the retry delay index if it exists
    idx=`getprop vendor.halo.prov.retry.idx`
    if [ $idx ]; then
        setprop vendor.halo.prov.retry.idx $FIRST_RETRY_IDX
    fi

elif [ "$REG_PARAM" = "unprovision" ]; then

    LOG_TAG_PROV="halo-provision"
    halo_provision_mode="unprovision"
    halo_log_info $LOG_TAG_PROV "Start gateway unprovision"

    halo_log_info $LOG_TAG_PROV "Stop hub services"
    stop_hub_services

    $HALO_PATH/halo_deregister_gateway.sh || {
        halo_log_error $LOG_TAG_PROV "Deregister gateway failed"
        echo "$GSN_WDD_PROV_ASSET_FAIL" > ${PROV_LAST_ERR}
        send_asset_status_wrap ${HALO_STATUS_ERROR}
        setprop persist.vendor.halo.host done
        exit_provision $GSN_WDD_PROV_ASSET_FAIL
    }

    halo_log_info $LOG_TAG_PROV "Unprovision gateway successful"

    halo_log_info $LOG_TAG_PROV "Start hub services"
    setprop persist.vendor.halo.prov.status unprovisioned
    setprop persist.vendor.halo.host done
    start_hub_services

elif [ "$REG_PARAM" = "keyrefresh" ]; then

    LOG_TAG_PROV="halo-keyrefresh"
    halo_provision_mode="keyrefresh"
    local status=`getprop persist.vendor.halo.prov.status`
    if [ "$status" = "provisioned" ]; then
        halo_log_info $LOG_TAG_PROV "Start key refresh"
        halo_cli set_protocol_on $protocol_off
        [ -f ${HALO_PATH}/maintainer ] && . ${HALO_PATH}/maintainer

        halo_log_info $LOG_TAG_PROV "Check inet status"
        check-inet-status
        # Add sync for assure that WORLD and POD files are available on FS for subsequent usage
        sync
        halo_log_info $LOG_TAG_PROV "Check inet status successful"

        $HALO_PATH/halo_register_gateway.sh keyrefresh || {
            # Set key refresh to false on failure
            setprop vendor.halo.key.refresh false
            halo_cli set_protocol_on $protocol_on
            exit_provision $ERROR_KEY_REFRESH_FAIL
        }
        send_asset_status_wrap ${HALO_STATUS_ONLINE}
        halo_cli set_protocol_on $protocol_on
    else
        halo_log_info $LOG_TAG_PROV "Key refresh not needed"
    fi
    setprop vendor.halo.key.refresh false
elif [ "$REG_PARAM" = "factoryreset" ]; then

    LOG_TAG_PROV="halo-factoryreset"
    halo_provision_mode="factoryreset"
    halo_log_info $LOG_TAG_PROV "Check if factory reset is required"
    local provstatus=`getprop persist.vendor.halo.prov.status`
    local frstatus=`getprop persist.vendor.halo.fr.status`

    if [ -z "$frstatus" ]; then
        if [ "$provstatus" != "provisioned" ]; then
            halo_log_info $LOG_TAG_PROV "Factory reset nordic"
            $HALO_PATH/halo_deregister_gateway.sh
        fi
        setprop persist.vendor.halo.fr.status not-required
    fi
else
    LOG_TAG_PROV="halo-provision"
    halo_log_error $LOG_TAG_PROV "Wrong parameter"
fi

exit_provision $GSN_WDD_SUCCESS
