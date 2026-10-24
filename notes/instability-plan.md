# Nexus 9 pmOS instability-reduction plan

Scope: hard hangs of the installed pmOS (loop-mounted rootfs in `/data/pmos/rootfs.img`)
under non-VDE workloads, especially a 6 MB `scp` over WiFi into `/tmp`.
Host-only analysis; no tablet access was used. Date 2026-10-24.

Sources read: `notes/stability-debug.md` (all entries), `notes/handoff.md`,
`notes/wifi.md`, `notes/usb-debug.md`, `notes/pmos.md` (rootfs/loop layout),
`notes/gpu.md` (EMC/thermal), `notes/lte.md` (large-push history),
`tools/pmos/*`, `tools/miniroot/*`, `tools/n9sh.py`, `tools/n9push.py`,
`tools/stability-run.sh`, kernel DTS/defconfig in `~/code/linux-flounder`.

---

## 0. Verified facts that constrain the diagnosis

1. **`/tmp` is on the loop-mounted rootfs, not tmpfs.** Host-side verification:
   `postmarketos-base-62-r0` (fetched from the v26.06 mirror) ships no fstab/tmpfs
   unit; Alpine 3.24 `alpine-baselayout-3.7.2-r1` has no `/etc/fstab`, so OpenRC's
   `bootmisc` only creates `/tmp` (mode 1777). `tools/pmos/init` does not mount
   tmpfs on `/tmp`. Therefore every byte of the 6 MB write goes:
   rootfs ext4 page cache -> loop worker -> `/data` ext4 page cache -> eMMC (mmc0).
   Verify on device: `findmnt -T /tmp -o FSTYPE,SOURCE,TARGET` (expect ext4/loop0;
   if it says tmpfs, the reproducer assumption is wrong and the plan changes).
2. **The logger writes to the same loop rootfs and calls global `sync` every 5 s.**
   `tools/pmos/n9-kmsg.initd`: `cat /proc/kmsg >> /var/log/kmsg.log & while true; do sync; sleep 5; done`.
   `/var/log` is on the loop image. This is a permanent 5-second global writeback
   trigger and a confounder in every pmOS hang so far.
3. **Both mmc hosts use Palmas SMPS8 as vqmmc.**
   `tegra132-flounder.dts`: `mmc@700b0000` (WiFi) and `mmc@700b0600` (eMMC) both have
   `vqmmc-supply = <&vdd_1v8>` = Palmas `smps8`, i2c-4 address 0x58/0x59.
4. **A real D-state lock chain through the PMIC was captured**
   (`stability-debug.md` 2026-10-21 22:40): holder `irq/72-palmas` inside
   `tegra_i2c_wait_completion`; waiters `mmc_rescan -> mmc_sdio_init_card ->
   mmc_regulator_set_vqmmc`, `regulator_late_cleanup`, and an i2c kworker; palmas
   ~1000 irq/s and i2c ~10k/s, all `palmas_usb_vbus`.
5. **That storm was fixed by removing `nvidia,invert-interrupt`** (`n9dbgD`,
   palmas/i2c counters frozen, tfa989x probes OK), **but PMIC interrupt delivery is
   still unverified**: RTC alarm never advanced the palmas irq, VBUS plug only
   counted once, and one boot had 52 `dummy 4-0059: Failed to read IRQ status: -121`
   lines (`stability-debug.md` 2026-10-22 17:50; 2026-10-21 23:55).
6. **A reproducible PMIC wedge remains: display power-down.** Every DPMS off gives
   +20..41 `-121` lines; DPMS on gives 0; a session died at 700 s right after such a
   burst. `panel_jdi_lpm089a128a.keep_power=1` gives 0/3 errors (still in the pmOS
   cmdline). simplefb also leaks the panel rails (`pmos.md` 17:40/18:00/18:30).
7. **The watchdog can be fed through a dead system.** busybox watchdog kept feeding
   in mode B for >10 min (needs power cycle); that is why `n9-health` was added.
   But `n9-health.sh` only tests a local sshd banner and `/bin/true`: both can pass
   while the block layer is wedged (page-cache exec, listen backlog). This is why
   hangs need a power cycle instead of self-recovering.
8. **eMMC writes per se are not proven fatal.** The record-write theory was killed
   by paired 30-min runs; no mmc/sdhci error appears in any captured log.
   The "44 MB push hangs at ~30 MB" (`lte.md` 09:10) was over the **USB-serial
   console**, not WiFi/eMMC, and 8 MB parts worked.
