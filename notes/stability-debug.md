# Stability (mode-B stall) — working state

Last updated: 2026-10-19 22:30 · branch `nexus9`

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
| 1 | Raw eMMC record write (every 10 s) stalls the machine | record-on stable 30 min twice; record-off stalled once | no correlation | dead |
| 7 | USB gadget console path wedges; the machine keeps running | 17:29 stall **self-reset at ~141 s** after the reordered open → pinger stopped → userspace blocked | real system stall | dead |
| 8 | brcmfmac/SDIO probe at the 20 s-delayed module load | 17:29 stall had module loads failing (`-ENOENT`) and no card; 18:16 soak had modules load but card absent | not necessary | dead |
| 9 | Unknown early stall in the `init-auto` path (6–11 s, userspace blocked) | the stall precedes the 26 s WiFi load; minimal `init-ping` image has not stalled yet (one 10-min run) | **one 30-min marker run stable at 62–73 %**; still intermittent, needs samples | **open (weakened)** |
| 2 | brcmfmac/SDIO probe wedges the system | `n9console` boots with `/etc/no-wifi` | stalled anyway → not *required* | dead as necessary cause |
| 3 | MMC/SDIO runtime PM | `n9auto15pm` (runtime PM off) | not run | open |
| 4 | eMMC writeback after the emit | timing cannot separate from (1) yet | — | open |
| 5 | Battery undervoltage / brownout | 6–7 % at 08:45; the 00:35 and 08:29 stalls both fell in that window | but the 14:38 stall happened at 78 % start | weakened |
| 6 | Something `init-auto` adds on top of a plain shell (watchdog open, record write, WiFi, runtime-PM sweep) | minimal shell stable 10 min; `bare` silent; `n9wdtest` (= minimal + watchdog open) silent once, **alive the next run** | not deterministic | open — needs repeated runs |

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
→ busybox exists, `/etc/no-record` and `/etc/no-wifi` present. That boot's
screen was black, but the panel is known to work (see the display correction
below), so the screen is unexplained rather than ignorable. The minimal-shell
result below is the useful discriminator: same kernel and gadget, plain init
works.

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

