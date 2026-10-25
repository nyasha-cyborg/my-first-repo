# LTE regression suspects: stable 3.10.103 -> 3.10.108 (2026-10-26)

## Plain summary

Kernel 3.10.108 boots, the modem starts and talks to the phone software, but it
never joins the LTE network, and the tablet keeps dropping into and out of
sleep (about 19 times a minute). This note looks at the 996 Linux stable fixes
added on top of 3.10.103 and picks out the ones most likely to cause that. None
of them changes the kernel functions the modem driver uses to manage power
(`usb_autopm_*`, `pm_runtime_*`, `wakeup_source_*`). The prime suspects are two
changes to how the USB core reads device descriptors, and one change to USB
port reset. Next step: revert the top suspects one at a time (cheap), or bisect
by tag (104..107).

Static analysis only; nothing tested. Tablet not touched.

## Method

Range: `git log --no-merges lineage-16.0..n9-3.10.108` in `~/n9kernel/kernel`
(no `v3.10.x` tags in this clone; the range is the 996 stable commits), limited
to drivers/usb/{core,host,class,serial,gadget}, drivers/net/usb, kernel/power,
drivers/base, kernel/time, timers, drivers/rtc, net/core, include/linux/{usb*,
pm*,suspend.h}, kernel/irq, workqueue, sched, drivers/misc, drivers/tty.

## Ranked suspects

| # | Commit | Subject | Why it could matter |
|---|--------|---------|---------------------|
| 1 | `15668b4354b` | USB: fix problems with duplicate endpoint addresses | Now *skips* any endpoint whose address repeats inside an altsetting. Qualcomm composite firmware is known for odd descriptors; a dropped endpoint on a QMI/diag/rmnet interface would still enumerate 05c6:9048 but lose a data or notify pipe. Look for `duplicate endpoint with address` in dmesg. |
| 2 | `2226a520b3c` (+ fix `bb9a7c518fd`) | USB: validate wMaxPacketSize entries | Caps/rewrites wMaxPacketSize on HS endpoints. If the MDM reports a non-standard value (e.g. 512 on interrupt, or extra bits), the cap changes what ehci-tegra programs into the QH. Look for `invalid ... maxpacket` warnings. |
| 3 | `48091078f77` | USB: change bInterval default to 10 ms | Default interval for invalid bInterval drops from 32 ms to 8 ms on HS. If the modem's QMI interrupt (notify) endpoint has an out-of-range bInterval, polling is 4x faster: more wakeups, and can keep the HSIC link from autosuspending or interfere with the remote-wakeup handshake. Fits the suspend/resume churn. |
| 4 | `1ea3d6c8d51` | usb: hub: wait for connection after port reset | Changes `hub_port_wait_reset()` result when CONNECTION isn't set right after reset. HSIC on Tegra has no real connect detect; the mdm driver resets/re-enumerates the modem around boot and resume. A long wait or changed error path here alters HSIC re-enumeration timing. |
| 5 | `ae49cb71c5f` / `162f50e6914` | workqueue: WQ_UNBOUND + max_active==1 made ordered | Downstream mdm/HSIC bridge and rmnet code commonly use `alloc_workqueue(..., WQ_UNBOUND, 1)`. They become strictly ordered; a blocking work item (e.g. modem status / wake handling) now stalls the ones queued behind it. Timing-only, but plausible for flapping. |
| 6 | `296a1ab22e2` | rtc: ignore expired timers when enqueuing | Changes when the RTC alarm is armed. Android alarmtimer wake-ups go through this path; can cause immediate wakeups after suspend -> the ~19/min suspend loop. |
| 7 | `de3e6236be5` | timers: proper base migration in add_timer_on() | Timer placement; low probability. |
| 8 | `c73d76df37c`, `6a94ced1bf3` | sched: try_to_wake_up races | Correctness fixes; low probability. |
| 9 | `973d5956f75`, `835b474b8f7`, `04355d6767d`, `14ba02f999d`, `fa69abfe6a0`, `cba3e28f6cf` | ipv6 addrconf DAD/RS reworks | Affects IPv6 on rmnet after attach, not NAS registration. Low for this symptom. |
| 10 | `990d13a5e86`, `5c82a634f9d` | u_ether: remove interrupt throttling; don't starve tx queue | Gadget side; may relate to late adb, not to LTE. |

Others seen and dismissed: cdc-acm (`817a471a34a`, `256d49baf39`,
`f8dc9ab9dcf`, `d4898081cf8` — cdc-acm not used by the MDM path unless a
port binds to it; check `lsusb -t`), usb-serial drivers, xhci, OHCI/UHCI,
net/core sk/gro fixes, `6d97f02a6c0` (test_suspend only), `c11c8fcaa2e`
(PM domains), driver-core glue dir race `e7f6e3c9db4`.

## API dependencies of downstream mdm/HSIC code

- No stable commit in range touches `include/linux/pm*.h`, `include/linux/usb.h`,
  `drivers/base/power/{runtime,wakeup,main}.c`, `drivers/usb/core/driver.c`
  (usb_autopm_*), `drivers/usb/host/ehci*` or `kernel/power/` apart from
  `6d97f02a6c0`. So `usb_autopm_get/put_interface`, `pm_runtime_*`,
  `wakeup_source_*`/`pm_stay_awake` semantics are unchanged.
- Changed USB core files: `drivers/usb/core/config.c` (#1-3) and
  `drivers/usb/core/hub.c` (#4). Both are on the enumeration/reset path the
  HSIC modem uses at boot and after every link reset.
- Shared infrastructure changes: workqueue ordering (#5), rtc interface (#6).

## Suggested next actions

1. From the 3.10.108 boot log (if kept): grep dmesg for `duplicate endpoint`,
   `maxpacket`, `bInterval`, `config .* interface` warnings on 2-1 / usb2.
2. Build 108 with `15668b4354b`, `2226a520b3c`+`bb9a7c518fd`, `48091078f77`
   reverted (all in config.c) -> one boot test. If LTE returns, split them.
3. If not, revert `1ea3d6c8d51` and `ae49cb71c5f`/`162f50e6914`.
4. For the suspend loop: capture `/sys/kernel/debug/wakeup_sources` and
   `/sys/power/pm_wakeup_irq`-equivalent on 108 vs 103.
5. Fall back to tag bisect (104..107 merge commits in kernel-build-log.md).
