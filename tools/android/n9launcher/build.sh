#!/bin/bash
# Build N9 Home (minimal launcher) with SDK build-tools only: javac + d8 + aapt2 + zipalign + apksigner.
#   usage: tools/android/n9launcher/build.sh <keystore> <storepass>   -> out/N9Home.apk
set -eu
cd "$(dirname "$0")"; KS=$1; PW=$2
BT=$(ls -d ~/Android/Sdk/build-tools/* | tail -1); JAR=$(ls ~/Android/Sdk/platforms/*/android.jar | tail -1)
rm -rf out && mkdir -p out/classes
javac -source 8 -target 8 -bootclasspath "$JAR" -classpath "$JAR" -d out/classes $(find src -name '*.java') 2>&1 | grep -v "bootstrap classpath" || true
"$BT/d8" --min-api 26 --lib "$JAR" --output out $(find out/classes -name '*.class')
"$BT/aapt2" link -o out/unsigned.apk -I "$JAR" --manifest AndroidManifest.xml --min-sdk-version 26 --target-sdk-version 28
python3 -I -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],'a'); z.write(sys.argv[2],'classes.dex'); z.close()" out/unsigned.apk out/classes.dex
"$BT/zipalign" -f 4 out/unsigned.apk out/aligned.apk
"$BT/apksigner" sign --ks "$KS" --ks-pass "pass:$PW" --key-pass "pass:$PW" --out out/N9Home.apk out/aligned.apk
ls -l out/N9Home.apk
