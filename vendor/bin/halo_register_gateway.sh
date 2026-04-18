#!/vendor/bin/sh

HALO_PATH=/vendor/bin

[ -f ${HALO_PATH}/maintainer ] && . ${HALO_PATH}/maintainer
[ -f ${HALO_PATH}/halo-lib.sh ] && . ${HALO_PATH}/halo-lib.sh

session_header_name="X-Amz-Halo-Provisioning-Session-Id"
session_header="${session_header_name}: "
provisioning_url=""
error_tag=$HALO_STATUS_ERROR
LOG_TAG=""
key_refresh_response=""
halo_mode=""
protocol_on=1
protocol_off=0

#PROV revisit
#Hack since cloud is not ready
RINGFFS_DEVW_URL="https://Ringffsproxy-beta.amazon.com"
RINGFFS_STGW_URL="https://Ringffsproxy-gamma.amazon.com"
RINGFFS_PRDW_URL="https://Ringffsproxy.amazon.com"
PUBLIC_V1="public/v1"

FFS_WORLD_FILE="/data/vendor/halo/etc/maintainer/world"

KEYREFRESH_AUTH_RETRY_MAX=3
KEYREFRESH_DELAY=30

on_error()
{
    1>&2 halo_log_error $LOG_TAG "$1"
    if [ "$halo_mode" = "keyrefresh" ]; then
        # send_asset_status is used only for provisioning. Since key refresh is called
        # after the device is provisioned, send HALO_STATUS_ONLINE.
        send_asset_status ${HALO_STATUS_ONLINE}
        # Set key refresh to false on failure
        setprop vendor.halo.key.refresh false
        halo_cli set_protocol_on $protocol_on
    else
        setprop persist.vendor.halo.host done
        send_asset_status ${error_tag}
    fi
    if ! [ -z ${2} ]; then
        while IFS= read -r line || [ -n "$line" ]
        do
            halo_log_error "halo-cloud-resp" "$line"
        done < "$2"
    fi
    exit 1
}

on_halo_reg_error()
{
    1>&2 halo_log_error $LOG_TAG "$1"
    local product_name=`getprop ro.product.name`

    if [ "$halo_mode" = "keyrefresh" ]; then
        # Set key refresh to false on failure
        if [ "$product_name" = "cypress" ]; then
            send_asset_status ${HALO_STATUS_ONLINE}
        fi
        setprop vendor.halo.key.refresh false
        halo_cli set_protocol_on $protocol_on
    else
        setprop persist.vendor.halo.host done
        if [ "$product_name" = "cypress" ]; then
            send_asset_status ${error_tag}
        fi
    fi

    exit 1
}

get_provisioning_url() {
    local url="https://${WORLD}/api/v2/hub/maint/halo-provisioning-url"

    ${curl2}  \
    --request GET \
    --header "${ZASSET_AUTH_HEADER}" \
    "$url" || on_error "Failed to get provisioning url"
}

compose_url() {
    local endpoint=$1
    echo "${provisioning_url}/twirp/halo.provisioning.v1.${endpoint}"
}

send_ringnet() {
    local cmd=$1
    halo_cli -x "${cmd}" 2>/dev/null | tr -d " "
}

compose_echo_url() {
    local endpoint=$1
#PROV revisit
#Hack since cloud is not ready
#   echo "${provisioning_url}/twirp/halo.provisioning.v1.${endpoint}"
    if [[ ${WORLD} == *"devw"* ]]; then
        echo "${RINGFFS_DEVW_URL}/${PUBLIC_V1}/${endpoint}"
        halo_log_info $LOG_TAG "DEVW environment"
    elif [[ ${WORLD} == *"stgw"* ]]; then
        echo "${RINGFFS_STGW_URL}/${PUBLIC_V1}/${endpoint}"
        halo_log_info $LOG_TAG "STGW environment"
    else #prdw
        echo "${RINGFFS_PRDW_URL}/${PUBLIC_V1}/${endpoint}"
        halo_log_info $LOG_TAG "PRDW environment"
    fi
#End hack
}

