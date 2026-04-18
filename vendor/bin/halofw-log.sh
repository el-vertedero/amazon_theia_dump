#!/vendor/bin/sh

HALOLOG=/vendor/bin/halo-log
HALONODE=/dev/halo0
HALOLOG_PATH=/data/vendor/halo/var/log/
HALOLOG_FILE=halo_fw.log

echo "Starting halo-log service"

$HALOLOG -r -a "${HALOLOG_PATH}/${HALOLOG_FILE}"
