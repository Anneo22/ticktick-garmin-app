#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sdk_root=$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")
key_path=${CIQ_DEVELOPER_KEY:-"$project_root/.developer-key.der"}
fenix_device=$(node -e 'const m=require(process.argv[1]); process.stdout.write(m.representative.primaryFenix8)' "$project_root/watch/device-matrix.json")

mkdir -p "$project_root/build" "$project_root/dist"
release_tmp=$(mktemp -d "$project_root/build/package.XXXXXX")
trap 'rm -rf "$release_tmp"' EXIT HUP INT TERM
# A failed package must leave no previous release looking current.
rm -f "$project_root/dist/ticktick-garmin.iq" "$project_root/dist/TICKTICK.PRG"

"$project_root/scripts/verify.sh"
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
    PATH=/opt/homebrew/opt/openjdk@17/bin:$PATH \
    "$sdk_root/bin/monkeyc" -e -f "$project_root/watch/monkey.jungle" -o "$release_tmp/ticktick-garmin.iq" -y "$key_path"
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
    PATH=/opt/homebrew/opt/openjdk@17/bin:$PATH \
    "$sdk_root/bin/monkeyc" -f "$project_root/watch/monkey.jungle" -o "$release_tmp/TICKTICK.PRG" -y "$key_path" -d "$fenix_device" -w

test -s "$release_tmp/ticktick-garmin.iq"
test -s "$release_tmp/TICKTICK.PRG"
mv "$release_tmp/ticktick-garmin.iq" "$project_root/dist/ticktick-garmin.iq"
mv "$release_tmp/TICKTICK.PRG" "$project_root/dist/TICKTICK.PRG"
echo "package: signed Store export and $fenix_device sideload binary"
