#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

# The only public origin this project may name. It is product-named on purpose: any other
# workers.dev host is a Cloudflare account subdomain, and an account subdomain is a personal
# identifier. Checking against the allowed value keeps the forbidden one out of the repository
# without ever writing the forbidden one down. See docs/adr/0003-product-neutral-relay-host.md.
allowed_origin="https://ticktick-garmin-relay.garmin-bridge.workers.dev"
allowed_host=${allowed_origin#https://}

if rg -n --hidden \
    --glob '!.git' \
    --glob '!.git/**' \
    --glob '!relay/node_modules/**' \
    --glob '!build/**' \
    --glob '!dist/**' \
    '(/Users/[A-Za-z0-9._-]+/|/home/[A-Za-z0-9._-]+/|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})' \
    "$project_root"; then
    echo "public leak check: personal path or email found" >&2
    exit 1
fi

found_hosts=$(rg -o --no-filename --hidden \
    --glob '!.git' \
    --glob '!.git/**' \
    --glob '!relay/node_modules/**' \
    --glob '!build/**' \
    --glob '!dist/**' \
    '[A-Za-z0-9.-]+\.workers\.dev' \
    "$project_root" | sort -u || true)

for host in $found_hosts; do
    if [ "$host" != "$allowed_host" ]; then
        echo "public leak check: unexpected workers.dev host $host" >&2
        echo "public leak check: only $allowed_host may appear" >&2
        exit 1
    fi
done

if ! rg -qF "$allowed_origin" "$project_root/watch/source/RelayClient.mc"; then
    echo "public leak check: the watch must call the product-neutral relay origin" >&2
    exit 1
fi

echo "public leak check: passed"
