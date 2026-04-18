#!/vendor/bin/sh
HALO_PATH=/vendor/bin
[ -f ${HALO_PATH}/halo_common_lib.sh ] && . ${HALO_PATH}/halo_common_lib.sh

LOG_TAG="halo-metrics"

init_for_non_unified_uploader() {
    if [ -s $MFG/authtoken ]; then
        setprop vendor.halo.authtoken $(cat $MFG/authtoken)
    fi

    if [ -s $MFG/serial ]; then
        setprop vendor.halo.serial $(cat $MFG/serial)
    fi

    [ -f /vendor/bin/maintainer ] && . /vendor/bin/maintainer
    setprop vendor.halo.env $(echo ${POD} | grep -oE "^[[:alnum:]]+")
    setprop vendor.halo.server $WORLD
}

init_for_unified_uploader() {
    setprop vendor.halo.authtoken "__dummy__"
    setprop vendor.halo.serial "__dummy__"
    setprop vendor.halo.env "__dummy__"
    setprop vendor.halo.server "__dummy__"
}

halo_log_info $LOG_TAG  "*** >>> Start to initialize halo-metrics  <<< ***"

prov_without_msp=`getprop vendor.halo.gw.prov.withoutmsp`

if [ "$prov_without_msp" = "false" ]; then
    init_for_non_unified_uploader
else
    init_for_unified_uploader
fi

halo_log_info $LOG_TAG  "*** >>> Finish initializing halo-metrics <<< ***"
