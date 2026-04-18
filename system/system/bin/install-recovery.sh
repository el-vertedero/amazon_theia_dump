#!/system/bin/sh
if ! applypatch -c EMMC:/dev/block/platform/bootdevice/by-name/recovery:16046080:f1fa1d9342bcd8326c61bccd19d04630b57c0130; then
  applypatch  EMMC:/dev/block/platform/bootdevice/by-name/boot:10569728:724bfc1694b7547c0bf6898991eab928828c4b6b EMMC:/dev/block/platform/bootdevice/by-name/recovery eb9822d625aa2a2923af8dc1ef312d3fabc19ab1 16044032 724bfc1694b7547c0bf6898991eab928828c4b6b:/system/recovery-from-boot.p && installed=1 && log -t recovery "Installing new recovery image: succeeded" || log -t recovery "Installing new recovery image: failed"
  [ -n "$installed" ] && dd if=/system/recovery-sig of=/dev/block/platform/bootdevice/by-name/recovery bs=1 seek=16044032 && sync && log -t recovery "Install new recovery signature: succeeded" || log -t recovery "Installing new recovery signature: failed"
else
  log -t recovery "Recovery image already installed"
fi
