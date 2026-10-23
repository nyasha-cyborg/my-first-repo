#!/bin/bash
# Reboot into pmOS N times; after each boot record GR init, the GPU clock, greetd/phoc and resets.
#   usage: tools/pmos/gpu-boot-test.sh [cycles] [ip]
HERE=$(dirname "$0")
N=${1:-4}
IP=${2:-192.168.1.109}
SSH="ssh -o ConnectTimeout=5 -o BatchMode=yes root@$IP"
for c in $(seq 1 "$N"); do
	"$HERE/pmboot.sh" "" "$IP" >/dev/null || { echo "cycle $c: pmOS did not come up"; continue; }
	sleep 90
	r=$($SSH 'D=/sys/class/devfreq/57000000.gpu
		gr=ok; dmesg | grep -q "gr: init failed" && gr=FAIL
		pf=$(dmesg | grep -c "PRIVRING")
		ph=$(pgrep phoc >/dev/null && echo up || echo down)
		echo "up=$(cut -d. -f1 /proc/uptime)s gr=$gr privring=$pf phoc=$ph gpu=$(($(cat $D/cur_freq)/1000000))MHz min=$(($(cat $D/min_freq)/1000000)) trans=$(tail -1 $D/trans_stat | grep -o "[0-9]*$") greetd=$(rc-service greetd status 2>&1 | sed "s/.*status: //")"' 2>&1)
	echo "cycle $c $(date +%T): $r"
done
