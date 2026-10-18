# USB device mode — working state

Last updated: 2026-10-18 · branch `usb-bringup` · commit bc43a4477+dirty (n9trace/n9trigger diags uncommitted)

## Symptom
- Expected: `g_serial` gadget enumerates on host; adb/serial over USB.
- Actual: whole kernel-side sequence succeeds (probe, extcon, g_serial bind,
  device mode set, RS run bit set, PORT_CAP flipped to DEVICE) but the host
  sees NO device on the bus (not even a full-speed chirp). Earlier runs
  sometimes stalled inside `usb_phy_init()` — intermittent, later runs
  completed fully, so that stall may be a red herring (timing-sensitive).
- Host shows: `usb 3-1: USB disconnect` then silence. `lsusb` shows no
  0525/18d1 device during the run.

## Environment
- Tablet flounder_lte, fastboot boot via wrapper-stripped image
  (`tail -c +257`). Host: CachyOS laptop, USB cable sometimes marginal —
  replug fixes hboot wedges. Battery fine (4200mV).
- Test harness: `n9.trigger` cmdline → glue probe deferred; userspace init
  (freestanding aarch64, tools/miniroot/init.c -DTRIGGER) mounts sysfs and
  writes `7d000000.usb` to `.../tegra-usb/bind` from a child; a sibling child
  refreshes the DTB-partition log record every 2 s (survives hangs).
  `n9.reader` cmdline prints PMC scratch breadcrumbs from the previous boot.

## Current hypotheses
| # | Hypothesis | Test | Result | Status |
|---|------------|------|--------|--------|
| 1 | VBUS never reaches controller (Tegra VBUS is in palmas, not OTGSC) | `CI_HDRC_FORCE_VBUS_ACTIVE_ALWAYS` + `CI_HDRC_DUAL_ROLE_NOT_OTG` on tegra124-udc | connect path now runs; vbus connect forced OK | confirmed, fix landed |
| 2 | extcon deferral blocks probe | removed extcon, then re-added; extcon vbus/id now resolve to real edevs | resolved OK | dead |
| 3 | USBMODE write hangs the SoC | step counters around hw_device_reset | all steps complete; usbmode=0x500a (DC), usbcmd RS set | dead (was a timing artifact) |
| 4 | Pad transceiver powered down: padctl port setup FAILED because mode "otg" needs `usb-role-switch` (parse_dt returns -EINVAL without it) | PORT_CAP read 0x0 (DISABLED) at pullup time; my raw poke set it to 0x2 but pads still down | no enumeration | **confirmed — current focus** |
| 5 | phy_init deadlock (PLL_U/regulator) | step prints inside tegra_usb_phy_init | all steps printed in latest run (pll_u→rate→vbus→pad_open→pmc→power_on→done) | dead |

