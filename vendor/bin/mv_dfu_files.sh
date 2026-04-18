#!/vendor/bin/sh

dfu_dir="/data/vendor/halo/tmp/dfu"

print_and_exit() {
    echo $1
    exit 0
}

remove_and_exit() {
    rm ${dfu_dir}/${1}*
    exit 0
}

[ "$#" -eq 1 ] && remove_and_exit $1

[ "$#" -ge 2 ] || print_and_exit "Serial number and version arguments not provided"

cd $dfu_dir

for ra in *release*
do
    if [ -f $ra ]
    then
        echo $ra
        mv $ra "${1}-${2}-application.${ra##*.}"
    fi
done

for da in *debug*
do
    if [ -f $da ]
    then
        echo $da
        mv $da "${1}-${2}-application.${da##*.}"
    fi
done

for sb in sd_bl*
do
    if [ -f $sb ]
    then
        echo $sb
        mv $sb "${1}-${2}-softdevice_bootloader.${sb##*.}"
    fi
done



