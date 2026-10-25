#!/bin/bash
# Reproduce the LTE transplant on the LineageOS 16 Wi-Fi build (retiredtab flounder) with root adb. Reversible (additive).
#   usage: tools/android/lte/install-lte-lineage16.sh <stage-dir> <rild-binary>
# <stage-dir>: files extracted from the stock vendor.img (see notes/android-reference/lte-transplant-files.txt;
#   `debugfs -R "rdump / out" vendor.raw`, then copy the listed paths keeping the tree).
# <rild-binary>: built from LineageOS/android_hardware_ril lineage-16.0 rild.c + librilutils with NDK r26d:
#   aarch64-linux-android28-clang -O2 -DRIL_SHLIB -I<ril>/include -I<ril> -I<core>/libcutils/include -I<core>/liblog/include \
#     rild.c librilutils.c record_stream.c -o rild -L<libs from the tablet> -lcutils -lril -llog -ldl
set -eu
STAGE=$1; RILD=$2; HERE=$(cd "$(dirname "$0")" && pwd)
adb root; sleep 2; adb remount
adb push "$STAGE"/. /vendor/
adb shell 'chmod 755 /vendor/bin/*; mkdir -p /vendor/bin/hw /data/qcks/mdm; chown system:system /data/qcks /data/qcks/mdm; chmod 770 /data/qcks /data/qcks/mdm'
adb push "$RILD" /vendor/bin/hw/rild; adb shell chmod 755 /vendor/bin/hw/rild
adb push "$HERE/rild.rc" /vendor/etc/init/rild.rc
adb pull /vendor/etc/vintf/manifest.xml /tmp/manifest.orig.xml
patch -o /tmp/manifest.new.xml /tmp/manifest.orig.xml "$HERE/vintf-manifest-radio.diff"
adb push /tmp/manifest.new.xml /vendor/etc/vintf/manifest.xml
adb shell 'chmod 644 /vendor/etc/init/rild.rc /vendor/etc/vintf/manifest.xml; restorecon -R /vendor /data/qcks'
adb reboot
