# WiFi — working state

Last updated: 2026-10-19 00:05 · branch `usb-bringup`

## Status: fully working

```
wpa_cli status:  ssid=Hotshot-38F0  freq=2437  key_mgmt=WPA2-PSK  wpa_state=COMPLETED
udhcpc:          lease of 192.168.1.102 obtained from 192.168.1.71
ping 8.8.8.8:    2/2, 35-52 ms
wget example.com: 577 bytes, rc=0
```

All of the above now happens **automatically** on boot (`init-auto.c`):
20 s delay -> modules -> wait for wlan0 -> wpa_supplicant -> udhcpc with
`/usr/share/udhcpc/default.script` -> route forced to 192.168.1.1. Verified
from a cold boot with no manual steps: `ip route` shows
`default via 192.168.1.1 dev wlan0` and `ping 8.8.8.8` succeeds.

Two traps found on the way:

1. **The DHCP server is the Pi (`192.168.1.71`) but the router is
   `192.168.1.1`.** The lease hands out `.71` as the gateway; using it gives
   LAN-only connectivity (gateway ping and DNS work, nothing on the WAN).
   Set the default route explicitly to `192.168.1.1`.
2. **udhcpc does not configure the interface**: the ramdisk has no
   `/usr/share/udhcpc/default.script`. Apply the lease by hand or add the
   script.

## Hardware / driver

- Broadcom **BCM4354** on SDIO, `mmc1` (`mmc@700b0000`, `brcm,bcm4354-fmac`
  in the DTS), 1.8V-only, reset on `TEGRA_GPIO(X,7)` via `mmc-pwrseq-simple`
  (`post-power-on-delay-ms = 300`).
- Driver is modular: `brcmfmac` + `brcmutil` + `cfg80211` (+ `rfkill`),
  firmware `brcm/brcmfmac4354-sdio.bin` from linux-firmware (the Cypress
  copy), nvram `brcmfmac4354-sdio.nvidia,p2371-2180.txt` (copied to
  `brcmfmac4354-sdio.txt`; it is not the flounder-specific NVRAM, but the
  chip comes up and associates).
- **Module paths must carry the exact `UTS_RELEASE`**, including `-dirty`.
  A stale hardcoded path makes every `insmod` fail with `-ENOENT` while the
  card is perfectly enumerated; check the `brcmfmac.ko rc=` lines in dmesg.
- **`brcmfmac-wcc.ko` is required.** `brcmfmac` calls `request_module()` for
  it during attach; without it: `brcmf_fwvid_request_module: mod=wcc: failed`
  and `brcmf_attach failed`. It depends on `brcmfmac`, so it must be found by
  modprobe, not loaded by hand first.
- Ramdisk needs `/sbin/modprobe -> /bin/busybox` and a hand-written
  `/lib/modules/<release>/modules.dep` containing `brcmfmac-wcc.ko: brcmfmac.ko`.

## Reliability problem: SDIO enumeration is intermittent

The card comes up on some boots only. When it fails the log shows:

```
mmc1: Switching to 3.3V signalling voltage failed
```

and `/sys/bus/sdio/devices` stays empty, so there is nothing for `brcmfmac`
to bind to. Mainline `sdhci-tegra` **ignores the vendor's `nvidia,only-1-8v`
property**, so the host starts at 3.3V on a 1.8V-only part. When it succeeds
(`ls /sys/class/net` -> `wlan0`, `/sys/bus/sdio/devices` -> `mmc1:0001:1..3`)
everything downstream works.

`sdhci-tegra` now honours the vendor's `nvidia,only-1-8v` by starting such
hosts at 1.8V (this kernel tree). Whether that alone fixed enumeration is
unproven: the card has also come up on boots without it. Do not trust the
"3.3V switch failed" line as the cause either; it appears on working boots.

Do **not** unbind/rebind `sdhci-tegra` to force a rescan: that call blocked
inside the kernel and took the console and the machine down with it.

## The "7-second hang" was our own reset timer

`ci_hdrc_tegra.c` armed a PMC reset 8 s after `core_initcall` to recover
from wedged probes. It checked `system_state >= SYSTEM_RUNNING` only when it
fired, so any boot whose userspace took longer than 8 s to start was reset
mid-boot: the gadget enumerated, vanished ~7 s later and Android came up.
That is the intermittent "hang" seen throughout this session. The timer is
now armed only with `n9.hangreset` on the command line.

A separate, rarer failure remains: sometimes no USB appears at all and the
tablet needs a power cycle.

## Serial console (the reliable workbench)

- udev rule makes `/dev/ttyACM0` 0666 on every enumeration:
  `/etc/udev/rules.d/99-n9-gadget.rules`
- **Set the line first** or every byte arrives as garbage (`sh: /: Permission
  denied` loops): `stty -F /dev/ttyACM0 115200 raw -echo`, then
  `socat - /dev/ttyACM0,ispeed=115200,ospeed=115200,raw,echo=0,crnl`.
- busybox applets are not installed in the ramdisk by default; run
  `/bin/busybox --install -s /bin` once per boot.
- No DHCP script in the ramdisk, so a lease is obtained but not applied:
  `ip addr add 192.168.1.102/24 dev wlan0; ip route add default via 192.168.1.71`

## Harness

- `tools/miniroot/init-auto.c`: loads the modules, waits 20 s for `wlan0`,
  starts `wpa_supplicant`, runs `udhcpc`, then leaves a shell on `ttyGS0`.
- `tools/watch-n9.sh`: logs USB state transitions (fastboot / android /
  gadget / none) with timestamps to `/tmp/n9-watch.log`.
- The wpa_supplicant config is built into the test ramdisk only. It holds the
  SSID and a PSK derived from the user's passphrase, is never committed and
  never written to the notes.

## Next actions

1. Add `/usr/share/udhcpc/default.script` and set the right gateway so the
   automatic path reaches the internet without hand-holding.
2. Real MAC address: the chip reports `00:90:4c:16:70:01`, which is not the
   board MAC. The NVRAM in use is the NVIDIA p2371 one, not flounder's.
3. Then touch, audio, and the installed-boot path.
