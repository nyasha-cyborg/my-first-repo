# Updating LineageOS 16 on the Nexus 9

A new ROM build wipes our changes on /vendor and the kernel (LNX). /data is kept.

1. Build the two files that are not in git: `rild` (see the header of `lte/install-lte-lineage16.sh`) and
   `N9MobileOverlay.apk` (build `lte/overlay/` with aapt2, zipalign, apksigner, any test key).
2. Have the stock vendor files ready: `/tmp/n9ltetx/stage` (LTE files) and stock `liboemcrypto.so`
   (from the stock N4F27P vendor.img).
3. Reboot to TWRP, install the new LineageOS 16 zip. Do not wipe data. Reboot to Android.
4. Enable root adb (Developer options) and plug in the USB cable.
5. Run:
   `tools/android/post-rom-update.sh --rild <rild> --overlay <N9MobileOverlay.apk> [--oemcrypto <so>] [--boot <img>]`
   It backs up the new LNX to `~/Downloads/nexus9/boot-backups/`, flashes our kernel, re-adds LTE, liboemcrypto
   (HW video decode), recreates the /data dirs, reboots, and prints a summary of checks.
6. Running it again is safe; it skips what is already done.
