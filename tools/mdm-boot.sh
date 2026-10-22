#!/bin/sh
# Bring the Nexus 9 LTE modem (MDM9x25 on HSIC, USB2 controller) up from a cold or running state:
#   per-unit data from the tablet's partitions (mdm-data.sh) -> power sequence (modem-gpio-min hold 4,
#   raises AP2MDM_WAKEUP once MDM2AP_STATUS is high) -> boot ROM 05c6:9008 -> Sahara image loader ->
#   modem OS (STATUS=1) -> re-enumerate the HSIC port -> 05c6:9048 -> qmi_wwan -> /dev/cdc-wdm*.
# Needs in the rootfs: /bin/modem-gpio-min, /bin/sahara, the stock vendor/firmware/mdm/image files in
# $FW (sbl1 rpm tz mba apps sdi dsp1 + htc*.mbn stubs + rcdata_*.img), modules qmi_wwan (+ usbnet, cdc-wdm).
# Never writes to any partition.  Log: /tmp/mdm-boot.log
FW=${FW:-/fw}
DSP1=${DSP1:-$FW/dsp1.mbn}
[ -f "$DSP1" ] || DSP1=/tmp/dsp1.mbn
HERE=$(dirname "$0")
USB=/sys/bus/usb/devices
say() { echo "mdm-boot: $*"; }
reenum() { echo 0 > $USB/usb1/authorized; sleep 1; echo 1 > $USB/usb1/authorized; }
pid() { cat $USB/1-1/idProduct 2>/dev/null; }

ARGS=$(OUT=/tmp/mdata.bin "$HERE/mdm-data.sh") || { say "cannot build the per-unit data"; exit 1; }
say "per-unit data ready"
pkill modem-gpio-min 2>/dev/null; rmmod qcserial 2>/dev/null
sleep 1
(/bin/modem-gpio-min hold 4 > /tmp/mdm.log 2>&1 &)
say "modem power sequence started"
i=0
while [ "$(pid)" != 9008 ]; do
	i=$((i + 1)); [ $i -gt 40 ] && { say "boot ROM 9008 never showed up"; tail -2 /tmp/mdm.log; exit 2; }
	[ $i = 12 ] && reenum
	sleep 1
done
say "boot ROM enumerated after ~${i}s"
N=$(printf "/dev/bus/usb/%03d/%03d" "$(cat $USB/1-1/busnum)" "$(cat $USB/1-1/devnum)")
/bin/sahara "$N" 21:$FW/sbl1.mbn 23:$FW/rpm.mbn 25:$FW/tz.mbn 31:$FW/mba.mbn 8:"$DSP1" 6:$FW/apps.mbn \
	30:$FW/sdi.mbn $ARGS > /tmp/sahara.log 2>&1
say "sahara done: $(grep -c END_IMAGE_TRANSFER /tmp/sahara.log) images, last: $(grep END_IMAGE /tmp/sahara.log | tail -1)"
i=0
until tail -1 /tmp/mdm.log | grep -q "STATUS=1"; do
	i=$((i + 1)); [ $i -gt 20 ] && { say "MDM2AP_STATUS never went high"; tail -1 /tmp/mdm.log; exit 3; }
	sleep 1
done
say "modem OS is up (MDM2AP_STATUS=1)"
modprobe qmi_wwan 2>/dev/null
sleep 1
reenum
i=0
while [ "$(pid)" != 9048 ]; do
	i=$((i + 1)); [ $i -gt 30 ] && { say "05c6:9048 never showed up"; tail -1 /tmp/mdm.log; exit 4; }
	sleep 1
done
sleep 3
say "modem enumerated as 05c6:9048: $(ls /dev/cdc-wdm* 2>/dev/null | tr '\n' ' ')"
tail -1 /tmp/mdm.log