9. **Other causes already fixed / excluded:** EMC DVFS memory corruption
   (fixed by `initcall_blacklist=tegra_devfreq_driver_init`, 8/8 clean boots, in the
   pmOS cmdline); thermal power-cut (series 0039, `nvidia,gpu-throt-level`);
   low battery (only explains some 2026-10-19 runs); memory exhaustion
   (1 GB available measured at the 122 s PMIC hit). Verify all three in preflight.

---

## 1. Most likely mechanisms for a hang during 6 MB over WiFi into the loop rootfs

The write path is: brcmfmac/SDIO (mmc1) -> TCP -> ext4 page cache (loop rootfs)
-> loop kworker -> ext4 on /data (eMMC, mmc0). The control/console path is
independent (USB gadget). A hang in any single link can produce "ssh and adb
gone, no fastboot"; a *global* hang needs a shared lock/IRQ or a stalled
userspace. Ranked:

| # | Mechanism | Confidence | Evidence for | Evidence against / gaps |
|---|-----------|-----------|--------------|--------------------------|
| M1 | **Palmas PMIC I2C/IRQ stall or NAK loop blocks regulator users (both mmc hosts) and/or starves CPU** | **Medium (~50%)** | Captured D-state chain through `irq/72-palmas` + `mmc_regulator_set_vqmmc`; both mmc vqmmc on Palmas; reproducible `-121` bursts at display blank; WiFi "died first" in two session hangs | The per-second VBUS storm is fixed; residual `-121` bursts at boot/blank were survived. No log yet from a WiFi-transfer hang (kmsg lives on the same loop). |
| M2 | **mmc/SDIO runtime PM (brcmfmac autosuspend, sdhci runtime resume) during traffic** | **Medium-low (~35%)** | Never tested: `n9auto15pm` image not run; HANDOFF lists SDIO/MMC runtime PM as a top suspect; runtime resume triggers ios/vqmmc -> Palmas path of M1 | No direct measurement of `power/runtime_status` during a transfer in any note. |
| M3 | **Loop + ext4 writeback burst / double caching / fragmented 12 GiB sparse image** | **Low-medium (~30%)** | The 5 s global `sync`; sparse non-preallocated image; 6 MB dirties both ext4 layers and journal; low writeback ratios delay the flush to a late burst | No mmc/loop error in any log; record writes and 30-min soaks did not correlate; the 44 MB hang was a different transport. |
| M4 | **SDIO/brcmfmac data-path wedge (sg/block size, BCM4354 firmware)** | **Low-medium (~25%)** | Historical SDIO enumeration flakiness (mitigated by pwrseq ext_clock/only-1-8v, not proven over many boots); brcmfmac attach has wedged the machine; WiFi died first in session hangs | No SDIO data-path errors logged; stable-debug 18:16 boot had brcmfmac loaded with no card and stayed up (proves absence, not presence, of a data-path fault). |
| M5 | **Remaining Palmas VBUS/IRQ storm** | **Low (<10%)** | Storm history | The 1000/s storm is gone after the polarity fix; residual bursts are short. |
| M6 | **eMMC/controller hardware or HS200 retuning failure** | **Low (<15%)** | eMMC write is on the path | `mmc0: new HS200`, all 33 partitions, no timeouts in logs. |
| M7 | **Why it does not self-recover (not the cause of the stall): watchdog monitor blind spot** | **High (~85%)** | busybox fed through mode B; `n9-health` checks only sshd banner + `/bin/true`; 12:25 boot had no watchdog fed at all | — |

Practical reading: M1 and M2 share the Palmas/regulator path and are the most
actionable; M3 is cheap to rule out with tmpfs + writeback tuning; M4 is ruled
out/in by separating WiFi from storage in the experiment. M7 must be fixed in
parallel or every experiment ends in a power cycle.

---

## 2. Low-risk mitigations (no kernel rebuild)

Priority order. Each has an explicit verification.

### T1. Stop the diagnostics from writing to the loop rootfs (highest value, lowest risk)
- Change `n9-kmsg` to write **directly to `/android-data/pmos/kmsg.log`** (the
  eMMC ext4 mount of `/data`, bypassing the loop device) and replace the
  unconditional global `sync` with a per-file flush or a 30 s interval:
  ```sh
  # /etc/init.d/n9-kmsg (edit tools/pmos/n9-kmsg.initd, ship in overlay)
  cat /proc/kmsg >> /android-data/pmos/kmsg.log &
  while true; do sync -f /android-data/pmos/kmsg.log 2>/dev/null || sync; sleep 30; done
  ```
  (busybox `sync` may lack `-f`; keep the 30 s fallback. The point is to stop
  forcing a global writeback every 5 s through loop+ext4.)
