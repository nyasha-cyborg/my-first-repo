#!/bin/bash
# Probe the two TFA9895 speaker amps while a tone plays, trying the vendor's
# register recipe step by step and recording each amp's status (R0) after
# every change.  Needs an image with tone-min + i2c16-min (n9ampA) booted by
# tools/n9boot.sh <img> load-audio.   usage: tools/amp-probe.sh
HERE=$(dirname "$0")
S() { "$HERE/n9sh.sh" "$1" "${2:-6}"; }
rd() { S "echo \$(/bin/i2c16-min 1 $1 $2)" 4; }
dump() {
	for a in 34 35; do
		printf "amp 0x%s: " $a
		for r in 00 01 02 03 04 05 06 07 08 09 0a; do printf "r%s=%s " $r "$(rd $a $r)"; done
		echo
	done
}
decode() {  # R0 status bits
	python3 -I -c "
v=int('$1',16)
names={0:'VDDS',1:'PLLS',2:'OTDS',3:'OVDS',4:'UVDS',5:'OCDS',6:'CLKS',7:'CLIPS',8:'MTPB',9:'NOCLK',11:'SPKS',12:'ACS',13:'SWS',14:'WDS',15:'AMPS'}
print(' '.join(n for b,n in sorted(names.items()) if v>>b&1) or '-')"
}
status() { for a in 34 35; do v=$(rd $a 00); echo "  amp 0x$a R0=$v: $(decode $v)"; done; }

S 'mount -t debugfs none /sys/kernel/debug 2>/dev/null; /bin/tone-min 0 0 200 440 10 >/tmp/tone.log 2>&1 &' 3 >/dev/null
sleep 8
echo "== baseline during playback"; dump; status
echo "== step 1: R4 = 0x8853 (vendor I2S register)"
for a in 34 35; do S "/bin/i2c16-min 1 $a 04 8853" 3 >/dev/null; done; sleep 1; status
echo "== step 2: R9 |= 0x0010 (DCA, boost on)"
for a in 34 35; do v=$(rd $a 09); n=$(printf '%04x' $(( 0x$v | 0x0010 ))); S "/bin/i2c16-min 1 $a 09 $n" 3 >/dev/null; done; sleep 1; status
echo "== step 3: R8 |= 0x0400 (vendor speaker block bit)"
for a in 34 35; do v=$(rd $a 08); n=$(printf '%04x' $(( 0x$v | 0x0400 ))); S "/bin/i2c16-min 1 $a 08 $n" 3 >/dev/null; done; sleep 1; status
echo "== step 4: R6 &= ~0x0020 (vendor unmute bit)"
for a in 34 35; do v=$(rd $a 06); n=$(printf '%04x' $(( 0x$v & ~0x0020 ))); S "/bin/i2c16-min 1 $a 06 $n" 3 >/dev/null; done; sleep 1; status
echo "== final dump"; dump
