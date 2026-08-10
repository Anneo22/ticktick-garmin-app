#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sdk_root=$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")
key_path=${CIQ_DEVELOPER_KEY:-"$project_root/.developer-key.der"}
primary=${WATCH_TEST_DEVICE:-$(node -e 'const m=require(process.argv[1]); process.stdout.write(m.representative.primaryFenix8)' "$project_root/watch/device-matrix.json")}

mkdir -p "$project_root/build"
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
    PATH=/opt/homebrew/opt/openjdk@17/bin:$PATH \
    "$sdk_root/bin/monkeyc" -f "$project_root/watch/tests.jungle" -o "$project_root/build/ticktick-garmin-tests.prg" -y "$key_path" -d "$primary" -t -w

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
    PATH=/opt/homebrew/opt/openjdk@17/bin:$PATH \
    "$sdk_root/bin/connectiq" >/dev/null 2>&1

set +e
test_output=$(JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
    PATH=/opt/homebrew/opt/openjdk@17/bin:$PATH \
    "$sdk_root/bin/monkeydo" "$project_root/build/ticktick-garmin-tests.prg" "$primary" -t 2>&1)
set -e
echo "$test_output"

echo "$test_output" | rg -q '^PASSED \(passed=[1-9][0-9]*, failed=0, errors=0\)$'
echo "watch tests: passed on $primary"