- Keep `/var/log/kmsg.log` only as a boot-time convenience if desired, but never
  as the evidence store.
- Verify: `grep -c . /android-data/pmos/kmsg.log`, `findmnt -T /android-data`,
  and confirm the 5 s `sync` is gone from `ps`.
- Why: removes the logger as a confounder and makes evidence survive a loop/eMMC
  hang. If the hang is eMMC itself, also add a UDP/serial copy (T6).

### T2. Put `/tmp` (or at least `/tmp/video`) on tmpfs
- `/etc/fstab`: `tmpfs /tmp tmpfs size=512m,mode=1777 0 0`
  (or a local.d one-shot: `mountpoint -q /tmp || mount -t tmpfs -o size=512m,mode=1777 tmpfs /tmp`).
  Add to the image in `finish-rootfs.sh`, not by hand, so it survives rebuilds.
- Also provide `/tmp/video` and require test clips there.
- Verify: `findmnt -no FSTYPE,SOURCE -T /tmp` -> `tmpfs tmpfs`;
  `grep -E 'Dirty|Writeback' /proc/meminfo` stays near zero during a 6 MB scp;
  repeat the reproducer 5x.
- Effect: removes M3 from every clip transfer. If the hang persists, storage/
  loop is exonerated and attention goes to M1/M2/M4.

### T3. Transfer in <=4 MiB parts, checksummed, and never join on the tablet
- Use `tools/pmos/push-small.sh` (added with this plan). It splits, verifies
  sha256 per part, warns when the destination is not tmpfs, and flushes per file
  instead of a global sync.
- Push parts into `/tmp/video` (tmpfs, T2). Only join on the tablet if the final
  file must live on the rootfs; otherwise consume the parts directly.
- Verify: sha256 match printed per part; no part larger than 4 MiB; no global
  `sync` invoked.

### T4. Disable WiFi power save and SDIO/mmc runtime PM for the test cycle
- In a `local.d` service / manual step:
  ```sh
  iw dev wlan0 set power_save off
  nmcli connection modify wifi-home 802-11-wireless.powersave 2 2>/dev/null || true
  for d in /sys/bus/sdio/devices/*; do [ -w "$d/power/control" ] && echo on > "$d/power/control"; done
  for h in /sys/class/mmc_host/mmc0 /sys/class/mmc_host/mmc1; do
      [ -w "$h/power/control" ] && echo on > "$h/power/control"
  done
  ```
- This is hypothesis 3 from `stability-debug.md`, never actually run. Do it as a
  one-variable test (T4 alone) before combining.
- Verify: `iw dev wlan0 get power_save` -> `off`; `cat .../power/runtime_status`
  -> `active` after 60 s idle; the transfer run.
- If this alone removes the hang, the kernel fix is "do not runtime-suspend this
  SDIO host" (see K6), not a userspace workaround.

### T5. Keep the display from blanking during transfers and soaks
- `gsettings set org.gnome.desktop.session idle-delay 0` for the session, or set
  a dconf system default in `finish-rootfs.sh`; `panel_jdi_lpm089a128a.keep_power=1`
  is already on the pmOS cmdline.
- Verify after a forced 30 s idle: no new `dummy 4-0059: Failed to read IRQ
  status: -121` in kmsg (`grep -c '4-0059'` before/after DPMS off/on).
- This removes the only *reproduced* PMIC wedge from the soak. It is a workaround,
  not a root fix; K3 addresses the cause.

### T6. Out-of-band console and evidence capture
- Do control and logging over the **USB serial gadget** (`tools/n9sh.py`), not
  SSH, and let the host journal capture it. Optionally boot a debug image with
  `console=tty0 console=ttyGS0` so kernel messages stream to the host (no disk
  writes at all). Netconsole is not built (`CONFIG_NETCONSOLE` is off).
- Persist `/proc/interrupts`, D-state stacks, `Dirty/Writeback`, mmc/loop stats to
  `/android-data/pmos/diag.log` (T1 path) every 5 s from a small on-device script.
