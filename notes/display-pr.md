# PR drafts for the Nexus 9 display work

Branch: `display-vblank-cmds` in `/home/nyasha/code/linux-flounder`, based on
`38ff6862` (the commit the postmarketOS package pins). Six commits, no push yet.

Two submissions are possible:

1. a fork PR against `yuka/linux` branch `flounder` (everything below);
2. upstream: two separate series, because `drm/tegra` and the panel/DT changes
   have different maintainers.

---

## Fork PR: yuka/linux, branch `flounder`

**Title:** drm/tegra: fix Nexus 9 (flounder) display bring-up

**Body:**

This series makes the ganged JDI LPM089A128A panel on the LTE Nexus 9 work
under mainline. Before it, the panel powered on, ACKed every DCS command, and
stayed black.

Root cause: the panel only executes commands that arrive inside the running
video stream, at vblank. Mainline sends panel init before starting video (or
with the stream stopped), which gets a protocol ACK but no execution. The
vendor driver never does this: `tegra_dsi_start_host_cmd_v_blank_video()`
queues the packet with `DSI_VIDEO_MODE_CONTROL` and lets the controller insert
it at the next vblank.

Changes:

- `drm/tegra`: correct the DSI clock (371.5 MHz parent with shift divider 1;
  the previous computation left divider 6 after a rejected 742.5 MHz request)
- `drm/tegra`: match the bootloader's video configuration (SOL delay, packet
  lengths, `VIDEO_MODE_CONTROL`, ECC/checksum host control)
- `drm/tegra`: deliver host commands into the running video stream at vblank,
  and keep that path for runtime backlight writes
- `drm/panel`: add the JDI LPM089A128A driver, including a real reset pulse
  (driving the line high alone left the panel in whatever state survived the
  previous SoC reboot)
- `arm64: tegra132`: enable the display nodes, ganged DSI and the panel

Tested on hardware (`HT4C3WV00112`, LTE variant): kernel console text with a
cursor appears on the panel, then a userspace white-paint fills it; both DSI
links report streaming with no errors.

Known limitations:

- the vblank insertion uses a fixed two-frame delay rather than a frame-end
  wait;
- suspend/resume and modeset cycling have not been exercised;
- Android/postmarketOS userspace has not been booted on top yet.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## Upstream series 1: drm/tegra (drm-misc)

**Title:** drm/tegra: dsi: support host commands in running video mode

**Body:**

Tegra DSI can insert host command packets into an active video stream at
vblank (`DSI_VIDEO_MODE_CONTROL`). Some panels only accept their init and
backlight commands that way: with the stream stopped, the controller completes
the host trigger but the panel never executes the packet.

Add that path to `tegra_dsi_host_transfer()` and use it whenever the encoder
has started video, instead of the host trigger. Also carry the two related
fixes this uncovered: the ganged non-burst packet length/SOL delay values and
the DSI clock computation.

Split into independent commits before sending:

1. `drm/tegra: dsi: fix ganged clock and packet timing`
2. `drm/tegra: dsi: inject host commands into the video stream`

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## Upstream series 2: panel + DT

**Title:** drm/panel: add JDI LPM089A128A and enable it on tegra132 flounder

**Body:**

Add a driver and binding for the 1536x2048 JDI panel used in the Google
Nexus 9, driven as two ganged 4-lane DSI links, and wire it up in the
`tegra132-flounder` device tree together with the DSI-B MIPI pad fix and the
LTE board compatible.

The panel takes DCS over both links and has no PWM or enable line: brightness
is DCS 0x51.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## Before sending

- Add `Signed-off-by:` to every commit (`git rebase --signoff 38ff6862` with
  the correct name/email configured).
- Rebase the upstream split onto `drm-misc-next`; the fork PR can stay on
  `flounder`.
- Run `scripts/checkpatch.pl` again after the rebase.
- Do not push until explicitly asked.
