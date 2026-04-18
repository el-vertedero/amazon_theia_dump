#!/vendor/bin/sh

HALO_PATH=/vendor/bin
[ -f ${HALO_PATH}/halo_common_lib.sh ] && . ${HALO_PATH}/halo_common_lib.sh

CMD_CLASS_HALO_MGMT=0
CMD_ID_FACTORY_RESET=449
PLD_SOFT_FACTORY_RESET=0
PLD_HARD_FACTORY_RESET=1

soft_factory_reset() {
    halo_cli -c $CMD_CLASS_HALO_MGMT -i $CMD_ID_FACTORY_RESET $PLD_SOFT_FACTORY_RESET
}

hard_factory_reset() {
    halo_cli -c $CMD_CLASS_HALO_MGMT -i $CMD_ID_FACTORY_RESET $PLD_HARD_FACTORY_RESET
}
