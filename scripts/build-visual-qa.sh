#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sdk_root=$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")
key_path=${CIQ_DEVELOPER_KEY:-"$project_root/.developer-key.der"}
device=${1:-fenix847mm}
view=${2:-today}
qa_dir="$project_root/build/visual-qa"

case "$view" in
    today) entry=VisualQaApp ;;
    lists) entry=VisualQaListsApp ;;
    *) echo "visual QA view must be today or lists" >&2; exit 2 ;;
esac

mkdir -p "$qa_dir"
sed "s/entry=\"TickTickGarminApp\"/entry=\"$entry\"/" "$project_root/watch/manifest.xml" > "$qa_dir/manifest.xml"

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
    PATH=/opt/homebrew/opt/openjdk@17/bin:$PATH \
    "$sdk_root/bin/monkeyc" \
    -f "$project_root/watch/visual-qa.jungle" \
    -o "$qa_dir/$device-$view.prg" \
    -y "$key_path" \
    -d "$device" \
    -w

echo "$qa_dir/$device-$view.prg"