Display correction: the panel does work. The final section of
`display-progress.md` ("It works: inject panel commands into the running video
stream") confirms console text and the white paint on hardware. So the black
screen at 12:43 was a real observation, not the normal state; by 13:02 the
minimal-shell image shows a console with a blinking cursor on the panel.
Whether 12:43 was a panel state left by the preceding stall or a driver
difference is unrecorded — do not use the screen as a liveness signal without
checking it per boot.

### Watchdog-open image goes silent (13:19)

```
13:20:07 booted, waiting for gadget
13:20:13 gadget after 6s
13:20:57 shell unresponsive after 15s
```
`n9wdtest` = the minimal init plus `open("/dev/watchdog")` after the tty is
attached, with `n9shell: connected / opening watchdog / opened` printed on the
serial. It is silent, like `n9bare` (also opens the watchdog), while the
minimal image without the open is stable. Strong correlation: **opening the
watchdog is the trigger**.

The script's probes had already drained the buffered boot lines, so the last
message was lost. `stability-run.sh` now accumulates every probe's output in
`/tmp/n9-probe.log` and prints the tail when a stall is declared. Confirmation
run needs a power cycle (the reboot path hangs, below).

### Watchdog reset works; automation is possible (13:24–13:27)

The same `n9wdtest` image that was silent at 13:19 ran normally at 13:24:
```
13:24:51 gadget after 6s
/probe log: ~ # echo PROBE_OK -> PROBE_OK   (shell alive)
13:27:00 USB dropped after 90s             (nothing pings the armed WDT)
13:27:   Android 18d1:4ee7 back, adb HT4C3WV00112
```
So the watchdog arm/reset path **does work from the userspace open**, Android
recovers by itself, and no power cycle is needed in that case. The 13:19
silence was an intermittent stall, not a deterministic effect of the open.

This contradicts the handoff's "watchdog does not fire in mode B". Either those
boots never armed it (older init / the open came after the stall), or the
stall blocks the reset path itself. Deliberate test: arm it and never ping
(done above), then arm + ping from userspace and watch a stall.

Consequence for iteration: images now arm the watchdog and ping it from a
dedicated child (`init-auto.c`, plus the new `n9ping` test init). A healthy
system pings every 20 s; if userspace is blocked the pings stop and the box
resets after 120 s. If only the tty path dies while userspace runs, the
machine stays up — that difference is itself evidence.

### Record-free images are stable; the decisive comparison is ready

```
n9ping (minimal + armed/pinged watchdog): 13:28:21 -> 13:42:13 STABLE 10 min
n9shell (minimal, no watchdog):          12:45:54 -> 12:59:47 STABLE 10 min
```
No record-enabled image has yet completed a 10-minute run; every observed
stall so far was on an image with the recording monitor. To test that directly
with no power cycles, all images now arm the watchdog and ping it from
userspace every 20 s; `touch /stop-ping` (sent by the harness) stops the ping
and lets the hardware reset the box back to Android.

Built and ready in `~/Downloads/nexus9/bootimg-build/n9-mainline/`:
| Image | Record | WiFi |
|---|---|---|
| `n9wifi-rec-stripped.img` | on | on |
| `n9wifi-norec-stripped.img` | off | on |
| `n9console-ping-stripped.img` | on | off |
| `n9bare-ping-stripped.img` | off | off |
| `n9ping2-stripped.img` | off | off (shell only) |

Next: alternate `wifi-rec` and `wifi-norec` for several rounds. A stall only
in the record-on image settles hypothesis 1.

### Record-on image is stable at healthy charge (13:48–14:02)

```
13:48:48 gadget after 6s
14:02:40 STABLE for 10 min: n9wifi-rec   # record ON, WiFi ON, pinger
14:02:46 stop-ping set; waiting for the watchdog reset
14:05:37 no android after ~170 s; power cycle needed
```
Two conclusions:

1. The rolling eMMC record is **not deterministically fatal**. The earlier
   record-enabled stalls (00:35 auto, 08:29 console) both fell inside the
   window where the pack was nearly flat (6–7 % measured at 08:45). Every run
   at 78 % or above has been stable. Battery/undervoltage is now the leading
   explanation, with the record unproven.
2. The release path failed because `touch` is not on PATH in the ramdisk
   (no applet symlinks). `release_image` now calls `/bin/busybox touch`.
   The tablet was recovered by `killall init` (busybox) — the pinger died and
   the watchdog reset it, still with no power cycle.

Next: long soak at healthy charge (`N9_DURATION=1800`) to see whether the
intermittent stall appears at all when the pack is full.

### Stall at healthy charge in the 30-min soak (14:38)

```
14:09:24 gadget after 6s
14:38:34 shell unresponsive after 15s     # ~30 min in, started at 78 %
14:38:34 serial capture (last lines):     # empty
14:41:25 no android after ~170 s; power cycle needed
```
This is a real intermittent stall at healthy charge, so the low battery is
not the whole story. The absence of a watchdog reset has two readings:
- userspace (including the pinger) was still running and only the USB/tty
  path died, so the WDT never expired; or
- the watchdog was never armed in init-auto.

init-auto armed the watchdog before the tty existed, so it could not report
the result. It now opens the watchdog **after** the console is attached and
prints `n9wifi: watchdog opened` / `... FAILED` on the serial. The harness
also logs the wlan0 address so a stalled box can be pinged on the network if
the shell is silent. `192.168.1.102` did not answer during this stall, but
that address may not be the current lease.

### Record-off survives 30 minutes; record-on swallowed ~30 min (15:38)

```
14:56:29 gadget after 6s
15:38:05 STABLE for 30 min: n9wifi-norec   # /etc/no-record, WiFi enabled
15:38:11 stop-ping set
15:40:   USB gone, Android 18d1:4ee7 back
```
The same kernel and WiFi configuration without `/etc/no-record` stalls at
about the same point the record-off run completed. The rolling raw eMMC write
is the strongest candidate; it is only a bring-up diagnostic and is not part
of the production/installed-boot path, so it can simply be left off.

Caveat to close: at the 1-minute probe `wlan0` did not exist in this run
(possible SDIO enumeration failure), so the two runs differ in wireless load
as well as the record. The harness now logs `wlan0` at ~60 s and ~300 s to
confirm parity before calling the hypothesis settled.

The `/stop-ping` -> watchdog-reset path worked end to end for the first time:
no power cycle was used to leave this image.

### Paired 30-minute runs contradict the record theory (16:37–17:26)

```
16:37 n9wifi-rec   -> 17:19:42 STABLE for 30 min   (record ON, second time)
17:19 stop-ping    -> 17:22:04 android is back      (watchdog reset)
17:22 n9wifi-norec -> 17:23:08 shell unresponsive   (record OFF!)
17:25:58 no android after ~170 s
```
The record write is not the cause. Worse for the "system stall" reading: the
norec image was silent, but no watchdog reset happened in 170 s, even though
the **same init** had just proven that `/stop-ping` stops the keepalive and the
WDT resets the box. If the WDT was armed (very likely), the only way it does
not fire is that the pinger was still running: **userspace was alive and only
the USB console path died**. The earlier mode-B observations (WiFi also
unreachable) are compatible if the SDIO card simply failed to enumerate, which
happens intermittently.

Working hypothesis now: u_serial / chipidea gadget TX/RX wedges on the host's
open/probe pattern; the kernel and userspace continue.

To confirm independently of USB, init-auto now forks a heartbeat child that
writes `HB <hex counter>` to `/dev/tty0` every 5 s. The panel works, so a
changing counter during a "stall" proves the machine is alive.

### Watchdog now armed reliably; stall is real and self-recovers (17:29)

```
17:29:48 gadget after 6s
17:30:32 shell unresponsive after 15s
17:32:53 android is back          # ~141 s later, no power cycle
```
Moving the watchdog open **after** `ttyGS0` exists made the arm reliable: the
pinger stopped when userspace blocked, the WDT fired ~120 s later, and Android
returned by itself. The earlier no-reset cases used the old ordering (open
before the tty), which evidently did not arm.

So mode B is a genuine system stall, not a USB-console-only failure.

The timing is the new lead: the gadget is up at 6 s, the first probe at ~11 s
and the next at ~26 s both fail. init starts the WiFi child at ~6 s, which
sleeps 20 s and then loads the modules at ~26 s. Every completed 30-minute run
had `wlan0` absent (the SDIO card did not enumerate); the early stalls line up
with boots where it did. This is exactly the trap recorded in `wifi.md`:
brcmfmac attachment can wedge the machine, and running it in a child protects
the console only when the stall is task-local.

Next control: a no-WiFi auto image with the same watchdog/pinger/heartbeat,
run until it either completes 30 minutes or stalls.

### Build trap: the rebuilt inits never loaded WiFi modules (found 17:33)

The record from the stable run ends its module lines with:
```
n9wifi: /lib/modules/KVER/rfkill.ko rc=fffffffe
... brcmfmac.ko rc=fffffffe                     # -ENOENT, literal "KVER"
```
`init-auto.c` contains `/lib/modules/KVER/...` placeholders; the original
build substituted the kernel release, but the ad-hoc rebuilds in this session
did not. So **every WiFi-enabled image rebuilt today ran without modules** —
`wlan0` was absent for that reason, not SDIO enumeration. The stalls still
happened, so WiFi is not necessary; but the WiFi/SDIO hypothesis has not
actually been tested yet.

Fix for future builds:
```
sed "s|/lib/modules/KVER/|/lib/modules/$(kernelrelease)/|g" init-auto.c
```
(caught by the `/bin/busybox` applet trap too: always check the `rc=` lines in
the record before trusting a WiFi result).

Also: the two "USB dropped after 0 s" fast resets appeared only after the
display-heartbeat build. The heartbeat no longer writes to `/dev/tty0`, only
to `/dev/kmsg`, to rule out the console/DC path.

New images with working module paths: `n9wifi-rec-real-stripped.img`,
`n9wifi-norec-real-stripped.img`. The rec image runs now.

### 30-min soak with working module paths: stable (18:16)

```
17:35:11 gadget after 6s
17:37:11 wlan0 at 75s:  can't find device wlan0   # SDIO card absent this boot
17:42:28 wlan0 at 300s: can't find device wlan0
18:16:52 STABLE for 30 min
18:16:58 stop-ping set
18:19:14 android is back                           # watchdog reset
```
brcmfmac loaded (`rc=00000000`) but the SDIO card did not enumerate, so the
WiFi stack was never exercised; the machine stayed up for 30 minutes. Combined
with the 17:29 stall (modules failed with `-ENOENT`, so no WiFi probe either),
this rules WiFi/SDIO **out as a necessary cause** of the stall.

State at 20:03: battery 46 % and charging slowly on the host's 500 mA port;
still below the 60 % needed for a long run. Hardware tests paused; the tablet
is idle in Android. The prepared next image is `n9wifi-rec-mark-stripped.img`
(record every 2 s for the first minute + `n9st:` stage markers), which will
localise a stall to the exact init step.

### Instrumentation for the early window (18:25)

The stall happens at 6–11 s but the record used to write every 10 s, so an
early stall usually left no record. `monitor()` now writes every **2 s for the
first minute**, then every 10 s. New images:
`n9wifi-rec-early-stripped.img`, `n9wifi-norec-early-stripped.img`.

### Marker soak: 30 min stable, no stall to localise (21:45–22:29)

```
21:45:19 booted, waiting for gadget
21:45:25 gadget after 6s
21:47:05 wlan0 at 60s:   can't find device wlan0    # SDIO card absent
21:52:41 wlan0 at 300s:  can't find device wlan0
22:27:07 STABLE for 30 min: n9wifi-rec-mark
22:29:28 android is back                            # /stop-ping -> WDT reset
```
Started at 73 %, ended 62 %. The image arms the watchdog, pings from
userspace, records every 2 s for the first minute with `n9st:` stage markers,
and writes `n9hb:` heartbeats. No stall occurred, so there is no marker to
read; the run only bounds the rate. Wall time was ~38 min because each 15 s
probe adds ~4 s of Python/serial overhead.

`/stop-ping` → 120 s WDT → Android worked with no power cycle.

### Decision: proceed on features, keep the watchdog workaround (22:30)

The stall is intermittent, mitigated (armed WDT + pinger), and not a
prerequisite for the port. Do not spend more cycles soaking to root-cause it;
carry `RuntimeWatchdogSec=120` into the installed system. Revisit only if the
stall becomes frequent. Scope is display, WiFi, touch, audio, Bluetooth —
camera and sensors are explicitly out for now.

### The stall hit the first audio boot before init's first record write (22:31)

The first boot of `n9audio-bind-stripped.img` was silent (gadget enumerated, no
shell) and **no watchdog reset followed** (~5 min). After the power cycle the
record was unchanged from the 21:45 soak: `flags=2617 s`, 523 `n9hb` lines, all
five `n9st:` markers at 4.0 s (`mounted`, `tty`, `hb forked`, `wd opened`,
`exec sh`). So the audio boot never wrote a record at all — the stall landed
before the monitor's first 2 s emit, i.e. **< ~6 s from kernel start, before
the watchdog open**, which is why nothing reset it. The retry boot was healthy,
so this was the intermittent stall, not the image.

This also gives the first positive marker data: a healthy init completes every
stage within **4.0 s** of kernel start; heartbeats then ran the full 2617 s of
the soak.

### Separate bug: reboot from the test kernel hangs (13:05)

On the minimal-shell image (stable 10 min, shell answering):

```
~ # /bin/busybox reboot -f
~ # echo PING            <- echoed by the tty, NOT executed (no output)
~ # cat /proc/sys/kernel/sysrq; echo b > /proc/sysrq-trigger
                         <- also echoed, no output, no reboot
```
The gadget stays enumerated, so this is not a power loss. After `reboot -f`
the shell stops executing; later input is still echoed by the ttyGS0 line
discipline. `busybox --list` could not be checked because that first command
was the one that hung.

Consequences:
- The harness cannot leave a test image by software; every stalled or
  rebooted test currently needs a physical power cycle. `stability-run.sh`
  now calls `/bin/busybox reboot -f` (instead of bare `reboot`, which is not
  on PATH in the minimal ramdisk), but that path hangs too.
- Investigate `kernel_restart()` on this kernel (PMC reset, driver shutdown,
  DSI/DC stop). This may share a root cause with mode B.

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
1. Move to feature bring-up on the current kernel (fastboot boot, no flash):
   audio (`rt5677` + `tfa989x` + AHUB), then touch, then Bluetooth.
2. Keep the watchdog/pinger + `/stop-ping` harness for every test image.
3. Later, installed boot: pmOS flounder rootfs + this 6.19 kernel,
   `RuntimeWatchdogSec=120`; flashing only with explicit approval.
4. If a stall reappears, the marker image is ready and will localise it.
5. Open driver issue, not blocking install: SDIO enumeration is unreliable;
   keep `N9_REQUIRE_WLAN=1` for WiFi tests.

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

## 2026-10-21 22:40 — ROOT CAUSE CANDIDATE: Palmas VBUS interrupt storm starves the PMIC I2C bus

Found while chasing the `modprobe snd-soc-tfa989x` hang (audio.md). On the
consistent kernel `6.19.0-htc-flounder-gbd93f7930b07` (image `n9dbgA`), with a
serial shell and `/proc/<pid>/stack`:

- `modprobe` blocks (state D) in `tfa989x_i2c_probe -> devm_regulator_get ->
  regulator_dev_lookup` (a mutex), not in the amp itself.
- Other D-state tasks: `mmc_rescan -> mmc_sdio_init_card ->
  mmc_regulator_set_vqmmc` (regulator lock), `regulator_late_cleanup`, and a
  kworker on `i2c_adapter_lock_bus`. The holder is **`irq/72-palmas`**, always
  inside `tegra_i2c_wait_completion` reading Palmas registers.
- `/proc/interrupts` (3 s apart): palmas 190369 -> 193636 (~1000/s), the
  `7000d000.i2c` controller 1.90M -> 1.94M (~10k/s), and every Palmas
  interrupt is `palmas_usb_vbus` (child irq 23, identical counts).
  => the PMIC bus (i2c4) is saturated by a VBUS interrupt storm, so every
  regulator operation (SDIO vqmmc, audio rails, ...) queues behind it.
- This matches mode B (USB enumerated, userspace blocked, no watchdog reset
  because the machine is alive) and the "early stall" of ~1 in 3 boots; the
  gadget's VBUS (host-powered) is the trigger candidate.

Next: read the Palmas INT3 / VBUS state registers while storming; check the
IRQ trigger type (DT says edge; palmas INT is level-low), the local
`palmas-usb` n9 changes, and whether the storm starts at gadget connect.