register_gateway() {
#PROV revisit
#Hack since cloud is not ready
#   local url=$(compose_url "RegistrationManager/RegisterGateway")
#   local payload=$(jq -nc --arg ringnetDeviceId $(fwenv ringnetid) '{$ringnetDeviceId}')
    local url=$(compose_echo_url "Halo/RegisterGateway")
    local payload=$(jq -nc --arg endpointId $(fwenv ringnetid) '{$endpointId}')
#End hack
    halo_log_info $LOG_TAG "Starting gateway registration..."
    halo_log_debug $LOG_TAG "with url: ${url}"
    halo_log_extended $LOG_TAG "with payload: ${payload}"

    ${curl2} --dump-header ${WORKDIR}/header \
        --request POST \
        --header "Content-Type: application/json" \
        --header "${ZASSET_AUTH_HEADER}" \
        --header "X-Amz-Halo-Gateway-Id: $(fwenv ringnetid)" \
        --data "${payload}" \
        "$url" > ${WORKDIR}/response || on_error "Gateway registration failed" "${WORKDIR}/response"

    local response=$(cat ${WORKDIR}/response)
    halo_log_extended $LOG_TAG "response: ${response}"

    halo_log_info $LOG_TAG "Gateway registered"

    session_header=$(grep "${session_header_name}" < ${WORKDIR}/header)
    halo_log_debug $LOG_TAG "Got session header: ${session_header}"
}

# Parses input as json, reads RingNet commands, executes each command.
# For each command outputs a line in format: "cmd=response"
run_commands() {
    local resp=""

    for cmd in $(jq --raw-output '.ringnetCommands[]'); do
        resp=$(send_ringnet "${cmd}")
        echo "${cmd}=${resp}"
    done
}

process_response_with_commands() {
    run_commands | jq \
        --null-input \
        --raw-input \
        --compact-output \
        --arg ringnetDeviceId $(fwenv ringnetid) \
        'reduce (inputs) as $i
         ({}; ($i | split("=")) as [$cmd, $resp]
             | .ringnetCommandResponses[$cmd]=$resp)
         | . + {$ringnetDeviceId}'
}

sce_request() {
    local phase="$1"
    local url=$(compose_url "CloudSecureChannelManager/$phase")

    ${curl2} \
        --request POST \
        --header "Content-Type: application/json" \
        --header "${ZASSET_AUTH_HEADER}" \
        --header "${session_header}" \
        --data @${WORKDIR}/secure/request \
        "${url}" > ${WORKDIR}/secure/response
}

process_sce_response() {
    process_response_with_commands < ${WORKDIR}/secure/response > ${WORKDIR}/secure/request
}

sce_phase() {
    local phase="$1"
    local payload=$(cat ${WORKDIR}/secure/request)

    halo_log_info $LOG_TAG "SCE phase: ${phase}"
    halo_log_extended $LOG_TAG "payload: ${payload}"

    sce_request "$phase" || on_error "${phase} request failed" "${WORKDIR}/secure/response"

    local response=$(cat ${WORKDIR}/secure/response)
    halo_log_extended $LOG_TAG "response: ${response}"

    # Skip empty response
    [ "${response}" = "{}" ] && return

    process_sce_response || on_error "Failed to process $phase commands"
}

establish_secure_channel() {
    local secure_dir="${WORKDIR}/secure"

    halo_log_info $LOG_TAG "Starting secure channel establishment..."

    mkdir -p "${secure_dir}"

    jq -nc  --arg ringnetDeviceId $(fwenv ringnetid) '{$ringnetDeviceId}' > ${secure_dir}/request \
        && sce_phase "StartSecureChannelEstablishment" \
        && sce_phase "GetRemoteSignedPublicKey" \
        && sce_phase "SetDeviceSignedPublicKey" \
        && sce_phase "PerformHandshake" \
        || on_error "Secure channel establishment failed"

    halo_log_info $LOG_TAG "Secure channel established"
}

