# Browser for Nexus 9 (LineageOS 16 / Android 9, arm64, no Play)

Checked 2026-10-26. Not installed yet.

## Choice: Firefox for Android (official Mozilla build)

- Uses its own engine (Gecko), not the system WebView.
- Supports Android 8.0 and newer. Firefox 144 (Oct 2025) raised the minimum
  from Android 5 to 8; there is no announced plan to drop Android 9.
  Sources: Firefox 144 release notes, SUMO "Will Firefox work on my mobile device".
- Updated every 4 weeks by Mozilla. Current stable is 158.0.2
  (product-details.mozilla.org/1.0/mobile_versions.json).

## Other options considered
- IronFox: a hardened Firefox fork with the same Android 8 minimum, still
  active. It's a good second choice, but the build comes from a smaller
  project. Its site still says "Android 5", which is out of date.
- Mull: the project is archived and no longer updated (from memory, not re-checked this session).
- Cromite: its README now says Android 10+, so it won't run on this tablet.

## File
- /tmp/n9browser/fenix-158.0.2.multi.android-arm64-v8a.apk
- Source: https://archive.mozilla.org/pub/fenix/releases/158.0.2/android/fenix-158.0.2-android-arm64-v8a/
- Size: 135,361,229 bytes (~129 MiB)
- sha256: 46a588b9f33c261e8cda9549426fc0118fde517cb87087633c11000d3e8099d5
- Package org.mozilla.firefox, versionCode 2016191570, minSdk 26, abi arm64-v8a
- Signer: CN=Release Engineering, O=Mozilla Corporation; cert SHA-256
  a78b62a5165b4494b2fead9e76a280d22d937fee6251aece599446b2ea319b04
  (the same key Mozilla uses for Play-store Firefox, so updates install over it)

## Updates without Play
Firefox doesn't update itself. Pick one of these:
- Obtainium, pointed at archive.mozilla.org fenix releases (or the
  mozilla-mobile/firefox-android GitHub releases).
- Or, by hand: download the new arm64 APK from archive.mozilla.org each month and install it with adb.
Aurora Store also works (anonymous Play login), but it is not an official Mozilla channel.
