#!/bin/bash
# Re-run the modem boot on an ALREADY booted test image (tools/lte-sahara-test.sh did the boot and
# left /tmp/dsp1.mbn in the tablet's RAM): restart the modem power sequence, re-enumerate the
# HSIC port, run the Sahara loader and watch for the modem's second USB identity.
# Log: /tmp/n9build/lte-retry.txt        No flashing, no EFS partition is touched.
HERE=$(dirname "$0")
if [ -f "$HOME/Downloads/nexus9/modem-private/sahara-args.txt" ]; then
	MODEMARGS=$(cat "$HOME/Downloads/nexus9/modem-private/sahara-args.txt")
else
	MODEMARGS="16:=zero 17:=zero 40:+/fw/htcssmem.mbn 42:+/fw/htcnvmfg.mbn 43:+/fw/htcrfnv.mbn 45:+/fw/htcuserd.mbn 46:+/fw/htccdma.mbn 44:+/fw/htccnv_a.mbn 47:+/fw/htccnv_t.mbn 48:+/fw/htccnv_v.mbn 49:+/fw/htccnv_s.mbn 55:+/fw/htccnv_u.mbn 56:+/fw/htccnv_o.mbn"
fi
OUT=/tmp/n9build/lte-retry.txt
BASEARGS='21:/fw/sbl1.mbn 23:/fw/rpm.mbn 25:/fw/tz.mbn 31:/fw/mba.mbn 8:/tmp/dsp1.mbn 6:/fw/apps.mbn 30:/fw/sdi.mbn'
{
echo "== restart the modem"
"$HERE/n9sh.sh" 'ls -l /tmp/dsp1.mbn; /bin/busybox pkill modem-gpio-min; /bin/busybox pkill mgm; sleep 2; dmesg -c >/dev/null; ('"${MGM:-/bin/modem-gpio-min}"' hold '"${HOLDARG:-4}"' > /tmp/mdm.log 2>&1 &); sleep 9; tail -1 /tmp/mdm.log; P=/sys/kernel/debug/tegra-hsic-poke; echo "174 0 1000" > $P; sleep 1; echo "174 1000 0" > $P; sleep 6; for d in /sys/bus/usb/devices/1-1*; do [ -f $d/idProduct ] && echo $d $(cat $d/idVendor $d/idProduct $d/devnum); done; dmesg | grep -E "usb 1-" | cut -c1-110 | tail -4' 60
echo "== arm the watcher + run sahara"
"$HERE/n9sh.sh" '(while ! tail -1 /tmp/mdm.log | grep -q "STATUS=1"; do sleep 1; done; echo "STATUS=1 seen: $(tail -1 /tmp/mdm.log | cut -c1-12)"; dmesg -c >/dev/null; for i in $(seq 1 45); do [ $i = 12 ] && { echo 0 > /sys/bus/usb/devices/usb1/authorized; sleep 1; echo 1 > /sys/bus/usb/devices/usb1/authorized; echo "(authorized toggle)"; }; echo "t$i $(for d in /sys/bus/usb/devices/1-1*; do [ -f $d/idProduct ] && echo -n "$(basename $d)=$(cat $d/idVendor):$(cat $d/idProduct) "; done) | $(tail -1 /tmp/mdm.log | cut -c1-70) | portsc $(grep ^174 /sys/kernel/debug/tegra-hsic-regs | cut -d" " -f2)"; sleep 1; done; dmesg | grep -E "usb 1-" | cut -c1-130 | tail -20) > /tmp/second.log 2>&1 &' 5
"$HERE/n9sh.sh" 'B=$(cat /sys/bus/usb/devices/1-1/busnum); D=$(cat /sys/bus/usb/devices/1-1/devnum); N=$(printf "/dev/bus/usb/%03d/%03d" $B $D); echo node $N; (/bin/sahara $N '"$BASEARGS $MODEMARGS"' > /tmp/sahara.log 2>&1 &); for i in $(seq 1 150); do pgrep sahara >/dev/null || break; sleep 2; done; grep -vE "^rx cmd=3" /tmp/sahara.log | tail -12' 330
echo "== second enumeration (watcher log)"
"$HERE/n9sh.sh" 'for i in $(seq 1 30); do grep -q "^t45 " /tmp/second.log 2>/dev/null && break; sleep 3; done; cut -c1-200 /tmp/second.log; echo; echo "mdm.log milestones:"; grep -nE "STATUS=1|ERRFATAL=1" /tmp/mdm.log | sed -n "1p;\$p"' 120
echo flush
} 2>&1 | tee "$OUT"
