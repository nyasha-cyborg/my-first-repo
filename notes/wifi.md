# WiFi — working state

Last updated: 2026-10-18 23:35 · branch `usb-bringup`

## Status: working (association + DHCP + DNS proven)

```
wpa_cli status:  ssid=Hotshot-38F0  freq=2437  key_mgmt=WPA2-PSK  wpa_state=COMPLETED
udhcpc:          lease of 192.168.1.102 obtained from 192.168.1.71
ping gateway:    2/2, 25-41 ms
nslookup:        example.com resolves via the router
```

Not confirmed: outbound HTTP/TCP from the tablet. `ping 1.1.1.1` and a
`wget http://example.com` both stalled (the ping is 100% loss, the wget hung
and had to be abandoned). DNS works, so UDP to the gateway is fine. Treat
"internet reachable" as unproven; the driver and association are not in doubt.

## Hardware / driver

- Broadcom **BCM4354** on SDIO, `mmc1` (`mmc@700b0000`, `brcm,bcm4354-fmac`
  in the DTS), 1.8V-only, reset on `TEGRA_GPIO(X,7)` via `mmc-pwrseq-simple`
  (`post-power-on-delay-ms = 300`).
- Driver is modular: `brcmfmac` + `brcmutil` + `cfg80211` (+ `rfkill`),
  firmware `brcm/brcmfmac4354-sdio.bin` from linux-firmware (the Cypress
  copy), nvram `brcmfmac4354-sdio.nvidia,p2371-2180.txt` (copied to
  `brcmfmac4354-sdio.txt`; it is not the flounder-specific NVRAM, but the
  chip comes up and associates).
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

Do **not** unbind/rebind `sdhci-tegra` to force a rescan: that call blocked
inside the kernel and took the console and the machine down with it.

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

1. Make the card enumerate reliably: teach `sdhci-tegra` about
   `nvidia,only-1-8v` (or start the host at 1.8V for this node).
2. Add `/usr/share/udhcpc/default.script` so leases are applied.
3. Confirm outbound traffic (the gateway ping and DNS work; HTTP did not).
4. Then touch, audio, and the installed-boot path.
