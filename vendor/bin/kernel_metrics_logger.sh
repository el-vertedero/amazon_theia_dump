#!/system/bin/sh

DELAY=3600 #send stuff every hour

source log_counter_metrics.sh

function log_backlight_status()
{
    BL_FLAGS_NODE_PATH="/sys/devices/platform/11007000.i2c/i2c-0/0-0011/leds/lm36274-leds:white:backlight_cluster/lm36274_flags"

    kmlogger_strings_node_counter_metrics "$BL_FLAGS_NODE_PATH" "backlight_fault"
}

function log_logcat()
{
    log_backlight_status
}

# Run the collection repeatedly, pushing all output through to the metrics log.
while true ; do
    log_logcat
    sleep $DELAY
done
