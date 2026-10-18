# USB device mode — working state

Last updated: 2026-10-18 18:34 · branch `usb-bringup` · HEAD `24f3878ae` + uncommitted diag

## Symptom
- Expected: `g_serial` enumerates on the host; adb/serial over USB.
- Actual: full kernel-side sequence succeeds — probe, extcon (state=1), g_serial
  bind, USBMODE=DEVICE (0x500a), RS run bit set — but the host sees **no device
  attach at all** (no full-speed chirp).
- The one stall seen inside `usb_phy_init()` earlier was intermittent/timing;
  latest runs print every PHY step and complete.

## Test harness (works, use it)
- `n9.trigger` cmdline: glue probe returns -ENODEV at boot; userspace init
  (tools/miniroot/init.c, `-DTRIGGER`) mounts sysfs and binds
  `7d000000.usb` from a child, while a sibling child rewrites the DTB-partition
  log record every 2 s (so blocked probes are still diagnosable).
- `n9.reader` cmdline prints PMC scratch breadcrumbs from the previous boot.
- Images: repack with `--append-cmdline "console=tty0 n9.trigger"`, strip the
  256-byte HTC wrapper, `fastboot boot`.
- **fastboot boot is flaky**: it often "succeeds" but boots Android instead.
  Retry; after several attempts the USB link wedges and the tablet needs a
  power cycle (unplug/replug does not clear it).

## Current hypotheses
| # | Hypothesis | Test | Result | Status |
|---|------------|------|--------|--------|
| 1 | VBUS never reaches controller (Tegra VBUS in palmas, not OTGSC) | FORCE_VBUS_ACTIVE_ALWAYS + DUAL_ROLE_NOT_OTG | connect path runs | confirmed, in tree |
| 2 | pad transceiver powered down (padctl PD bits) | raw-clear bias/ctl0/ctl1 PD bits, PORT_CAP=DEVICE | regs changed as intended; still no attach | investigated, insufficient |
| 3 | PHY cannot see VBUS: UTMI `USB_PHY_VBUS_SENSORS` (0x404) reads 0 while palmas extcon state=1 | read 0x404 before/after pad power | stays 0x0 | open — may be normal/bypass |
| 4 | **DEVLC.STS is skipped by mainline.** Vendor PHY (`tegra3_usb_phy.c` in LineageOS flounder kernel) clears PTS and **sets DEVLC.STS (bit 28)** on every open; mainline skips `hw_phymode_configure()` because Tegra sets `CI_HDRC_OVERRIDE_PHY_CONTROL` | add PTS=0 + STS=1 before RS in `ci_udc_pullup` | **trigger13 built, not yet run** | **current focus** |

## Evidence (trimmed) — trigger11/12 record
```
n9: extcon vbus state=1
n9: connected usbmode=0000500a usbcmd=00010000 portsc=00000004
n9: phy susp=000011c0 vbus=00000000 wake=000000c6     <- PHY enabled, clk valid, no VBUS sense
n9: padctl cap=00000000 bias=00003000 ctl0=003808a0 ctl1=00000004
n9: padctl2 cap=00000002 bias=00002000 ctl0=000008a0 ctl1=00000000
n9: phy2 susp=000011c0 vbus=00000000 wake=000000c6
n9: pullup on=1 role=1 usbcmd=00010001 usbmode=0000500a   <- RS set, still nothing on host
```
Vendor source for hypothesis 4 (LineageOS `android_kernel_htc_flounder`, cm-14.1,
`drivers/usb/phy/tegra3_usb_phy.c`):
```
val &= ~USB_USBMODE_MASK; ... val |= USB_USBMODE_DEVICE;
val = readl(base + HOSTPC1_DEVLC);
val &= ~HOSTPC1_DEVLC_PTS(~0);
val |= HOSTPC1_DEVLC_STS;
writel(val, base + HOSTPC1_DEVLC);
```
The same file also clears `COMB_TERMS | ALWAYS_FREE_RUNNING_TERMS` when leaving
host mode, and does a one-time PMC bias/trk init — check those next if STS fails.

## Changes since last commit
- `udc.c::ci_udc_pullup`: raw padctl power (bias 0xb8 PD, ctl0 0xa0 PD/PD2/PD_ZI,
  ctl1 0xac PD_DR/CHRP/DISC, PORT_CAP=DEVICE), PHY 0x404 dump, DEVLC PTS→UTMI
  + STS set.
- `xusb.c`: lane-program and "padctl ports up" logs.
- `phy-tegra-usb.c`: step logs through `tegra_usb_phy_init`.
- `core.c`: extcon state log.

## Dead ends — do not retry
- Removing extcon: probe stops deferring but VBUS never connects.
- Waiting for the extcon notifier to drive vbus: gated by `is_otg`/OTGSC;
  force-flag is the working mechanism.
- Assuming the earlier `usb_phy_init` stall was deterministic — it is not.
- `fastboot boot` retry loops after a wedge: needs a power cycle.

## Next actions (when hardware is back)
1. Power cycle → `adb reboot bootloader` → `fastboot boot /tmp/n9trigger13.img`
   (retry until the kernel starts; watch for `USB disconnect` then no 18d1).
2. Read the record via Android (`adb root`, dd mmcblk0p5) — check `devlc before/after`
   and whether the host enumerated.
3. If STS does not fix it: try setting `COMB_TERMS | ALWAYS_FREE_RUNNING_TERMS`
   in UTMIP_MISC_CFG0 (0x824) after clearing them, and/or drive the padctl
   role switch (`/sys/class/usb_role/*/role=device`) before pullup.
4. Identify the shipped kernel's devlc value via REA if still stuck.