- Verify: unplug WiFi (or stop NetworkManager) and confirm the host still gets
  shell/diag.
- **USB transport instead of WiFi for moving data.** The proven low-risk route is
  the existing serial gadget with `tools/n9push.py` (16 KiB blocks, ACK, checksum;
  2-4 MiB parts worked in `lte.md`). A faster route is a USB Ethernet gadget:
  `CONFIG_USB_CONFIGFS_ECM=y` (built-in) plus `CONFIG_USB_F_ECM=m`
  (in the module overlay) / RNDIS are configured, so configfs can expose
  `usb0` and a 6 MB transfer never touches SDIO. Caveat: the UDC is currently
  bound by the built-in `g_serial`; switching to a configfs composite unbinds it,
  which removes the serial console. Only attempt after an alternative console
  (e.g. `console=ttyGS0` in a configfs composite with both ACM and ECM) is
  prepared and tested. Use USB serial now; USB Ethernet is medium effort.

### T7. Writeback smoothing (sysctl) and loop mount options
- `/etc/sysctl.d/80-n9-storage.conf`:
  ```
  vm.dirty_background_bytes = 4194304
  vm.dirty_bytes = 33554432
  vm.dirty_expire_centisecs = 500
  vm.dirty_writeback_centisecs = 200
  ```
- `tools/pmos/init`: mount the loop rootfs with `noatime,commit=30`
  (currently `noatime`; default journal commit is 5 s). Keep `data=ordered`.
- Optional test only: `losetup --direct-io=on` (bypasses the double page cache;
  ext4 must support direct I/O for the backing file) and/or `fallocate` the
  12 GiB image once to remove sparse-file fragmentation.
- Verify: during a 4 MiB part push, `Writeback` peaks lower and no single burst
  exceeds ~4 MiB; no I/O errors; boot still works.
- Risk: `commit=30` widens the post-crash window (fsck already runs at boot);
  direct-io/fallocate are experiments and should be one at a time.

### T8. Fix the watchdog monitor so a hang self-recovers
- Replace/augment `n9-health.sh` checks: sshd banner + fork/exec **plus**
  (a) count D-state tasks (`/proc/[0-9]*/stat` state D) and refuse to pet if it
  grows across two checks; (b) a 5 s fsync probe on the loop rootfs
  (`/var/tmp/.n9hb`) and on `/android-data/pmos/.n9hb` executed by a timed
  grandchild; (c) `Writeback` stuck > 0 for 3 checks. Three strikes -> stop
  petting -> tegra_wdt reset.
- For diagnosis runs only, set the early heartbeat back to 180 s
  (`tegra_wdt.heartbeat=180`, already in the cmdline) so a hang can be observed
  for a few minutes before reset. For daily use keep 60 s plus the stronger
  checks.
- Verify: deliberately `echo c > /proc/sysrq-trigger`? No — instead `kill -STOP`
  the test workload's parent or `echo 1 > /sys/block/loop0/device/delete` is too
  destructive. Use a controlled `dd` against a file on a scsi_debug? Simplest
  positive control: `mount -o remount,ro /` then the fsync probe must fail and
  the WDT must reset within ~90 s.
- Note `CONFIG_WATCHDOG_SYSFS` is not set, so the state/timeleft cannot be read;
  enabling it in K1 helps confirm arm/feed behaviour.

---

## 3. Kernel / driver fixes worth testing (ranked, one per boot)

K1. **Diagnostics first (no behavioural change).**
    `CONFIG_DETECT_HUNG_TASK=y`, `CONFIG_DEFAULT_HUNG_TASK_TIMEOUT=15`,
    `CONFIG_WATCHDOG_SYSFS=y`, optionally `CONFIG_SOFTLOCKUP_DETECTOR=y`;
    boot param `hung_task_timeout_secs=15 hung_task_warnings=10`.
    This turns every future hang into a persistent stack trace of the blocker.
    Verify: `cat /sys/class/watchdog/watchdog0/timeleft`, and a synthetic
    `dd` to a stopped device shows a hung-task splat.
    (Current config has all of these off — checked in `linux-flounder-out/.config`.)

