# USB device mode — working state

Last updated: 2026-10-18 21:45 · branch `usb-bringup` · HEAD `ac093f0b7` + uncommitted diag

## Symptom
- Expected: `g_serial` enumerates on the host; adb/serial over USB.
- Actual: every kernel-side step succeeds (probe, extcon state=1, g_serial bind,
  USBMODE=DEVICE, RS run bit set) but the host **never sees a device attach**.
- Not a mainline-only omission we can see: after cloning hboot's exact
  controller + UTMI state (below) the host still sees nothing.

## Ground truth: hboot running fastboot on the same port
Captured at core_initcall with `n9.dump` (video console; record via short init):
```
n9dump: cap=01100030 cmd=00000001 sts=00000080 portsc=00000005
n9dump: devlc=04000000 mode=00005002 susp=000011c0 vbus=00001804 wake=000000c6
n9dump: bias=00280180 xcvr0=06002a3e tx=00090200 misc=03e00078 spare=ffff00f0 xcvr1=00188201
n9dump: pcmux=00000000 pccap=00000000 elpg=07770000 ctl0=003808a0 ctl1=00000004 bias=00003000 vbusid=00000000
n9dump: pmc ao=000ffff3 sleep=c0c0c0c0 master=38000800
```
Interpretation: hboot leaves the padctl at reset defaults (PORT_CAP=0, pad
PD bits set), mux=SNPS, USBMODE=DEVICE with **SLOM clear** (0x5002), DEVLC
PSPD=2 (HS), RS=1. So padctl power pokes are irrelevant; PORT_CAP=0 is normal.

## What our kernel produces at pullup (trigger18, hboot clone)
```
n9: utmi before bias=00280180 xcvr0=06002309 misc=03a00078 xcvr1=00188200
n9: utmi after  bias=00280180 xcvr0=06002a3e misc=03e00078 xcvr1=00188201   <- now == hboot
n9: devlc=06000000 usbmode=00005002                                          <- SLOM cleared, PSPD=3 not 2
n9: pullup on=1 role=1 usbcmd=00010001 usbmode=00005002                      <- RS set
```
Still no attach. Differences left: DEVLC PSPD (3 vs 2, a status field) and the
PHY VBUS sensor (0x0/0x6 vs hboot 0x1804) — see hypothesis table.

## Test harness (works, use it)
- `n9.trigger`: glue probe returns -ENODEV at boot; userspace init mounts sysfs
  and binds `7d000000.usb` from a grandchild while a sibling rewrites the
  DTB-partition record every 2 s.
- `n9.reader`: prints PMC scratch breadcrumbs from the previous boot.
- `n9.dump`: early register dump (USB block + padctl + PMC), safe at core_initcall
  because hboot leaves the blocks clocked.
- Init now **unbinds the USB controller before rebooting** (trigger19) to stop
  the recurring hboot USB wedge.
- Images built with `tools/bootimg-repack.py --append-cmdline ...`, strip the
  HTC wrapper (`tail -c +257`), `fastboot boot`. Boot success ~50%: retry, and
  detect a real kernel start by *no* 18d1:4ee7 appearing within ~40 s.

## Hypotheses
| # | Hypothesis | Test | Result | Status |
|---|------------|------|--------|--------|
| 1 | VBUS not seen by controller | FORCE_VBUS_ACTIVE_ALWAYS + DUAL_ROLE_NOT_OTG | connect path runs | fixed in tree |
| 2 | intermittent `regulator_enable(avdd_usb)` deadlock | removed phy `vbus-supply` | probe now completes every run | fixed in tree |
| 3 | padctl pad powered down | raw PD-bit clears + ELPG | no effect; hboot runs with pad PD set | dead |
| 4 | DEVLC.STS needed (vendor sets it) | set PTS=0+STS=1 | no effect; hboot has STS=0 | dead |
| 5 | vendor termination/preamble missing | FUSE_ATERM_SEL + FS_PREABMLE_J | already set by hboot; no effect | dead |
| 6 | UTMI/controller tuning differs from hboot | cloned xcvr0/misc/xcvr1/USBMODE | still no attach | dead |
| 7 | **PHY VBUS/session comparators not active**: our 0x404 reads 0x0/0x6, hboot 0x1804 | compare PMC ao/sleep/master (dump vs trigger) | **trigger record pending (tablet wedged)** | open |

## Dead ends — do not retry
- Padctl PORT_CAP / pad PD power writes (hboot leaves them set/default).
- DEVLC STS, FUSE_ATERM_SEL, FS_PREABMLE_J.
- Removing extcon; relying on the extcon notifier (is_otg-gated).
- Any conclusion from a single successful-looking boot: the boot fallback to
  Android is frequent; verify with the record length or 18d1 absence.

## Next actions
1. Power cycle, read the trigger-x record, compare `pmc ao/sleep/master` with
   hboot's `000ffff3 / c0c0c0c0 / 38000800`.
2. If PMC differs, replicate hboot's PMC AO/sleep/master setup for port 0
   before pullup.
3. If PMC matches, look at the padctl `vbusid`/OTG comparator path and the
   vendor `tegra-otg.c` role handling next.
4. Long-term: a proper patch should configure whatever hboot does at handoff
   instead of poking registers from ci_udc_pullup.
