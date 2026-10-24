#!/bin/bash
# Boot-reliability soak for the Nexus 9. Uses `fastboot boot` only, never flashes.
#
#   usage: tools/soak-boot.sh [--dry-run] IMG [N]
#
#   IMG   wrapper-stripped boot image (first 8 bytes "ANDROID!")
#   N     iterations (default 10)
#
# Per iteration the tablet is brought to fastboot (Android and pmOS are handled by
# tools/pmos/pmboot.sh, whose helpers are sourced below), IMG is uploaded with
# `fastboot boot`, and the result is classified:
#
#   pmos-ssh     ssh root@192.168.1.109 answers `uname -r` (htc-flounder kernel)
#   pmos-serial  USB gadget 0525:a4a7 is present and its serial shell answers
#   android      adb reports a device (hboot ignored the image, or a hung boot was
#                watchdog-reset back to Android)
#   ignored      still in fastboot 20 s after a successful upload: image never ran
#   no-boot      no USB at all after the upload (no fastboot/Android/gadget)
#   hang         gadget enumerated but userspace never answered (or it vanished and
#                nothing answered for 180 s)
#
# Never power-cycles: a hung board is left for the tegra watchdog, optionally waited
# on for SOAK_WATCHDOG seconds (default 200; 0 disables) before the next iteration.
#
# One line per boot goes to $SOAK_LOG (default /tmp/soak-boot.log); a summary with
# counts, success rate and mean boot time is printed at the end. The running kernel
# release is read over ssh/serial and the kernel boot_id is compared with the
# previous success, so a stale SSH endpoint cannot be scored as a fresh boot.
#
# Environment: SOAK_TIMEOUT=240 (per boot), SOAK_TOTAL (default N*(TIMEOUT+90)+300),
#              SOAK_WATCHDOG=200, SOAK_LOG=/tmp/soak-boot.log.
set -o pipefail

SOAK_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
SOAK_LOG=${SOAK_LOG:-/tmp/soak-boot.log}
BOOT_TIMEOUT=${SOAK_TIMEOUT:-240}
HANG_GRACE=180
N=10
IMG=
DRY=0

usage() {
	awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); print } else { exit } }' "$0"
}

die() { echo "soak-boot: $*" >&2; exit 2; }

# --- argument parsing -------------------------------------------------------
args=()
while [ $# -gt 0 ]; do
	case $1 in
	--dry-run|-n) DRY=1; shift ;;
	-h|--help) usage; exit 0 ;;
	--) shift; while [ $# -gt 0 ]; do args+=("$1"); shift; done ;;
	-*) die "unknown option: $1 (try --help)" ;;
	*) args+=("$1"); shift ;;
	esac
