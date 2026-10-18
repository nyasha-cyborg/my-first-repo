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

## Layout

- `notes/` — investigation state and evidence, one file per topic
- `patches/` — kernel/DT changes
- `tools/` — host and on-device helpers
- `setup.sh` — environment setup

Keep new notes in `notes/`, never in the repo root.
