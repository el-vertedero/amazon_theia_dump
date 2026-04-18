#!/vendor/bin/sh

HALO_PATH=/vendor/bin
[ -f ${HALO_PATH}/halo_common_lib.sh ] && . ${HALO_PATH}/halo_common_lib.sh
[ -f ${HALO_PATH}/halo_factory_reset.sh ] && . ${HALO_PATH}/halo_factory_reset.sh

LOG_TAG="halo-provision"

main() {

    halo_log_info $LOG_TAG "Soft factory reset nordic"
    soft_factory_reset
}

main $@
