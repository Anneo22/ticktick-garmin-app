#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"$project_root/scripts/verify-source.sh"

sdk_cfg="$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg"
if [ ! -f "$sdk_cfg" ]; then
    echo "watch: blocked, accept the Garmin SDK agreement and install an SDK/device pack" >&2
    exit 2
fi

sdk_root=$(cat "$sdk_cfg")
monkeyc="$sdk_root/bin/monkeyc"
if [ ! -x "$monkeyc" ]; then
    echo "watch: active SDK does not contain monkeyc" >&2
    exit 2
fi

if [ ! -f "$project_root/watch/manifest.xml" ]; then
    node "$project_root/scripts/configure-devices.mjs"
fi

key_path=${CIQ_DEVELOPER_KEY:-"$project_root/.developer-key.der"}
if [ ! -f "$key_path" ]; then
    echo "watch: blocked, CIQ_DEVELOPER_KEY is missing" >&2
    exit 2
fi

"$project_root/scripts/verify-matrix.sh"
"$project_root/scripts/verify-watch-tests.sh"
WATCH_TEST_DEVICE=instinct2s "$project_root/scripts/verify-watch-tests.sh"
"$project_root/scripts/build-visual-qa.sh" fenix847mm today >/dev/null
"$project_root/scripts/build-visual-qa.sh" fenix847mm lists >/dev/null
"$project_root/scripts/build-visual-qa.sh" fenix847mm stress >/dev/null
"$project_root/scripts/build-visual-qa.sh" instinct2s today >/dev/null
echo "watch: compiler matrix passed"
