#!/vendor/bin/sh

HALO_PATH=/vendor/bin
[ -f ${HALO_PATH}/halo_common_lib.sh ] && . ${HALO_PATH}/halo_common_lib.sh

# This file is used as a marker, if it exists, then device has been provisioned & first OTA succeed.
FILE_PROVISIONING="provisioning"

# Error codes
GSN_WDD_WPS_CONNECT_FAILURE=0x90000d05
GSN_WDD_SSID_NOT_FOUND=0x90000d06
GSN_WDD_AUTH_FAIL_INVALID_PSK=0x90000d07
GSN_WDD_AUTH_FAIL_TIMEOUT=0x90000d08
GSN_WDD_PROV_CHECKIN_FAIL=0x90000e00
GSN_WDD_PROV_ASSET_FAIL=0x90000e01
ERROR_NTP_TIMEOUT=0x90000e02
ERROR_HUBCORE_TIMEOUT=0x90000e03
GSN_WDD_PROV_GET_LOCATION_FAIL=0x90000e04
ERROR_WLAN_TIMEOUT=0x90000e05
ERROR_MFG_DATA_EMPTY=0x90000e06
ERROR_KEY_REFRESH_FAIL=0x90000e10
GSN_WDD_SUCCESS=0x0
GSN_WDD_MASK=0xFF

LOG_TAG="halo-provision"

PROV_LAST_ERR=${HALO_LOG_DIR}/prov_last_err

_run_single_instance_internal () {
    if [ ! -f "${1}" ]
    then
        echo "Executable ${1} not found"
        exit 1
    fi

    if [ -n "$(pgrep -f ${1})" ]
    then
        echo "Another ${1} instance is running, won't start another one"
        exit 0
    fi

    echo "Starting ${1}"
    $@
    RET=$?
    echo "Exited from ${1}"

    return $RET
}

run_single_instance() {
    if [ "$#" -lt 2 ]
    then
        echo "Incorrect arguments provided to run_single_instance" | logger -p 1.6
        exit 2
    fi

    COMMAND=$1
    shift
    SYSLOG_TAG=$1
    shift

    _run_single_instance_internal ${COMMAND} $@ 2>&1 | logger -t "<${SYSLOG_TAG}>" -p 1.6
}

# Make sure /mnt/nvram/ has been mounted
wait_nvram_to_mount()
{
    COUNTER=0
    while [ $COUNTER -lt 20 ]; do
       MNT=$(cat /proc/mounts | grep '/mnt/nvram')
       if [ -n "$MNT" ]; then
          echo "mount found: $MNT"
          return 0
       fi
       sleep 1
       echo "wait /mnt/nvram to mount ($COUNTER)"
       let COUNTER=COUNTER+1
    done

    echo "nvram mount failed"
    return 1
}

# Make sure overlay has been mounted
# $1 is mount point
wait_overlay_mounted()
{
    COUNTER=0
    while [ $COUNTER -lt 60 ]; do
       MNT=$(cat /proc/mounts | grep "$1")
       if [ -n "$MNT" ]; then
          echo "mount found: $MNT"
          return 0
       fi
       sleep 1
       echo "wait overlay "$1" to be mounted ($COUNTER)"
       let COUNTER=COUNTER+1
    done

    echo "fail to wait overlay "$1" mounted"
    return 1
}

wait_wlan_connected() {
    local max=$1
    local attempt=1

    while [ $attempt -le $max ]; do
        echo "Checking if WLAN is connected, attempt ${attempt} of ${max}"
        curl --ciphers ${CIPHER_LIST} --silent --connect-timeout 1 "https://${DEF_WORLD}" > /dev/null && return 0
        let attempt++
        sleep 1
    done

    halo_log_warning $LOG_TAG "Timeout waiting for wlan connected"
    return 1
}

start_hub_services()
{
    halo_log_info $LOG_TAG "Starting hub services"
    setprop vendor.halo.core-services start
}

stop_hub_services()
{
    halo_log_info $LOG_TAG "Stopping hub services"
    setprop vendor.halo.core-services stop
}
