#!/vendor/bin/sh

[ -f /vendor/bin/maintainer ] && . /vendor/bin/maintainer

ENV=$(echo ${POD} | grep -oE "^[[:alnum:]]+")
[ "${ENV}" != "" ] || ENV="bad"

LOGDIR=/data/vendor/halo/var/log
LOGSERVER=$WORLD
QUERYPATH="api/v2/hub/maint/upload-beams-logs-url"
URL="https://${LOGSERVER}/${QUERYPATH}"
SLEEP_TIME=2

# Get upload url
curl_get_upload_url(){
    ${curl} -v -H "X-HubEnv: ${ENV}" -H "Accept: application/maintainer" "${URL}$1" --ciphers ${CIPHER_LIST}
}

curl_up() {
    local upload_url=$(curl_get_upload_url "?filename=$(basename $1)")
    if [ $? -ne 0 ] || [ -z "${upload_url}" ]; then
        return 1
    fi
    curl -v -X PUT --data-binary "@$1" "$upload_url"
}

send_logs() {
    log -t halo-sendlogs "Going to archive logs:"
    cd $LOGDIR
    archive="$(date -u '+%Y-%m-%d-%H-%M-%S').tar.gz"
    tar -zvchf $archive *
    curl_up $archive

    if [ $? -ne 0 ]; then
        log -t halo-sendlogs "${date} Failed to send logs => $(ls -lh $archive)"
    else
        log -t halo-sendlogs "${date} sent log entry: => $(ls -lh $archive)"
    fi
    rm $archive
    return 0
}

send_logs
