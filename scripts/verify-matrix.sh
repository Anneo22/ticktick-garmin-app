#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sdk_cfg="$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg"
sdk_root=$(cat "$sdk_cfg")
monkeyc="$sdk_root/bin/monkeyc"
key_path=${CIQ_DEVELOPER_KEY:-"$project_root/.developer-key.der"}

node "$project_root/scripts/configure-devices.mjs"
mkdir -p "$project_root/build/matrix"

products=$(node -e 'const m=require(process.argv[1]); process.stdout.write(m.products.map((p) => p.id).join(" "))' "$project_root/watch/device-matrix.json")
for product in $products; do
    log="$project_root/build/matrix/$product.log"
    if ! JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
        PATH=/opt/homebrew/opt/openjdk@17/bin:$PATH \
        "$monkeyc" -f "$project_root/watch/monkey.jungle" -o "$project_root/build/matrix/$product.prg" -y "$key_path" -d "$product" -w >"$log" 2>&1; then
        cat "$log" >&2
        exit 1
    fi
done

echo "matrix: compiled $(printf '%s\n' $products | wc -l | tr -d ' ') SDK-verified products"
