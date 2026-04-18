#!/system/bin/sh

updateVersion=`cat /vendor/firmware/motor_version.txt`
#debug version format: 1.0.x.y. The last two fields are letters.
#relase version format: 1.0.134.0. The last two fields are digits.
currentVersion=`theia_get_version | grep -E -o '([0-9]{1,3}\.){2}[0-9a-zA-Z]{1,3}\.[0-9a-zA-Z]{1,3}'`
versionMode=`theia_get_version -m`

skipUpdate=`getprop persist.skip_mcu_firmware_update`

hallNormTableFile="/vendor/nvcfg/motor/hall_norm_table.bin"
DebugFile="/data/vendor/motor/motor_logging.txt"

function start_mcu_logger()
{
    setprop persist.uart1.ownership not_in_use
    setprop persist.uart1.request   not_in_use
    /vendor/bin/mcu_logger &
    #sleep 1 second to ensure mcu_logger is started
    sleep 1
}

function request_uart1()
{
    setprop persist.uart1.request flashing
    sleep 1
    a=1
    max_retry_cnt=3
    while [ $a -le $max_retry_cnt ]
    do
        var=`getprop persist.uart1.ownership`
        if [ $var == "not_in_use" ]
        then
            break
        fi
        a=`expr $a + 1`
        sleep 1
    done
    setprop persist.uart1.ownership flashing
    setprop persist.uart1.request not_in_use
}

function release_uart1()
{
    setprop persist.uart1.ownership not_in_use
}

function flash_regular_img()
{
    request_uart1

    echo 1 > /sys/devices/platform/11010000.spi/spi_master/spi32765/spi32765.0/mcu_boot
    echo 0 > /sys/devices/platform/11010000.spi/spi_master/spi32765/spi32765.0/mcu_rst
    sleep 1
    echo 1 > /sys/devices/platform/11010000.spi/spi_master/spi32765/spi32765.0/mcu_rst
    sleep 1

    mcu_id=`stm32flash -b 115200 /dev/ttyS1 | grep STM32 | cut -c29-32`
    stm32flash -b 115200 -w /vendor/firmware/${mcu_id}_motor.bin /dev/ttyS1

    release_uart1
}

function flash_factory_img()
{
    request_uart1

    echo 1 > /sys/devices/platform/11010000.spi/spi_master/spi32765/spi32765.0/mcu_boot
    echo 0 > /sys/devices/platform/11010000.spi/spi_master/spi32765/spi32765.0/mcu_rst
    sleep 1
    echo 1 > /sys/devices/platform/11010000.spi/spi_master/spi32765/spi32765.0/mcu_rst
    sleep 1

    mcu_id=`stm32flash -b 115200 /dev/ttyS1 | grep STM32 | cut -c29-32`
    stm32flash -b 115200 -w /vendor/firmware/${mcu_id}_motor_factory.bin /dev/ttyS1

    release_uart1
}

function reset()
{
    echo 0 > /sys/devices/platform/11010000.spi/spi_master/spi32765/spi32765.0/mcu_boot
    echo 0 > /sys/devices/platform/11010000.spi/spi_master/spi32765/spi32765.0/mcu_rst
    sleep 1
    echo 1 > /sys/devices/platform/11010000.spi/spi_master/spi32765/spi32765.0/mcu_rst
}

#should start mcu logger before update firmware to let mcu logger manage uart1
start_mcu_logger

filesize=`du $DebugFile | cut -f 1`

#save 2000+ lines of reboot trace then overwrite to avoid overflow
if [ "$filesize" -gt "8" ]
then
    echo "0" > $DebugFile
    echo "filesize $filesize >> $DebugFile"
else
    echo "0" >> $DebugFile
    echo "filesize $filesize >> $DebugFile"
fi

if [ ! -f "$hallNormTableFile" ]
then
    echo "3N" >> $DebugFile
fi

echo "1" >> $DebugFile

echo "2N" >> $DebugFile
if [ -z "$currentVersion" ] ||
   [ "$versionMode" = "Diag mode" ] ||
   ([ -n "$updateVersion" ] &&
    [ "$currentVersion" != "$updateVersion" ] &&
    [ "$skipUpdate" != "1" ]); then
    echo "2.0.1" >> $DebugFile
    stat=`flash_regular_img|grep Done`
    while [ "$stat" = "" ]
    do
        sleep 1
        stat=`flash_regular_img|grep Done`
        echo "2.1" >> $DebugFile
    done
    reset
    sleep 10
fi
hall=$(theia_norm_util halldone)
if [ $hall == "1" ]
then
    echo "5" >> $DebugFile
    exit
fi
print "load lut"
echo "2.0.2" >> $DebugFile
stat=`theia_norm_util load|grep done`
loop_count=0
while [ "$stat" = "" ] && [ $loop_count -lt 5 ]
do
    loop_count=`expr $loop_count + 1`
    echo $loop_count
    sleep 1
    stat=`theia_norm_util load|grep done`
    echo "2.2" >> $DebugFile
done
echo "2.4" >> $DebugFile

