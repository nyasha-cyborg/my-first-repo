#!/bin/sh
# Extract the modem firmware images from the stock Google LTE factory image into /lib/firmware/n9-modem.
# usage: provision-modem-fw.sh volantisg-n4f27p-factory-1e29c858.zip   (official dl.google.com file, sha256
#        1e29c858d283d75dab5c53eaa6397cd1f8bf4b3dd24efa03fb4b6f153eb899ac; not redistributed by this repo)
set -e
ZIP=$1; DEST=${2:-/lib/firmware/n9-modem}; T=$(mktemp -d)
echo "1e29c858d283d75dab5c53eaa6397cd1f8bf4b3dd24efa03fb4b6f153eb899ac  $ZIP" | sha256sum -c
unzip -q "$ZIP" -d "$T"; unzip -q "$T"/*/image-*.zip vendor.img -d "$T"
simg2img "$T/vendor.img" "$T/vendor.raw"
mkdir -p "$DEST"
for f in sbl1 rpm tz mba apps sdi dsp1; do
	debugfs -R "dump /firmware/mdm/image/$f.mbn $DEST/$f.mbn" "$T/vendor.raw" 2>/dev/null
done
for f in htcssmem htcnvmfg htcrfnv htcuserd htccdma htccnv_a htccnv_t htccnv_v htccnv_s htccnv_u htccnv_o; do
	debugfs -R "dump /firmware/mdm/image/$f.mbn $DEST/$f.mbn" "$T/vendor.raw" 2>/dev/null
done
for r in att tmo vzw ul o2; do
	debugfs -R "dump /firmware/mdm/image/rcdata_$r.img $DEST/rcdata_$r.img" "$T/vendor.raw" 2>/dev/null
done
rm -rf "$T"; ls -l "$DEST"