set_location_settings() {
    local url=$(compose_url "NetworkConfigurationManager/BeginRingnetDeviceRegistration")

    halo_log_info $LOG_TAG "Setting location settings..."
    halo_log_info $LOG_TAG "BeginRingNetDeviceRegistration..."

    jq -nc --arg id $(fwenv ringnetid) '.ringnetDeviceId=$id' \
        | ${curl2} \
        --request POST \
        --header "Content-Type: application/json" \
        --header "${ZASSET_AUTH_HEADER}" \
        --header "${session_header}" \
        --data @- \
        "${url}" > ${WORKDIR}/location_settings \
        || on_error "Failed to request location settings (BeginRingNetDeviceRegistration)" "${WORKDIR}/location_settings"

    process_response_with_commands < ${WORKDIR}/location_settings > ${WORKDIR}/config_status \
        || on_error "Failed to process location settings response"

    halo_log_info $LOG_TAG "SetDeviceConfigurationStatus..."
    local url=$(compose_url "NetworkConfigurationManager/SetDeviceConfigurationStatus")
    ${curl2} \
        --request POST \
        --header "Content-Type: application/json" \
        --header "${ZASSET_AUTH_HEADER}" \
        --header "${session_header}" \
        --data @${WORKDIR}/config_status \
        "${url}" > ${WORKDIR}/response || on_error "Failed to report config status" "${WORKDIR}/response"

    local response=$(cat ${WORKDIR}/response)
    halo_log_extended $LOG_TAG "response: ${response}"
    [ "${response}" != "{}" ] && on_error "Failed to report config status" "${WORKDIR}/response"

    halo_log_info $LOG_TAG "Finished setting location settings"
}

on_key_refresh_acquire_error() {
    while IFS= read -r line
    do
        if [[ "$line" = *"412 Precondition Failed"* ]]; then
            halo_log_error $LOG_TAG "Registration states not in sync. Skip key refresh and restart registration."
            setprop vendor.halo.key.refresh false
            setprop persist.vendor.halo.prov.status retry
            setprop vendor.halo.prov.retry true
            setprop persist.vendor.halo.host done
            exit 1
        else
            on_error "keyrefresh request failed" "${key_refresh_dir}/response"
        fi
    done < "$3"
}

acquire_key_refresh_settings() {

    halo_log_info $LOG_TAG "acquire key refresh settings..."
    local key_refresh_dir="${WORKDIR}/keyrefresh"
    mkdir -p "${key_refresh_dir}"
    tmp=$(mktemp -p ${WORKDIR} "curl.XXXXXX")

    jq -nc  --arg ringnetDeviceId $(fwenv ringnetid) '{$ringnetDeviceId}' > ${key_refresh_dir}/request
    local payload=$(cat ${key_refresh_dir}/request)
    halo_log_extended $LOG_TAG "payload: ${payload}"

    local url=$(compose_url "CloudSecureChannelManager/KeyRefresh")
    ${curl2} \
        --request POST \
        --header "Content-Type: application/json" \
        --header "${ZASSET_AUTH_HEADER}" \
        --header "${session_header}" \
        --dump-header ${tmp} \
        --data @${key_refresh_dir}/request \
        "${url}" > ${key_refresh_dir}/response || on_key_refresh_acquire_error "keyrefresh request failed" "${key_refresh_dir}/response" "$tmp"

    key_refresh_response=$(cat ${key_refresh_dir}/response)
    halo_log_extended $LOG_TAG "response: ${key_refresh_response}"
}