K2. **PMIC interrupt handling / delivery.**
    Current state is config B: DTS `interrupts = <GIC_SPI 86 IRQ_TYPE_NONE>` and
    no `nvidia,invert-interrupt` in `pmc@7000e400`. Measured vendor is the same
    (PMC_CNTRL polarity 0, PMIC POLARITY_CTRL 0). Next untested combination from
    the notes: `IRQ_TYPE_LEVEL_HIGH` **without** invert (the earlier failure was
    LEVEL_HIGH **with** invert). Also instrument `palmas_irq_thread` /
    `tegra_i2c_wait_completion` to rate-limit and timestamp `-121` sequences, and
    verify the PMIC RTC alarm and cable plug/unplug actually move the parent IRQ
    and the correct child IRQ. If delivery stays broken, either keep edge+NONE
    and poll VBUS, or fix the PMC/PMIC polarity pair properly.
    Do this on a `fastboot boot` image with the watchdog armed; n9dbgC hung, so
    keep the USB serial/console recovery ready.

K3. **Panel/simplefb rail ownership.**
    Documented next action (`pmos.md` 18:30): remove `dsi-supply`, `lcd-supply`,
    `io-supply` from the `simple-framebuffer` node so the panel driver owns the
    rails, then retest DPMS off with `keep_power=0`. The goal is that no rail
    switch at blank produces the `-121` burst. Medium risk (display); keep
    `keep_power=1` as the fallback. Verify with the DPMS loop (5x off/on,
    `grep -c 4-0059`).