done
[ ${#args[@]} -ge 1 ] || die "missing IMG (try --help)"
[ ${#args[@]} -le 2 ] || die "too many arguments (try --help)"
IMG=${args[0]}
[ ${#args[@]} -ge 2 ] && N=${args[1]}
[[ $N =~ ^[0-9]+$ ]] && [ "$N" -gt 0 ] || die "N must be a positive integer, got '$N'"
SOAK_TOTAL=${SOAK_TOTAL:-$((N * (BOOT_TIMEOUT + 90) + 300))}
[[ $SOAK_TOTAL =~ ^[0-9]+$ ]] || die "SOAK_TOTAL must be seconds"
WATCHDOG=${SOAK_WATCHDOG:-200}
[[ $WATCHDOG =~ ^[0-9]+$ ]] || die "SOAK_WATCHDOG must be seconds"

if [ ! -f "$IMG" ]; then
	if [ "$DRY" = 1 ]; then
		echo "soak-boot plan: image $IMG (MISSING)"
	else
		die "no such image: $IMG"
	fi
elif [ "$(head -c 8 "$IMG")" != "ANDROID!" ]; then
	# hboot accepts a wrapper-wrapped upload and silently does nothing (notes/usb-debug.md).
	echo "soak-boot: WARNING: $IMG is not wrapper-stripped; hboot will ignore it" >&2
fi

if [ "$DRY" = 1 ]; then
	cat <<EOF
soak-boot plan (dry run: no device access)
  image            $IMG
  iterations       $N
  per-boot timeout ${BOOT_TIMEOUT}s (upload + wait)
  hang grace       ${HANG_GRACE}s after the gadget vanishes
  watchdog wait    ${WATCHDOG}s after a hang (0 = do not wait)
  overall cap      ${SOAK_TOTAL}s
  log              $SOAK_LOG
  transport        fastboot boot only; never flashes; never power-cycles
  helper           $SOAK_DIR/pmos/pmboot.sh (Android/pmOS -> fastboot)
  kernel check     ssh/serial 'uname -r' + /proc/sys/kernel/random/boot_id
  outcomes         pmos-ssh pmos-serial android ignored no-boot hang
  loop             1..$N: ensure fastboot (<=60s) -> fastboot boot -> classify -> log
EOF
	exit 0
fi

# --- shared helpers (fastboot/Android/pmOS detection and to_bootloader) ------
# shellcheck source=pmos/pmboot.sh
. "$SOAK_DIR/pmos/pmboot.sh" || die "cannot source pmos/pmboot.sh"

SOAK_DEADLINE=$((SECONDS + SOAK_TOTAL))
DEADLINE=$SOAK_DEADLINE
# The sourced helper logs with say(); route everything through the soak log instead.
say() { local m; m="soak-boot $(date -Iseconds): $*"; echo "$m"; echo "$m" >>"$SOAK_LOG"; }

ssh_kernel() { timeout 12 $SSH 'uname -r' 2>/dev/null | tr -d '\r' | tail -1; }
ssh_boot_id() { timeout 12 $SSH 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null | tr -d '\r' | tail -1; }
serial_kernel() { serial 'uname -r' 5 2>/dev/null | tr -d '\r' | tail -1; }
serial_boot_id() { serial 'cat /proc/sys/kernel/random/boot_id' 5 2>/dev/null | tr -d '\r' | tail -1; }

# Bring the board to fastboot within 60 s, reusing pmboot.sh's to_bootloader for
# Android (adb reboot bootloader) and pmOS (PMC reboot-mode bit + SysRq), serial included.
ensure_fastboot() {
	local end=$((SECONDS + 60)) saved=$DEADLINE rc
	while [ $SECONDS -lt $end ]; do
		has_fastboot && return 0
		if has_android || has_gadget || ssh_up; then
			DEADLINE=$end		# keep the helper inside this 60 s window
			to_bootloader; rc=$?
			DEADLINE=$saved
			[ $rc = 0 ] && has_fastboot && return 0
		fi
		sleep 2
	done
	return 1
}

# After a hang, give the tegra watchdog time to reset the board. Never power-cycles.
wait_watchdog() {
	[ "$WATCHDOG" = 0 ] && { say "watchdog wait disabled"; return 0; }
	local end=$((SECONDS + WATCHDOG))
	say "hang: waiting up to ${WATCHDOG}s for the watchdog"
	while [ $SECONDS -lt $end ]; do
		has_fastboot && { say "board is back in fastboot"; return 0; }
		has_android && { say "board is back in Android"; return 0; }
		sleep 3
	done
	say "board still unresponsive; leaving it to the watchdog (no power cycle)"
	return 1
}

# One upload + bounded classification. Sets OUTCOME, DURATION, KERNEL, BOOT_ID, NOTE.
run_one() {
	OUTCOME=; DURATION=0; KERNEL=; BOOT_ID=; NOTE=
	local t0=$SECONDS start seen=0 gone_since=0 last="" state serial_at=0 out rc
	say "boot $1/$N: fastboot boot $(basename "$IMG")"
	out=$(timeout 120 fastboot boot "$IMG" 2>&1); rc=$?
	printf '%s\n' "$out" >>"$SOAK_LOG"
	if [ $rc -ne 0 ] || ! printf '%s' "$out" | grep -qiE 'Booting|OKAY'; then
		OUTCOME=no-boot
		NOTE="upload failed rc=$rc: $(printf '%s' "$out" | tail -1)"
		DURATION=$((SECONDS - t0))
		return
	fi
	start=$SECONDS
	while [ $((SECONDS - start)) -lt $BOOT_TIMEOUT ] && [ $SECONDS -lt $SOAK_DEADLINE ]; do
		if has_gadget; then state=gadget
		elif has_fastboot; then state=fastboot
		elif has_android; then state=android
		else state=none; fi
		[ "$state" != "$last" ] && { say "boot $1: usb $state ($((SECONDS - start))s)"; last=$state; }
		case $state in
		gadget)
			[ $seen = 0 ] && seen=$SECONDS
			if ssh_up; then
				KERNEL=$(ssh_kernel)
				BOOT_ID=$(ssh_boot_id)
				OUTCOME=pmos-ssh
				break
			fi
			# WiFi is the flaky path; once past ~25 s also try the USB serial shell.
			if [ $((SECONDS - seen)) -ge 25 ] && [ $((SECONDS - serial_at)) -ge 20 ]; then
				serial_at=$SECONDS
				if serial_up; then
					KERNEL=$(serial_kernel)
					BOOT_ID=$(serial_boot_id)
					OUTCOME=pmos-serial
					break
				fi
			fi
			;;
		fastboot)
			# Still in fastboot 20 s after "Booting OKAY": upload accepted but never run.
			[ $((SECONDS - start)) -ge 20 ] && { OUTCOME=ignored; break; }
			;;
		android)
			OUTCOME=android
			[ $seen != 0 ] && NOTE="watchdog reset after gadget"
			break
			;;
		none)
			# No USB at all after the upload: hard hang or the board is off.
			if [ $seen = 0 ] && [ $((SECONDS - start)) -ge 45 ]; then
				OUTCOME=no-boot
				NOTE="no USB 45s after upload"
				break
			fi
			if [ $seen != 0 ]; then
				[ $gone_since = 0 ] && gone_since=$SECONDS
				if [ $((SECONDS - gone_since)) -ge $HANG_GRACE ]; then
					OUTCOME=hang
					NOTE="gadget vanished, nothing answered for ${HANG_GRACE}s"
					break
				fi
			fi
			;;
		esac
		sleep 2
	done
	if [ -z "$OUTCOME" ]; then
		if [ $seen != 0 ]; then
			OUTCOME=hang
			NOTE="gadget enumerated, userspace silent for $((SECONDS - start))s"
		else
			OUTCOME=no-boot
			NOTE="no USB within $((SECONDS - start))s"
		fi
	fi
	DURATION=$((SECONDS - t0))
}

# --- run --------------------------------------------------------------------
mkdir -p "$(dirname "$SOAK_LOG")" 2>/dev/null
: >"$SOAK_LOG" 2>/dev/null || true
declare -A COUNT=( [pmos-ssh]=0 [pmos-serial]=0 [android]=0 [ignored]=0 [no-boot]=0 [hang]=0 )
STALE=0
SUCCESS=0
SUM_BOOT=0
LAST_BOOT_ID=
say "start image=$(basename "$IMG") n=$N per_boot=${BOOT_TIMEOUT}s cap=${SOAK_TOTAL}s"

for i in $(seq 1 "$N"); do
	if [ $SECONDS -ge $SOAK_DEADLINE ]; then
		say "overall cap ${SOAK_TOTAL}s reached before boot $i"
		break
	fi
	ITER_T0=$SECONDS
	if ! ensure_fastboot; then
		OUTCOME=no-boot
		DURATION=$((SECONDS - ITER_T0))
		KERNEL=; BOOT_ID=
		NOTE="no fastboot device within 60s"
	else
		run_one "$i"
	fi

	# Stale-result detection: a fresh boot must expose a new kernel boot_id.
	if [ "$OUTCOME" = pmos-ssh ] || [ "$OUTCOME" = pmos-serial ]; then
		if [ -z "$KERNEL" ] || ! printf '%s' "$KERNEL" | grep -q htc-flounder; then
			STALE=$((STALE + 1))
			NOTE="${NOTE:+$NOTE; }kernel release unreadable: '${KERNEL}'"
		elif [ -n "$BOOT_ID" ] && [ "$BOOT_ID" = "$LAST_BOOT_ID" ]; then
			STALE=$((STALE + 1))
			NOTE="${NOTE:+$NOTE; }stale ssh/serial: boot_id $BOOT_ID reused"
		else
			SUCCESS=$((SUCCESS + 1))
			SUM_BOOT=$((SUM_BOOT + DURATION))
			[ -n "$BOOT_ID" ] && LAST_BOOT_ID=$BOOT_ID
		fi
	fi
	[ -z "$OUTCOME" ] && { OUTCOME=no-boot; NOTE="${NOTE:+$NOTE; }unclassified"; }
	COUNT[$OUTCOME]=$(( ${COUNT[$OUTCOME]:-0} + 1 ))

	printf '%s boot=%d/%d outcome=%s dur=%ds kernel=%s boot_id=%s%s\n' \
		"$(date -Iseconds)" "$i" "$N" "$OUTCOME" "$DURATION" \
		"${KERNEL:-unknown}" "${BOOT_ID:-unknown}" \
		"${NOTE:+ note=\"$NOTE\"}" | tee -a "$SOAK_LOG"

	[ "$OUTCOME" = hang ] && wait_watchdog
done

TOTAL_RUNS=0
for k in pmos-ssh pmos-serial android ignored no-boot hang; do
	TOTAL_RUNS=$((TOTAL_RUNS + COUNT[$k]))
done
if [ $TOTAL_RUNS -gt 0 ]; then
	RATE=$(awk -v s=$SUCCESS -v t=$TOTAL_RUNS 'BEGIN { printf "%.1f", 100*s/t }')
else
	RATE=0.0
fi
if [ $SUCCESS -gt 0 ]; then
	MEAN=$(awk -v s=$SUM_BOOT -v n=$SUCCESS 'BEGIN { printf "%.1f", s/n }')
else
	MEAN=n/a
fi
SUMMARY="summary: runs=$TOTAL_RUNS pmos-ssh=${COUNT[pmos-ssh]} pmos-serial=${COUNT[pmos-serial]} android=${COUNT[android]} ignored=${COUNT[ignored]} no-boot=${COUNT[no-boot]} hang=${COUNT[hang]} stale=$STALE successes=$SUCCESS success_rate=${RATE}% mean_boot=${MEAN}s image=$(basename "$IMG")"
echo "$SUMMARY"
echo "$SUMMARY" >>"$SOAK_LOG"
[ $SUCCESS -gt 0 ] && exit 0
exit 1
