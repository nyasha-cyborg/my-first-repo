# Stability (mode-B stall) — working state

Last updated: 2026-10-19 13:00 · branch `nexus9` · tip `57b8686`

## Symptom
- Expected: auto image boots, shell answers, WiFi comes up, machine stays alive.
- Actual (mode B): USB stays enumerated as `0525:a4a7`, gadget silent, no shell,
  WiFi unreachable. Watchdog does **not** fire (mode A: whole machine dies and
  the watchdog does reset; verified).
- Since: repeated since ~00:33 on 2026-10-19; current stall began ~00:35.

## Environment
- Tablet: Nexus 9 (flounder), stock Android `HT4C3WV00112` normally; test images
  via `fastboot boot`.
- Kernel: `6.19.0-htc-flounder-g65429d8f78f5` #115, built 2026-10-19 00:18.
- At 08:25 the tablet was in Android, `ro.boot.bootreason=cold_boot`, uptime
  1 min — i.e. a human power cycle happened; the record was readable.

## Current hypotheses
| # | Hypothesis | Test | Result | Status |
|---|------------|------|--------|--------|
| 1 | Raw eMMC record write (every 10 s) stalls the machine | `n9console` (record on, WiFi off) | **stalled in <50 s** — record path still live | **leading** |
| 2 | brcmfmac/SDIO probe wedges the system | `n9console` boots with `/etc/no-wifi` | stalled anyway → not *required* | dead as necessary cause |
| 3 | MMC/SDIO runtime PM | `n9auto15pm` (runtime PM off) | not run | open |
| 4 | eMMC writeback after the emit | timing cannot separate from (1) yet | — | open |
| 5 | Battery undervoltage / brownout (6 %, 3.5 V under load) | charged to 87 % and repeated | no stall on the minimal image | confound removed |
| 6 | Something `init-auto` adds on top of a plain shell (watchdog open, record write, WiFi, runtime-PM sweep) | minimal shell = mounts + tty wait + sh: **stable 10 min**; `bare` (= +watchdog open) silent | watchdog-open test running | **leading** |

## Evidence (trimmed)

Record dump, read from Android after the power cycle:
```
$ adb root; adb exec-out "dd if=/dev/block/mmcblk0 bs=512 skip=79872 count=64" > /tmp/n9record.bin
$ python3 -I  # header: "N9LOG2\n" + u64 len + u64 flags, text at offset 23
len= 31655 flags(uptime)= 0        # flags==0 -> init predates commit ee4212a
first: 6,0,0,-;Booting Linux on physical CPU 0x0000000000 [0x4e0f0000]
       5,1,0,-;Linux version 6.19.0-htc-flounder-g65429d8f78f5 ... #115
last:  6,444,23167961,-;brcmfmac: brcmf_c_process_txcap_blob: no txcap_blob available (err=-2)
       6,445,23169186,-;brcmfmac: brcmf_c_preinit_dcmds: Firmware: BCM4354/1 wl0:
              Apr  9 2021 00:35:31 version 7.35.349.104 (775a9ab CY) FWID 01-d55901b0
```
Interpretation:
- init sleeps 20 s before WiFi; module load starts at 22.9 s. The monitor emits
  every 10 s, so the record containing a 23.17 s line was written at ~32.7 s.
- No *info-level* message after 23.17 s, but brcmfmac's remaining attach
  messages are debug-level, so this does **not** prove the probe was stuck.
  Treat 23.17 s as the last logged activity, not the stall point.
- The record containing that line was written by the ~32.7 s emit, so the
  machine was alive at 32.7 s and dead before the ~42.7 s emit. That window
  brackets the *next* record write — consistent with the original eMMC-write
  suspect.
- No `hung task`, lockdep or mmc error was recorded before the silence.

Also relevant from this record: `mmc1: Switching to 3.3V signalling voltage
failed` at 1.09 s (also appears on working boots); `mmc1: new UHS-I speed
SDR104 SDIO card` at 1.60 s; both mmc hosts came up.

### Mode B reproduced without WiFi (2026-10-19 08:29–08:31)

```
08:29:22 === n9console            # /etc/no-wifi, record monitor ON
08:29:36 booted, waiting for gadget
08:30:26 shell unresponsive after 15s
```
Gadget stays enumerated (`0525:a4a7`), `/dev/ttyACM0` exists, but manual
probes with `stty ... raw -echo` are silent. This is mode B, and
**WiFi/brcmfmac was never loaded**, so the SDIO probe cannot be the necessary
cause. Recovery was not observed directly this time — by 08:45 the tablet was
back in Android, but a human power cycle cannot be ruled out, so the
120 s-watchdog question stays open for this boot. The raw eMMC record write returns as the
leading suspect. Earlier in the same session the same image ran >80 s with a
working shell (the earlier console boot answered a manual probe >80 s in), so
the stall is intermittent.

### Battery is nearly flat — a confound for every stall result

Measured in Android at 08:45 after the power cycle:
```
USB powered: true      status: 2 (charging)
capacity:    6–7 %      voltage_now: 3.49–3.70 V
current_now: -2.41 A (boot spike) -> +0.16..+0.26 A (screen off, asleep)
```
The host port supplies only ~0.26 A net; the screen was already off and the
device asleep. At this level the pack is at ~3.5 V under load and a boot drains
faster than USB can replenish, so **brownout or undervoltage is a plausible
alternative cause of mode B**, and every recent stall result is confounded.
Do not run boot/flash tests until the pack is back above ~40 % on a wall
charger. Charge state is only visible from Android; the test kernel exports no
battery class.

### Bare test was a console-attach race, not a stall (12:27)

