#!/bin/bash
# Push a file to the tablet over WiFi/SSH in small, checksummed parts.
#
# Why: a single large scp dirties the loop-mounted rootfs (/data/pmos/rootfs.img)
# in one burst and has hung the tablet (notes/pmos.md, notes/stability-debug.md).
# Small parts + per-part sha256 + no global sync bound each write burst and make a
# stall easy to localise.
#
# Usage: tools/pmos/push-small.sh <local-file> [remote-dir] [part-MiB] [user@host]
#   defaults: remote-dir /tmp/video, part-MiB 4, host root@192.168.1.109
# Env:
#   N9_IP          default host (overridden by the 4th argument)
#   N9_SCP_LIMIT   scp bandwidth limit in kbit/s (0 = unlimited)
#   N9_KEEP=1      keep the split parts on the host
#   N9_JOIN=1      concatenate the parts on the tablet (writes the loop rootfs!)
#
# The remote directory is created if missing. A warning is printed when the
# destination is not tmpfs, because then the parts themselves are written to the
# loop-mounted rootfs.
set -euo pipefail

SRC=${1:?usage: push-small.sh <local-file> [remote-dir] [part-MiB] [user@host]}
RDIR=${2:-/tmp/video}
PART_MB=${3:-4}
HOST=${4:-${N9_IP:-192.168.1.109}}
HOST=${HOST##*@}
SSH="ssh -o ConnectTimeout=5 -o BatchMode=yes root@$HOST"
SCP="scp -o ConnectTimeout=5 -o BatchMode=yes"

[ -f "$SRC" ] || { echo "no such file: $SRC" >&2; exit 1; }
case $PART_MB in ''|*[!0-9]*) echo "part-MiB must be an integer" >&2; exit 1;; esac
[ "$PART_MB" -ge 1 ] && [ "$PART_MB" -le 64 ] || { echo "part-MiB out of range (1..64)" >&2; exit 1; }

base=$(basename "$SRC")
TMP=$(mktemp -d "${TMPDIR:-/tmp}/n9push.XXXXXX")
cleanup() { [ "${N9_KEEP:-0}" = 1 ] || rm -rf "$TMP"; }
trap cleanup EXIT

say() { printf 'push-small: %s\n' "$*"; }

# --- remote checks -----------------------------------------------------------
say "remote $HOST:$RDIR"
$SSH "mkdir -p '$RDIR'" || { echo "cannot create $RDIR on $HOST" >&2; exit 1; }
fstype=$($SSH "findmnt -no FSTYPE -T '$RDIR' 2>/dev/null || stat -f -c %T '$RDIR' 2>/dev/null || echo unknown" | tr -d '\r')
say "remote filesystem: $fstype"
case $fstype in
	tmpfs|ramfs) ;;
	*) say "WARNING: $RDIR is '$fstype', not tmpfs: parts are written to the loop rootfs."
	   say "         mount a tmpfs there first, e.g. mount -t tmpfs -o size=512m,mode=1777 tmpfs $RDIR" ;;
esac

# --- split + local checksums --------------------------------------------------
say "splitting $base into ${PART_MB} MiB parts"
split -b "${PART_MB}M" -d -a 3 "$SRC" "$TMP/part."
( cd "$TMP" && sha256sum part.* > SHA256SUMS )
whole=$(sha256sum "$SRC" | cut -d' ' -f1)
say "whole-file sha256: $whole"

# --- transfer ----------------------------------------------------------------
limit_arg=()
[ "${N9_SCP_LIMIT:-0}" != 0 ] && limit_arg=(-l "$N9_SCP_LIMIT")
say "transferring $(ls "$TMP"/part.* | wc -l) parts${N9_SCP_LIMIT:+ at ${N9_SCP_LIMIT} kbit/s}"
$SCP ${limit_arg[@]+"${limit_arg[@]}"} "$TMP"/part.* "$TMP"/SHA256SUMS "root@$HOST:$RDIR/"

# --- verify ------------------------------------------------------------------
say "verifying sha256 on the tablet"
if ! $SSH "cd '$RDIR' && sha256sum -c SHA256SUMS"; then
	echo "checksum verification failed on the tablet" >&2
	exit 2
fi

# Flush only the transferred files; a bare `sync` forces a global writeback
# through the loop-mounted rootfs, which is exactly what this helper avoids.
$SSH "for f in '$RDIR'/part.*; do sync -f \"\$f\" 2>/dev/null || { sync; break; }; done" >/dev/null 2>&1 || true

# --- optional join -----------------------------------------------------------
if [ "${N9_JOIN:-0}" = 1 ]; then
	say "joining parts into $RDIR/$base on the tablet"
	$SSH "cd '$RDIR' && cat part.* > '$base' && sha256sum '$base'"
	got=$($SSH "sha256sum '$RDIR/$base'" | awk '{print $1}' | tr -d '\r')
	[ "$got" = "$whole" ] || { echo "joined file checksum mismatch: $got != $whole" >&2; exit 3; }
	say "joined file verified"
fi

say "done: $(ls "$TMP"/part.* | wc -l) parts in $RDIR (source sha256 $whole)"
