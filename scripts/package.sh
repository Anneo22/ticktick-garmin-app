#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sdk_root=$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")
key_path=${CIQ_DEVELOPER_KEY:-"$project_root/.developer-key.der"}

"$project_root/scripts/verify.sh"
mkdir -p "$project_root/dist"
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
    PATH=/opt/homebrew/opt/openjdk@17/bin:$PATH \
    "$sdk_root/bin/monkeyc" -e -f "$project_root/watch/monkey.jungle" -o "$project_root/dist/ticktick-garmin.iq" -y "$key_path"

test -s "$project_root/dist/ticktick-garmin.iq"
echo "package: signed dist/ticktick-garmin.iq"