legacy_provision() {
    LOG_TAG="halo-provision"
    halo_mode="provision"
    halo_log_info $LOG_TAG "Requesting provisioning url..."
    provisioning_url=$(get_provisioning_url)
    halo_log_debug $LOG_TAG "Got provisioning url: ${provisioning_url}"

    send_asset_status ${HALO_STATUS_PROVISIONING}

    register_gateway

    establish_secure_channel

    set_location_settings
}

legacy_keyrefresh() {
    halo_log_info $LOG_TAG "Requesting provisioning url..."
    provisioning_url=$(get_provisioning_url)
    halo_log_debug $LOG_TAG "Got provisioning url: ${provisioning_url}"

    acquire_key_refresh_settings

    local key_refresh_value=`echo ${key_refresh_response} | jq -r '.keyRefreshAllowed'`
    halo_log_debug $LOG_TAG " $key_refresh_value"
    if [ "$key_refresh_value" = "true" ]; then
        halo_log_info $LOG_TAG "Initiating key refresh"
        establish_secure_channel
    else
        halo_log_info $LOG_TAG "Key refresh not needed"
    fi
}

hybrid_halo_reg_provision() {
    LOG_TAG="halo-provision"
    halo_mode="provision"
    halo_log_info $LOG_TAG "Start hybrid_halo_reg_provision..."

    send_asset_status ${HALO_STATUS_PROVISIONING}

    local auth_token=`halo_hidl_client get_auth_token`
    if [ "$auth_token" = "" ]; then
        on_halo_reg_error "hybrid_halo_reg_provision abort, empty auth token"
        return
    fi

    if [[ ${WORLD} == *"devw"* ]]; then
        halo_log_info $LOG_TAG "DEVW environment"
        halo_reg --reg.world="devw" --reg.prov_url="${RINGFFS_DEVW_URL}" --reg.registrator="echo" --reg.gateway_id=$(fwenv ringnetid) --reg.mode="provision" --reg.auth_token="$auth_token" || on_halo_reg_error "hybrid_halo_reg_provision on devw error"
    elif [[ ${WORLD} == *"stgw"* ]]; then
        halo_log_info $LOG_TAG "STGW environment"
        halo_reg --reg.world="stgw" --reg.prov_url="${RINGFFS_STGW_URL}" --reg.registrator="echo" --reg.gateway_id=$(fwenv ringnetid) --reg.mode="provision" --reg.auth_token="$auth_token" || on_halo_reg_error "hybrid_halo_reg_provision on stgw error"
    else # prdw
        halo_log_info $LOG_TAG "PRDW environment"
        halo_reg --reg.world="prdw" --reg.prov_url="${RINGFFS_PRDW_URL}" --reg.registrator="echo" --reg.gateway_id=$(fwenv ringnetid) --reg.mode="provision" --reg.auth_token="$auth_token" || on_halo_reg_error "hybrid_halo_reg_provision on prod error"
    fi
}

hybrid_halo_reg_keyrefresh() {
    LOG_TAG="halo-provision"
    halo_mode="keyrefresh"
    halo_log_info $LOG_TAG "Start hybrid_halo_reg_keyrefresh..."

    local auth_token=""
    for i in $(seq 1 ${KEYREFRESH_AUTH_RETRY_MAX}); do
        auth_token=`halo_hidl_client get_auth_token`
        if [ "$auth_token" != "" ]; then
            break
        fi
        sleep $KEYREFRESH_DELAY
    done

    if [ "$auth_token" = "" ]; then
        on_halo_reg_error "hybrid_halo_reg_keyrefresh abort, empty auth token"
        return
    fi

    if [[ ${WORLD} == *"devw"* ]]; then
        halo_log_info $LOG_TAG "DEVW environment"
        halo_reg --reg.world="devw" --reg.prov_url="${RINGFFS_DEVW_URL}" --reg.registrator="echo" --reg.gateway_id=$(fwenv ringnetid) --reg.mode="keyrefresh" --reg.auth_token="$auth_token" || on_halo_reg_error "hybrid_halo_reg_keyrefresh on devw error"
    elif [[ ${WORLD} == *"stgw"* ]]; then
        halo_log_info $LOG_TAG "STGW environment"
        halo_reg --reg.world="stgw" --reg.prov_url="${RINGFFS_STGW_URL}" --reg.registrator="echo" --reg.gateway_id=$(fwenv ringnetid) --reg.mode="keyrefresh" --reg.auth_token="$auth_token" || on_halo_reg_error "hybrid_halo_reg_keyrefresh on stgw error"
    else # prdw
        halo_log_info $LOG_TAG "PRDW environment"
        halo_reg --reg.world="prdw" --reg.prov_url="${RINGFFS_PRDW_URL}" --reg.registrator="echo" --reg.gateway_id=$(fwenv ringnetid) --reg.mode="keyrefresh" --reg.auth_token="$auth_token" || on_halo_reg_error "hybrid_halo_reg_keyrefresh on prod error"
    fi
}


