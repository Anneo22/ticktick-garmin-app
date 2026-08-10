#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

node "$project_root/contracts/test-contract.mjs"
node "$project_root/scripts/check-view-geometry.mjs"
node "$project_root/scripts/check-icon.mjs"
"$project_root/scripts/check-public-leaks.sh"

if rg -n '(client_secret|access_token|Bearer [A-Za-z0-9_-]{16,})' "$project_root/watch" "$project_root/contracts" --glob '!*.md'; then
    echo "source: possible embedded secret found" >&2
    exit 1
fi

relay="$project_root/watch/source/RelayClient.mc"
if ! rg -q 'const RELAY_URL = "https://[^\"]+";' "$relay" ||
    rg -q 'Properties\.getValue\("relayUrl"\)|<property id="relayUrl"' "$project_root/watch" ||
    rg -q '(example\.invalid|localhost|127\.0\.0\.1)' "$relay"; then
    echo "source: relay URL must be an immutable production HTTPS constant" >&2
    exit 1
fi

delegate="$project_root/watch/source/TaskListDelegate.mc"
view="$project_root/watch/source/TaskListView.mc"
if ! rg -q 'function onTap\(' "$delegate" || ! rg -q 'function onSwipe\(' "$delegate"; then
    echo "source: watch input delegate must support taps and swipes" >&2
    exit 1
fi
if ! rg -q 'cyclePrimary\(1\)' "$delegate" || ! rg -q 'cyclePrimary\(-1\)' "$delegate" ||
    ! rg -q '\["today", "inbox", "lists"\]' "$view"; then
    echo "source: navigation must expose Today, Inbox, and Lists while retaining swipe input" >&2
    exit 1
fi
if rg -q 'SELECT TO START|CONTACTING PHONE|Approve this code on your phone' "$view" ||
    ! rg -q 'START PAIRING' "$view" ||
    ! rg -q 'CONNECTING' "$view"; then
    echo "source: pairing action must use a compact input-neutral label" >&2
    exit 1
fi
if ! rg -q 'function armCompletion\(' "$project_root/watch/source/TaskController.mc" ||
    ! rg -q 'function disarm\(' "$project_root/watch/source/TaskController.mc" ||
    rg -q 'confirmingCompletion = true' "$view"; then
    echo "source: only the controller may arm a completion, and only through armCompletion" >&2
    exit 1
fi
if ! rg -q 'REQUEST_TIMEOUT_MS' "$relay" || ! rg -q 'onTimeout' "$relay"; then
    echo "source: relay requests must have a recovery timeout" >&2
    exit 1
fi
if ! rg -q 'var activeRequest' "$relay" || ! rg -q 'catch \(error\)' "$relay"; then
    echo "source: relay requests must remain owned and recover from synchronous failures" >&2
    exit 1
fi

if [ -d "$project_root/relay" ]; then
    npm --prefix "$project_root/relay" run verify
fi

echo "source: checks passed"
