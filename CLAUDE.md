# Nexus 9 port — project instructions

## Debugging state

Hardware bring-up here spans many sessions, flash cycles, and model switches.
Before working on USB, display, audio, Bluetooth, or boot-stage debugging:

1. Use the `debug-state` skill.
2. Read the matching note **first** — USB: `notes/usb-debug.md`; display:
   `notes/display-progress.md`; audio: `notes/audio.md`; Bluetooth:
   `notes/bluetooth.md`.
3. After each test cycle, update the note: hypothesis status, trimmed evidence,
   changes since the last cycle, dead ends, next actions.
4. Commit the note with the code it describes.

Do not re-derive state from full logs when a note exists; extend the note if
detail is missing.

## Vendor behaviour: REA before designing tests

Before designing a kernel-side test for how vendor hardware behaves, pull the
relevant Android userspace blobs with root adb (`/vendor/lib64`,
`/vendor/lib64/hw`, `/vendor/firmware`, `/system/etc`) into a fresh directory
and run REA on them. Userspace vendor libs often answer questions the
downstream kernel source cannot (which sysfs node powers a chip, which ioctl
drives wake, whether a HAL does real work or only flips ALSA mixer switches).
Record the result in the topic note before the next boot cycle.

## Layout

- `notes/` — investigation state and evidence, one file per topic
- `patches/` — kernel/DT changes
- `tools/` — host and on-device helpers
- `setup.sh` — environment setup

Keep new notes in `notes/`, never in the repo root.