halo_reg_provision() {
    LOG_TAG="halo-provision"
    halo_mode="provision"
    halo_log_info $LOG_TAG "Start halo_reg_provision..."

    local auth_token=`halo_hidl_client get_auth_token`
    if [ "$auth_token" = "" ]; then
        on_halo_reg_error "halo_reg_provision abort, empty auth token"
        return
    fi

    local ffs_world=`cat $FFS_WORLD_FILE`

    if [[ "$ffs_world" == *"devw"* ]]; then
        halo_log_info $LOG_TAG "DEVW environment"
        halo_reg --reg.world="devw" --reg.prov_url="${RINGFFS_DEVW_URL}" --reg.registrator="ffs_proxy" --reg.gateway_id=$(fwenv 5bmsn) --reg.mode="provision" --reg.auth_token="$auth_token" || on_halo_reg_error "halo_reg_provision on devw error"
    elif [[ "$ffs_world" == *"stgw"* ]]; then
        halo_log_info $LOG_TAG "STGW environment"
        halo_reg --reg.world="stgw" --reg.prov_url="${RINGFFS_STGW_URL}" --reg.registrator="ffs_proxy" --reg.gateway_id=$(fwenv 5bmsn) --reg.mode="provision" --reg.auth_token="$auth_token" || on_halo_reg_error "halo_reg_provision on stgw error"
    else
        halo_log_info $LOG_TAG "PRDW environment"
        halo_reg --reg.world="prdw" --reg.prov_url="${RINGFFS_PRDW_URL}" --reg.registrator="ffs_proxy" --reg.gateway_id=$(fwenv 5bmsn) --reg.mode="provision" --reg.auth_token="$auth_token" || on_halo_reg_error "halo_reg_provision on prod error"
    fi
}

main() {
    if [ "$1" = "provision" ]; then

        local prov_without_msp=`getprop vendor.halo.gw.prov.withoutmsp`
        if [ "$prov_without_msp" = "true" ]; then
            halo_reg_provision
        else
            local product_name=`getprop ro.product.name`
            if [ "$product_name" = "cypress" ]; then
                hybrid_halo_reg_provision
            else
                legacy_provision
            fi
        fi

    elif [ "$1" = "keyrefresh" ]; then

        LOG_TAG="halo-keyrefresh"
        halo_mode="keyrefresh"
        local status=`getprop persist.vendor.halo.prov.status`
        if [ "$status" = "provisioned" ]; then

            local prov_without_msp=`getprop vendor.halo.gw.prov.withoutmsp`
            if [ "$prov_without_msp" = "false" ]; then
                local product_name=`getprop ro.product.name`
                if [ "$product_name" = "cypress" ]; then
                    hybrid_halo_reg_keyrefresh
                else
                    legacy_keyrefresh
                fi
            fi

        else
            halo_log_info $LOG_TAG "device not provisioned"
        fi

    else
        LOG_TAG="halo-provision"
        halo_log_error $LOG_TAG "Wrong parameter"
    fi
}

main $@
