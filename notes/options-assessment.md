# Where to go from here: Android (3.10 kernel) vs pmOS — assessment 2026-10-26 (written while the owner slept)

Facts measured today (see android-probe.md, lte.md, gpu.md):
- LineageOS 16.0 (Android 9, retiredtab 20251224, 3.10.103) boots, smooth, no flicker, hardware H.264/VP8 decode present
  (`OMX.Nvidia.h264.decode`, `vp8.decode`). It is a **Wi-Fi build**: device tree has LTE hooks (`device-lte.mk`, `flounder_lte/`,
  `rild.libpath=/vendor/lib64/libril-qc-qmi-1.so`) but no Qualcomm blobs -> no LTE.
- Stock 7.1.1 N4F27P (Google, LTE unit): LTE works, almost no flicker, but the old-account FRP lock blocked setup and the
  Google apps are too old for current YouTube.
- pmOS (mainline 6.19): GPU 3D works (nouveau + patched Mesa), but slow/hot, flicker, no HW video player path.

## Options
| # | Path | LTE | YouTube / Stremio | Smoothness | Effort | Risk |
|---|---|---|---|---|---|---|
| A | **LineageOS 16 + LTE blob transplant** (stay as is) | to do: copy `qcks, qmuxd, netmgrd, ATFWD-daemon, port-bridge, qmiproxy, efsks, time_daemon, libril-qc-qmi-1 + deps`, firmware `/vendor/firmware/mdm`, init services gated on `androidboot.baseband`, sepolicy (or permissive), CarrierConfig. All sources are in `~/Downloads/nexus9/google-volantisg-n4f27p/` (stock vendor.img) | NewPipe/SmartTube (F-Droid) + Stremio APK: Android 9 is fine | smooth today | 3-6 h of trial and error | Android 9 telephony vs 7.1.1 RIL blob mismatch possible; recoverable by re-flashing |
| B | Newer Android (10-14) on the 3.10 kernel | n/a | n/a | n/a | not realistic: Android 10+ userspace needs kernel >= 4.4/4.9 features (eBPF, netd, etc.); the 3.10 NVIDIA kernel cannot be bumped by us | very high |
| C | AOSP/Lineage 17+ on a **mainline kernel + Mesa** | needs modem HAL rewrite | possible in theory | unknown | months (gralloc/hwcomposer/audio/camera/modem HALs) | very high |
| D | **pmOS with the fixes** | LTE works from mainline per notes/lte.md (ModemManager flow done) | Firefox (slow); mpv HW decode not wired; Waydroid for Android apps is heavy on 1.8 GB | can approach Android once DVFS works | days | medium |

## Recommendation
1. **Short term (YouTube + Stremio + LTE):** option **A**. It keeps the smooth, flicker-free NVIDIA stack and hardware decode; LTE
   is a vendor-blob job with all inputs already on disk. If the 7.1.1 RIL blob will not talk to Android 9 telephony, fall back
   to stock 7.1.1 + NewPipe/SmartTube/Stremio (needs the old Google account or a different unlock route; LineageOS has no FRP).
2. **pmOS (long term, hobby/upstream value):** keep it alive as a separate effort; the fixes below are upstreamable:
   - `patches/linux-flounder-emc/` — inverted AUTO_CAL_CONFIG mask in tegra124-emc (most likely cause of the "EMC DVFS corrupts
     memory" bug; if it holds, EMC scaling can return: less heat/power, more bandwidth when needed).
   - `patches/linux-flounder-gpu/` — GK20A GR reset (first-use `gr: init failed`).
   - then re-enable GPU DVFS (the old PLL-slide hang may also have been memory corruption), use Android's thermal/EDP values
     (android-reference/) for soctherm throttling, and re-test the panel with the live Android DSI register dump.
3. **Not worth it:** B and C.

## Next concrete steps (when the owner is back)
- A: say "go" and I do the LTE transplant on the current LineageOS (adb root, reversible).
- D: reinstall pmOS only after the EMC fix is validated on a test kernel (`fastboot boot`, nothing flashed).