K4. **SDIO/brcmfmac.**
    First add instrumentation (the note's ask): log the return value of the 1.8 V
    switch and the time between pwrseq release and first CMD5/CMD0. If T4 (runtime
    PM off) helps, implement the equivalent in the driver: force the mmc1/SDIO
    host to stay powered (or add a DT quirk for this non-removable SDIO host).
    If T4 does not help but T1/T2 do, do not touch SDIO. Only if the experiment
    points at the data path, test dropping `sd-uhs-sdr104` (SDR50) or a
    `max-frequency` clamp as a signal-integrity experiment. Never unbind/rebind
    `sdhci-tegra` (documented dead end).

K5. **Loop/ext4.**
    Mount options from T7; then `LO_FLAGS_DIRECT_IO` and preallocation
    (`fallocate`) as separate tests. Verify with 64 MiB local writes with
    `conv=fsync` to `/var/tmp` (loop) and `/android-data/pmos` (direct eMMC).
    If the loop layer alone reproduces a hang, the long-term fix is to stop
    using a file-on-ext4 as the root device (real partition or direct-io loop).

K6. **mmc runtime PM.**
    Only if T4 implicates it. Candidate: keep mmc0/mmc1 runtime-powered
    (`pm_runtime_forbid` for these hosts, or a DT property) and measure idle
    power. This is a workaround until the Palmas-vqmmc interaction is understood.

K7. **EMC/thermal verification (no code change expected).**
    Confirm in every boot: `cat /proc/cmdline | grep tegra_devfreq_driver_init`,
    `/sys/class/devfreq` empty (or tegra devfreq absent), dmesg has no
    `throttle-cfg` rejection / `thermtrip`. If the blacklist is missing from the
    actual booted image, EMC memory corruption (gpu.md 22:55) is back on the table
    and explains arbitrary hangs.

---

## 4. Minimal reproduction / soak experiment

Goal: decide between M1/M2 (PMIC/regulator/runtime-PM), M3 (loop/eMMC), and M4
(WiFi data path) with the fewest boots. Control over USB serial, data over WiFi,
evidence on `/android-data` (direct eMMC).

### Preflight (one boot, 5 min)
```
uname -a; cat /proc/cmdline
findmnt -T /tmp -o FSTYPE,SOURCE,TARGET
findmnt -T /var/log -o FSTYPE,SOURCE
mount | grep -E ' / | /android-data | loop'
ls /sys/bus/sdio/devices; iw dev wlan0 get power_save
for h in /sys/class/mmc_host/mmc*; do echo "$h $(cat $h/power/runtime_status) $(cat $h/power/control)"; done
dmesg | grep -iE 'mmc|sdhci|brcmf|palmas|4-0059|emc|devfreq|throttle|thermtrip'
cat /proc/interrupts | grep -E 'palmas|7000d000.i2c|mmc'
```
Record battery >60% (charger connected), otherwise the 2026-10-19 confound is back.

### Diag logger (start before each cell, stop after)
Every 5 s append to `/android-data/pmos/diag.log`:
- `uptime`, `loadavg`;
- `/proc/interrupts` rows for palmas (LIC 86), `7000d000.i2c`, `mmc0`, `mmc1`,
  `irq/72-palmas`, `palmas_usb_vbus`;
- `/proc/meminfo` `MemAvailable Dirty Writeback`;
- D-state tasks + `/proc/<pid>/stack` for each (root);
- `/sys/block/mmcblk0/stat`, `/sys/block/loop0/stat`, `inflight`;
- thermal zones, CPU freq;
- `cat /sys/class/net/wlan0/statistics/{rx,tx}_bytes` (WiFi progress);
- watchdog `timeleft` if K1 is applied.
Also print a one-line heartbeat to `/dev/kmsg`.

### Matrix (randomize order, n=5 per cell, 10 min cap per run)
| Cell | Transport | Destination | What it isolates |
|------|-----------|-------------|------------------|
| A | WiFi scp of 6 MB | `/tmp` (loop) | the reported reproducer |
| B | WiFi scp of 6 MB | `/tmp/video` (tmpfs) | storage/loop vs WiFi |
| C | USB serial `n9push.py`, 2 MB parts | `/tmp` (loop) | USB vs WiFi, same storage |
| D | USB serial `n9push.py`, 2 MB parts | tmpfs | transport + storage both changed |
| E | local `dd` 64 MiB `conv=fsync` | `/var/tmp` (loop) | loop+eMMC only, no network |
| F | local `dd` 64 MiB `conv=fsync` | `/android-data/pmos/tmpfile` | direct eMMC only |
| G | idle 15 min, display forced off (DPMS) | — | PMIC wedge control |
| H | idle 15 min, display on | — | baseline |

Repeat A after each Tier-1 change (T1, T2, T4 separately), n=5.

### Decision rules
- A fails, B/D stable -> storage/loop (M3) or loop<->eMMC path; go T2/T7/K5.
- A and B fail, C/D stable -> WiFi/SDIO (M4/M2); go T4/K4.
- E fails, F stable -> loop+eMMC (M3); go K5.
- E and F fail -> eMMC/mmc (M6) or PMIC regulator path (M1); check D-state stacks
  for `mmc*`/`palmas`; go K1/K2.
- Only G fails -> PMIC/display (M1) confirmed; K3 + keep T5.
- Everything stable after T1/T2/T4 -> re-run A 20x as a soak; keep the changes.

### Evidence to capture on every hang
1. Do **not** power-cycle immediately: wait 5 min (watchdog 180 s early + 60 s
   health) and record whether it resets by itself. If not, that is M7 evidence.
2. Host: timestamp logs, `lsusb`, ICMP/ssh results, serial output (T6).
3. After reset/Android: `adb root`, then pull
   `/data/pmos/kmsg.log` (T1 path), `/data/pmos/diag.log`,
   `/data/pmos/boot-init.log`, `/data/pmos/fsck.log`;
   `adb shell getprop ro.boot.bootreason`; check `/proc/last_kmsg` and pstore
   (no pstore today).
4. On the device before reset (if serial still answers):
   `echo t > /proc/sysrq-trigger` (D-state stacks to kmsg), `cat /proc/interrupts`,
   `cat /proc/meminfo`, `dmesg | tail`.
5. Note the exact last `diag.log` line and whether WiFi counters kept moving.

### Success criteria
- The 6 MB reproducer no longer hangs in 20/20 runs after the changes, with
  serial console and sshd both alive.
- If a hang still occurs, `diag.log` names the subsystem (palmas/i2c counters
  storming vs mmc inflight stuck vs WiFi counters frozen) and the D-state stack
  names the function.

---

## 5. Ranked "do first" list (summary)

1. **T1 + T2** (logger off the loop; `/tmp` on tmpfs; 4 MiB parts): cheapest,
   removes the main confounder and the storage half of the write path.
2. **T8 + K1** (real health checks + hung-task detector + watchdog sysfs): makes
   every subsequent failure self-recover with a stack trace instead of needing a
   power cycle.
3. **T4** (WiFi power save + SDIO/mmc runtime PM off) as a one-variable boot:
   tests the never-run runtime-PM hypothesis directly.
4. **T5 + K3** (keep display awake now; fix panel rail ownership next): removes
   the only reproducible PMIC wedge.
5. **K2** (PMIC interrupt delivery) and **K5** (loop mount/direct-io) only after
   the matrix points at them.

Do not retry: `sdhci-tegra` unbind/rebind; record-write correlation; LEVEL_HIGH
*with* invert; guessing EMC tables.
