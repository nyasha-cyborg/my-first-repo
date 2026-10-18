# Stability (mode-B stall) — working state

Last updated: 2026-10-19 08:30 · branch `nexus9` · tip 9fca799 (+ untracked CLAUDE.md)

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
| 1 | Raw eMMC record write (every 10 s) stalls the machine | `n9console` (record on, WiFi off) vs `n9bare` (both off) | not run | open |
| 2 | brcmfmac/SDIO probe wedges the system at ~23 s | record shows last kmsg at 23.17 s = firmware preinit | see Evidence | investigating |
| 3 | MMC/SDIO runtime PM | `n9auto15pm` (runtime PM off) | not run | open |
| 4 | eMMC writeback after the 32.7 s emit | timing cannot separate from (1) yet | — | open |

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
- **No kernel message after 23.17 s.** brcmfmac never printed its usual post-
  preinit lines (`brcmf_add_if`, `wlan0`, association). The probe was already
  stuck by 23.2 s.
- The machine still ran the monitor at ~32.7 s, so the stall came in
  (32.7 s, 42.7 s) — after the last eMMC write, which is why the eMMC-write
  hypothesis cannot be excluded on timing alone.
- No `hung task`, lockdep or mmc error was recorded before the silence.

Also relevant from this record: `mmc1: Switching to 3.3V signalling voltage
failed` at 1.09 s (also appears on working boots); `mmc1: new UHS-I speed
SDR104 SDIO card` at 1.60 s; both mmc hosts came up.

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
- Read the post-stall record (above); no code or image changes yet.

## Dead ends — do not retry
- Unbind/rebind `sdhci-tegra` to force an SDIO rescan: blocks in-kernel and
  takes the machine down.
- Trusting the record flags word on images built before ee4212a (04:20): it is
  hard-coded 0, so those records cannot prove freshness.

## Next actions
1. Bisect with `tools/stability-run.sh n9console n9bare n9auto15pm n9auto18`
   (decides hypothesis 1 vs 2/3). Watch `/tmp/stability.log`.
2. If `n9console` is stable and `n9bare` stable: daemonize the record only for
   bisection, then narrow brcmfmac (probe with WiFi off vs delayed load).
3. If `n9console` stalls: the raw eMMC write is implicated; replace the
   rolling record with an in-RAM ring plus a single panic-time flush.