```
12:27:49 === n9bare        # /etc/no-record + /etc/no-wifi
12:28:03 booted, waiting for gadget
12:28:54 shell unresponsive after 15s
```
Manual probes are silent, but the gadget appeared late: the timestamps imply
~20 s after `fastboot boot`. `init-auto.c` waited only **5 s** for
`/dev/ttyGS0`; when the gadget misses that window, the shell inherits
`console=tty0` and the serial stays silent while the machine is healthy. So
`n9bare` is **not evidence** for or against the record hypothesis yet.

Fix: `init-auto.c` now waits up to 60 s for `ttyGS0`, and `stability-run.sh`
logs how long the gadget took. Rebuilt as
`~/Downloads/nexus9/bootimg-build/n9-mainline/n9bare-tty60-stripped.img`
(kernel region reused from the split bare image, ramdisk repacked with the new
init).

Watchdog note: the earlier auto-boot record contains
`tegra-wdt 60005000.timer: initialized (heartbeat = 120 sec, nowayout = 0)`,
so the driver probes. The console-waiting bare boot still did not reset after
several minutes; either init never reached the `open("/dev/watchdog")` or the
open/arm does not actually fire in this state. Needs checking once a shell is
reachable (`cat /sys/class/watchdog/*/state` is not built: no WATCHDOG_SYSFS).

### Fixed bare image (60 s tty wait) still silent (12:40)

```
12:40:48 === n9bare-tty60
12:41:02 booted, waiting for gadget
12:41:08 gadget after 6s          # well inside the 60 s window
12:41:52 shell unresponsive after 15s
```
Host journal confirms the same boot: fastboot at 12:41:00, gadget 0525:a4a7
enumerated 12:41:06, `ttyACM0` created. Manual probes stay silent; `stty -a`
on `ttyACM0` round-trips (rc=0), so the gadget's kernel control path answers
but no userspace bytes arrive or are echoed.

Ramdisk verified: the image really carries the new 7472-byte init, `/bin/sh`
→ busybox exists, `/etc/no-record` and `/etc/no-wifi` present. The screen check
was uninformative (panel never lit, see above). The minimal-shell result below
is the useful discriminator: same kernel and gadget, plain init works.

### Minimal shell is stable for 10 minutes (12:45–12:59)

Image: mounts `devtmpfs`/`proc`/`sys`, waits up to 30 s for `ttyGS0`, execs
`sh -i`. No watchdog open, no record, no WiFi.
```
12:45:48 booted, waiting for gadget
12:45:54 gadget after 6s
12:59:47 STABLE for 10 min
```
So kernel, USB device mode, `ttyGS0`, and a userspace shell are healthy. The
stall must come from something `init-auto` does beyond this minimal set.
`n9bare-tty60` differs from this image in exactly one functional step: it opens
`/dev/watchdog` (it has `/etc/no-record` and `/etc/no-wifi`). The next image
(`n9wdtest-stripped.img`) reproduces the minimal init and adds only that open,
with `n9shell: opening watchdog / opened` written to the serial console so a
hang there is visible.

The black screen reported at 12:43 is expected: `display-progress.md` says the
panel was never actually lit (GET_POWER_MODE stays 0), so `console=tty0` shows
nothing and cannot be used as a liveness signal.

### Harness trap found in the first bisection attempt

```
08:26:33 === n9console
08:26:47 booted, waiting for gadget
08:27:05 shell unresponsive after 0s     <- FALSE
```
A manual probe of the same boot answered immediately, but only after
`stty -F /dev/ttyACM0 115200 raw -echo`: the gadget keeps stale line settings,
so the probe echoed `sh: /: Permission denied` in a loop. `stability-run.sh`
now sets raw mode before every probe, treats one lost probe as noise, and can
leave a booted test image with `reboot -f` on the serial shell. The console
image itself ran for 5+ min with a working shell before that reboot.

## Changes since last test cycle
- `init-auto.c`: ttyGS0 wait 5 s → 60 s (commit `55704a4`).
- `stability-run.sh`: raw-mode probe, battery guard at 40 %, gadget timing.
- Built `n9bare-tty60`, `n9shell`, and `n9wdtest` images from the same kernel
  region; no kernel change.

## Dead ends — do not retry
- Unbind/rebind `sdhci-tegra` to force an SDIO rescan: blocks in-kernel and
  takes the machine down.
- Trusting the record flags word on images built before ee4212a (04:20): it is
  hard-coded 0, so those records cannot prove freshness.

## Next actions
1. Read the `n9wdtest` result (running since 13:00):
   - shell appears, then dies when the watchdog opens → watchdog open is the
     trigger; inspect `tegra_wdt_start` / WDT reset path.
   - shell never appears, no "opening watchdog" line → the hang is before the
     open (ramdisk/init difference), not the watchdog.
   - stable 10 min → the watchdog is innocent; next add only the record write,
     then only the WiFi child.
2. Once the minimal delta is isolated, fix it and re-run `auto18` for 10 min.
3. Then re-test `auto15pm` (runtime PM off) only if WiFi is implicated.

## Rebuild recipe (for the fixed image)

```
clang --target=aarch64-linux-gnu -nostdlib -static -O2 -fuse-ld=lld \
      -o init-new tools/miniroot/init-auto.c
# replace ./init inside an extracted ramdisk, then:
(cd ramdisk-dir && find . -print0 | cpio --null -o -H newc --owner=0:0 --quiet) \
      | gzip -9 > new-ramdisk.gz
python3 tools/bootimg-split.py old-stripped.img out/     # kernel + ramdisk
python3 tools/bootimg-repack.py --stock old-stripped.img \
      --image out/kernel --ramdisk new-ramdisk.gz -o new-stripped.img
```
`--stock` may itself be a wrapper-stripped image; the tool warns and writes a
bare `ANDROID!` image, which is what `fastboot boot` wants.