## Evidence (trimmed)
```
$ grep -E 'n9|tegra-usb|ci_hdrc|g_serial' /tmp/n9trigger10.log
12,392,12461638,-;n9trigger: writing0
6,393,12462121,-;tegra-usb 7d000000.usb: n9: step phy
6,394,12462157,-;tegra-usb 7d000000.usb: n9: step clk
6,395,12462185,-;tegra-usb 7d000000.usb: n9: step opp
6,396,12462232,-;tegra-usb 7d000000.usb: n9: step pm
6,397,12462260,-;tegra-usb 7d000000.usb: n9: step reset
6,398,12462291,-;tegra-usb 7d000000.usb: n9: step phy_init
6,399,12462311,-;tegra-phy 7d000000.usb-phy: n9: phy step pll_u
6,400,12462413,-;tegra-phy 7d000000.usb-phy: n9: phy step rate
6,401,12462434,-;tegra-phy 7d000000.usb-phy: n9: phy step vbus
6,402,12462458,-;tegra-phy 7d000000.usb-phy: n9: phy step pad_open
6,403,12462481,-;tegra-phy 7d000000.usb-phy: n9: phy step pmc
6,404,12475383,-;tegra-phy 7d000000.usb-phy: n9: phy step power_on
6,405,12481233,-;tegra-phy 7d000000.usb-phy: n9: phy step done
6,406,12481257,-;tegra-usb 7d000000.usb: n9: step add_device
6,407,12481287,-;tegra-usb 7d000000.usb: n9: extcon vbus = 000000009a57f7fb
6,408,12481312,-;tegra-usb 7d000000.usb: n9: extcon id = 00000000f7937c91
6,409,12481516,-;ci_hdrc ci_hdrc.0: n9: lpm=1 op_off=0x130
6,410,12481866,-;g_serial gadget.0: Gadget Serial v2.4
6,411,12481891,-;g_serial gadget.0: g_serial ready
6,412,12481912,-;ci_hdrc ci_hdrc.0: n9: udc_start vbus_active=0
6,413,12481963,-;ci_hdrc ci_hdrc.0: n9: forcing vbus connect
6,414,12482050,-;ci_hdrc ci_hdrc.0: n9: connected usbmode=0000500a usbcmd=00010000 portsc=00000004
6,415,12482113,-;ci_hdrc ci_hdrc.0: n9: phy susp=000011c0 vbus=00000000 wake=000000c6
6,416,12482143,-;ci_hdrc ci_hdrc.0: n9: portcap 00000000 -> 00000002
6,417,12482168,-;ci_hdrc ci_hdrc.0: n9: pullup on=1 role=1 usbcmd=00010001 usbmode=0000500a
12,418,12482410,-;n9trigger: bind rc=12
12,419,68438481,-;n9trigger: parent awake0
```
Interpretation: SUSP_CTRL=0x11c0 → PHY_ENABLE(bit12) set, UTMIP_RESET(bit11)
clear — UTMI logic good. portcap was **0x0 (DISABLED)** → padctl never set up
the port → pad transceiver power-down bits (OTG_PAD_CTL0/1, BIAS_PAD_CTL0)
never cleared → D+ can't pull up. `usbcmd=0x10001` = RS set, device mode.

## Changes since last test cycle
- `ci_hdrc_tegra.c`: tegra124_udc_soc_info (DUAL_ROLE_NOT_OTG +
  FORCE_VBUS_ACTIVE_ALWAYS), n9trace/n9reader/n9.trigger plumbing, probe step
  prints. `core.c`/`udc.c`/`otg.c`: n9 logs + raw padctl PORT_CAP poke in
  ci_udc_pullup (ioremaps 0x7009f000). `phy-tegra-usb.c`: phy step prints.
- `tegra132-flounder.dts`: usb@7d000000 dr_mode "peripheral" + extcon
  re-added (palmas_usb, extcon_usb_otg). usb2-0 port still mode "otg",
  **no usb-role-switch**.
- init.c: -DTRIGGER build with child-process trigger + 2 s heartbeat record.

## Dead ends — do not retry
- Reading raw PHY/SUSP registers via ioremap before the legacy PHY init runs
  (host-mode paths differ; see notes/display-progress.md for the earlier
  `tegra-usb` probe-hang history).
- Waiting for extcon notifier to drive vbus (is_otg gating); force-connect
  flag is the right mechanism.
- `fastboot boot` retry loops: after several boots the link wedges; replug
  USB or power-cycle instead of more retries.

## Next actions
1. Add `usb-role-switch` (+ default mode device/peripheral) to the usb2-0
   port so `tegra_xusb_usb2_port_parse_dt()` stops failing and the padctl
   sets up the port + role switch. Check whether that alone powers the lane
   (tegra_xusb_set_peripheral → usb_phy_work → lane power_on, PORT_CAP=DEVICE).
   Verify with: padctl probe log ("usb-role-switch not found" gone) and
   PORT_CAP != 0 before pullup.
2. If the role switch needs a setter, drive it from userspace sysfs
   (`/sys/class/usb_role/...`) in the trigger init, then pullup.
3. Remove raw PORT_CAP poke once the padctl owns it.
4. Then: host should see `new full-speed device` → `new high-speed device`
   0525:xxxx (g_serial). Check `journalctl -k` on host.
