#!/vendor/bin/sh
set -u

HALO_PATH=/vendor/bin
[ -f ${HALO_PATH}/halo_common_lib.sh ] && . ${HALO_PATH}/halo_common_lib.sh

LOG_TAG="halo-dfu"

app_version=0
app_variant=-1
array_variant=(debug validation release diagnostics unknown)
HALO_CLI=/vendor/bin/halo_cli
VERSION=/vendor/firmware/halo/halo_version
PLD=10
FW_VERSION_ADDR=FFFFF400
FW_VARIANT_ADDR=FFFFF401
CMD_CLASS=0
CMD_ID=48C
GREP=/vendor/bin/grep
MAX_RETRY=1
MAX_SLEEP=1

halo_log_info $LOG_TAG "Starting compare dfu"

# Initializing vendor.halo.dfu to "required" to
# fix the compare_dfu failures due to older FW.

setprop vendor.halo.dfu required

# Get the app version. The device could be in normal mode or
# test mode. The script first tries to get the fw_version from the
# normal mode. If the version is not obtained, it tries to get the
# fw_version from the test mode. The app_version is set to the
# correct version. This flow is retried twice and app_version set
# to 0 if the version is not obtained.
get_app_version() {
	retry_count=0
	while [ $retry_count -le $MAX_RETRY ]
	do
		halo_log_info $LOG_TAG "Get app version for normal mode"
		app_version=`$HALO_CLI get_fw_version 2>/dev/null`
		if [ "$?" = "0" ]; then
			break;
		else
			halo_log_info $LOG_TAG "Get app version for test mode"
			version_string=`$HALO_CLI -T 0 $FW_VERSION_ADDR $PLD 2>/dev/null`
			if [[ "$version_string" = *pld* ]]; then
				major_version=`echo $version_string | cut -d: -f2-3 | cut -d\( -f1 | cut -d' ' -f2`
				minor_version=`echo $version_string | cut -d: -f2-3 | cut -d\( -f1 | cut -d' ' -f3`
				patch_version=`echo $version_string | cut -d: -f2-3 | cut -d\( -f1 | cut -d' ' -f4`
				build_version=`echo $version_string | cut -d: -f2-3 | cut -d\( -f1 | cut -d' ' -f5`
				app_version=$((16#$major_version)).$((16#$minor_version)).$((16#$patch_version))-$((16#$build_version))
				break;
			else
				halo_log_error $LOG_TAG "Cannot get halo app version"
				sleep $MAX_SLEEP
				app_version=0
			fi
		fi
		retry_count=$((retry_count+1))
		halo_log_info $LOG_TAG "Retrying..."
	done
}

# Get the app variant. The device could be in normal mode or
# test mode. The script first tries to get the variant from the
# normal mode. If the variant is not obtained, it tries to get the
# variant from the test mode. The app_variant is set to the correct
# variant. This flow is retried twice and app_variant set to -1 if
# the variant is not obtained.
get_app_variant() {
	retry_count=0
	while [ $retry_count -le $MAX_RETRY ]
	do
		halo_log_info $LOG_TAG "Get app variant for normal mode"
		variant_string=`$HALO_CLI -c $CMD_CLASS -i $CMD_ID 2>/dev/null`
		if [ "$?" = "0" ]; then
			app_variant=${variant_string: -1}
			break;
		else
			halo_log_info $LOG_TAG "Get app variant for test mode"
			variant_string=`$HALO_CLI -T 0 $FW_VARIANT_ADDR $PLD 2>/dev/null`
			if [[ "$variant_string" = *pld* ]]; then
				cut_string=`echo $variant_string | cut -d: -f 2-3`
				app_variant=${cut_string:2:2}
				break;
			else
				halo_log_error $LOG_TAG "Cannot get halo app variant"
				sleep $MAX_SLEEP
				app_variant=4
			fi
		fi
		retry_count=$((retry_count+1))
		halo_log_info $LOG_TAG "Retrying..."
	done
}

get_app_version
get_app_variant
halo_log_info $LOG_TAG "Current_version:$app_version:${array_variant[$app_variant]}"

# Look for app version or app variant mismatch
ota_version=`$GREP -ni version $VERSION | cut -d= -f2`
ota_variant=`$GREP -ni variant $VERSION | cut -d= -f2`
if [ "$app_version" != "$ota_version" ] || [ "$ota_variant" != "${array_variant[$app_variant]}" ]; then
	halo_log_info $LOG_TAG "OTA to version:$ota_version:$ota_variant"
	setprop vendor.halo.dfu required
else
	halo_log_info $LOG_TAG "Halo update not required"
	setprop vendor.halo.dfu not-required
fi

halo_log_info $LOG_TAG "Completed compare dfu"
