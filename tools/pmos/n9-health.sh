#!/bin/sh
# Health-checked watchdog feeder (see n9-health.initd). Grace period: 3 failed checks in a row (~30 s) before
# it stops petting; then the hardware watchdog (heartbeat 60 s) resets the tablet.
# The magic close character "V" is never written, so a killed feeder also ends in a reset.
exec 3>/dev/watchdog || exit 1
log() { echo "<5>n9-health: $*" > /dev/kmsg; }
fails=0
n=0
while true; do
	ok=1
	# a live sshd sends its "SSH-2.0-..." banner at once
	b=$(timeout 5 nc 127.0.0.1 22 </dev/null 2>/dev/null | head -c 3)
	[ "$b" = SSH ] || ok=0
	[ $ok = 1 ] && { timeout 5 /bin/true || ok=0; }
	if [ $ok = 1 ]; then
		fails=0
		printf '.' >&3
	else
		fails=$((fails + 1))
		log "check failed ($fails/3)"
		[ $fails -lt 3 ] && printf '.' >&3
	fi
	n=$((n + 1))
	if [ $((n % 3)) = 0 ]; then
		m=$(awk '/^(MemAvailable|SwapFree|CmaFree):/{printf "%s %dM ", $1, $2/1024}' /proc/meminfo)
		top=$(ps -o rss,comm 2>/dev/null | sort -rn | head -3 | awk '{printf "%s:%dM ", $2, $1/1024}')
		t=$(for z in /sys/class/thermal/thermal_zone*; do [ -r $z/temp ] && printf '%s:%d ' "$(cat $z/type | cut -d- -f1)" $(( $(cat $z/temp) / 1000 )); done)
		f=$(( $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo 0) / 1000 ))
		log "mem $m| load $(cut -d' ' -f1-3 /proc/loadavg) | temp $t| cpu ${f}MHz | top $top"
	fi
	sleep 10
done
