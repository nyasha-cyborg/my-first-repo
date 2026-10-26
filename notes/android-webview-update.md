# Android WebView update (LineageOS 16 / Android 9)

## Plain summary

The tablet's built-in web engine (WebView 135) is old. The newest version that
still runs on Android 9 is **138.0.7204.63**. Chromium 139 and later need
Android 10 (the Chromium dev PSA says 138 is the last version for Oreo/Pie). We
take the copy LineageOS ships in its own prebuilt repo and copy it over the old
one in /system. Nothing is installed yet.

## Chosen artifact

| | |
|---|---|
| Source | LineageOS `android_external_chromium-webview_prebuilt_arm64`, commit `f6f994f9912b26d1dffd100f6de959f9dfd31414` ("Update Chromium Webview arm64 to 138.0.7204.63", 2025-07-07). The next commit in the repo is 139. |
| Download | Git LFS object via `https://review.lineageos.org/LineageOS/android_external_chromium-webview_prebuilt_arm64.git/info/lfs` (batch API, oid below). Git LFS clone + `git lfs pull` at that commit gives the same file. |
| Local copy | `/tmp/n9webview/webview-138.0.7204.63-arm64.apk` |
| Size | 243,509,357 bytes |
| SHA-256 | `446ead71292578830d99e690fd8dded73bc63d85df80f0cfba37762ccb330326` (matches the LFS pointer) |
| Package | `com.android.webview`, versionCode 720406301 |
| minSdk | 26, so it runs on API 28 |
| ABI | arm64-v8a + armeabi-v7a (covers 64-bit and 32-bit apps) |
| Signature | APK v2 only, signer DN `CN=Unknown,...`, cert SHA-256 `32a2fc74d731105859e5a85df16d95f102d85b22099b8064c5d8915c61dad1e0` |

Not chosen: Google's official WebView (Play-only, package
`com.google.android.webview`, not in the Lineage provider list). Mulch and
Cromite are not chosen either: both track current Chromium and need API 29+ now.

## Install options

1. **Replace in /system (recommended).** Signature does not matter, because a
   new system-partition APK is rescanned at boot and its own cert is accepted.
   The package name stays the same, so `config_webview_packages` does not need
   to change.
   ```
   adb root && adb remount        # needs dm-verity off (already true on this ROM if remount works)
   adb shell ls /system/app/webview          # confirm path + file name (webview.apk)
   adb shell cp /system/app/webview/webview.apk /data/local/tmp/webview-135-backup.apk
   adb pull /system/app/webview/webview.apk ~/n9-backup/webview-135.apk
   adb shell df -h /system                   # need ~240 MB free (old APK is replaced)
   adb push webview-138.0.7204.63-arm64.apk /system/app/webview/webview.apk
   adb shell chmod 644 /system/app/webview/webview.apk
   adb shell rm -rf /system/app/webview/oat  # stale odex from 135, if present
   adb reboot
   ```
   Check: `adb shell dumpsys webviewupdate` should report 138.0.7204.63, and
   `dumpsys package com.android.webview | grep versionName` should show the same.
   Remove any 135 update in /data first (`pm uninstall-system-updates com.android.webview`
   if one exists), or the /data copy will shadow the new system one.
2. **`adb install -r` as an update.** This only works if the cert matches the
   installed 135 cert. Compare
   `apksigner verify --print-certs` on the pulled 135 APK with the digest above.
   If they match, this is the simplest option and needs no remount.
3. **RRO overlay adding a different package** to `config_webview_packages`
   (same idea as `tools/android/lte/overlay` N9MobileOverlay). This only makes
   sense for a differently named provider, which we do not need here.

## Rollback

- Option 1: push the 135 backup back to `/system/app/webview/webview.apk`,
  remove `oat/`, and reboot. If the WebView will not load at all, boot still
  works (only apps that use WebView break), so adb stays usable.
- Option 2: `adb shell pm uninstall-system-updates com.android.webview` (or
  `pm uninstall com.android.webview`, which removes just the update).

## Caveats

- 138 is end of the line. It gets no further security fixes on Android 9.
- /system free space must fit about 243 MB. Check before pushing.

## 2026-10-26 14:25 — INSTALLED
- /system/product/app/webview/webview.apk replaced (adb root + remount) with 138.0.7204.63; old 135.0.7049.100 saved at
  ~/Downloads/nexus9/android-addons/webview-backup/. After reboot: `Current WebView package (com.android.webview, 138.0.7204.63)`.
- Firefox 158.0.2 (Mozilla official, archive.mozilla.org, signer Mozilla Release Engineering) installed as org.mozilla.firefox.
- Note: a ROM update restores the ROM's WebView; post-rom-update.sh does not handle WebView yet (138 is final for Android 9 anyway).
