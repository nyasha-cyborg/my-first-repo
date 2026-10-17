# The ROM's system and vendor partitions

Opened 2026-10-17. Several things this port needed were not in the kernel, not in
`linux-firmware`, and not in the device tree — because on Android they live in
the **system and vendor partitions** instead. They turn out to be readable.

## Getting at them

An OTA does not contain a filesystem. It contains each partition as
`<part>.new.dat` — file contents concatenated in one order, with no filenames —
plus a `<part>.transfer.list` saying where each run of blocks belongs. So the
payload has to be replayed before anything in it can be read:

```sh
D=~/Downloads/nexus9/ota-system
mkdir -p "$D" && cd "$D"
unzip -o ~/Downloads/nexus9/roms/volantisg-ota-n4f27p.zip \
    system.new.dat system.transfer.list vendor.new.dat vendor.transfer.list

python3 -I ~/code/nexus9/tools/ota-image.py \
    system.transfer.list system.new.dat system.img
python3 -I ~/code/nexus9/tools/ota-image.py \
    vendor.transfer.list vendor.new.dat vendor.img
```

`tools/ota-image.py` does the replay and asserts its own interpretation against
the payload size, so a wrong reading of the format fails loudly rather than
producing a plausible-looking image.

Then read them **without mounting**, which needs no privileges:

```sh
debugfs -R "ls -l /" system.img
debugfs -R "cat /etc/RT5506" system.img
debugfs -R "dump /firmware/bcm4354.hcd bcm4354.hcd" vendor.img
```

`file` is a good sanity check on the result — both images come back as
`Linux rev 1.0 ext4 filesystem data`, named `system` and `vendor`.

## What was in them

### Firmware that was otherwise unobtainable — `vendor/firmware/`

| File | What it is |
|---|---|
| **`bcm4354.hcd`** | **Bluetooth firmware.** Reads `BCM4354 37.4MHz WLBGA HTC T1-0192` — this exact board |
| `bcm4350b1.hcd`, `bcm4350c0.hcd` | Other BCM parts, presumably fallbacks |
| `rt5677_elf_vad` | The rt5677 VAD DSP firmware, which explains the `dsp_vad_suffix` and `rt5677_load_dsp_from_file` strings found in the kernel |
| `fw_bcmdhd.bin`, `fw_bcmdhd_apsta.bin` | Wi-Fi firmware under Android's `bcmdhd` names; mainline's equivalent, `brcmfmac4354-sdio.bin`, is already in linux-firmware |
| `bcm20795_firmware.ncd` | NFC firmware — BCM20795, confirming that the `broadcom,bcm20791` node in the port's tree is an NFC part and not Bluetooth |
| `sensor_hub.img`, `synaptics.img`, `sar*_CY8C.img` | Sensor hub, touch and SAR firmware |
| `nvavp_*.bin` | AVP microcode — audio and H.264 decode on the video co-processor |
| `tegra13x/NETB_img.bin`, `fecs.bin`, `gpccs.bin`, `gpmu_ucode.bin` | The **nouveau** GPU firmware set for Kepler |
| `tegra13x/vic03_ucode.bin`, `nvhost_msenc031.fw`, `nvhost_tsec.fw` | VIC, video encode and TSEC |

### Configuration that Android kept out of the kernel — `system/etc/`

The most useful find, because it was believed to be locked inside a compiled
Android HAL:

- **`/etc/RT5506`** — the headphone amplifier's register table in plain text.
  A `__TABLE_START__` header, then sections keyed by mode (`00 init`, `01 mute`,
  `02 off`, `03 playback`, `04 playback_8_ohm` … `20 Mono HS, Beats ON`), each a
  list of register/value pairs. This is exactly the tuning that the earlier
  audio survey concluded mainline could not reproduce.
- `/etc/bluetooth/bt_vendor.conf` — two lines that answer the Bluetooth
  questions outright: `UartPort = /dev/ttyTHS2` and
  `FwPatchFilePath = /vendor/firmware/`.
- `/etc/nvaudio_conf.xml`, `/etc/mixer_paths_0.xml`, `/etc/audio_policy.conf` —
  the audio HAL's view of the routing.
- `/etc/gps.bcm47521.conf` — BCM47521 GNSS.

## What each unblocks

- **Bluetooth** is no longer firmware-blocked. `bcm4354.hcd` is the file the
  kernel's `btbcm` needs; what remains is giving it the right name, and writing
  the device tree node against `ttyTHS2` with the control GPIOs.
- **The headphone path** is more tractable than the audio note estimated. The
  RT5506 register values are available as text, so a driver would be
  transcribing a known table rather than reverse-engineering one.
- **The display and 3D path** gains a second source for the Kepler firmware,
  independent of linux-firmware.

None of this has been used for anything yet — the files are extracted and
identified, which is all.

## Why the blobs are not in this repository

The extracted firmware is small — `bcm4354.hcd` is 41 KB — but it is vendor
firmware with its own licensing, so it is not committed. What is committed is
the *way to get it*: `tools/ota-image.py` plus the recipe above, against an OTA
that is already obtainable. The extracted copies live alongside the ROMs, in
`~/Downloads/nexus9/vendor-firmware/`, which is the same place the rest of the
multi-gigabyte data lives and is gitignored.
