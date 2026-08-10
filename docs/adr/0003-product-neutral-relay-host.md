# ADR 0003: the public relay origin is product-named, not account-named

Status: accepted, 2026-08-10

## Decision

The single public origin of the pairing relay is `https://ticktick-garmin-relay.garmin-bridge.workers.dev`.

The Cloudflare account subdomain is `garmin-bridge` and the Worker script keeps the name `ticktick-garmin-relay`. Both halves of the host therefore describe the product. The watch binary, the Store reviewer notes, the pairing page, and every document name this origin and no other.

`scripts/check-public-leaks.sh` enforces it by allowlist: it collects every `*.workers.dev` host in the repository and fails on anything that is not the approved one. The forbidden host is never written down, so removing it cannot be undone by a copy-paste from the guard itself.

## Why

A `workers.dev` origin is `<script>.<account-subdomain>.workers.dev`. The account subdomain was previously a personal handle, so the app's only network endpoint published the maintainer's identity to every user, to the Connect IQ Store listing, and to anyone reading the binary. PRODUCT.md requires that public URLs and metadata carry the product's identity, not the maintainer's.

Renaming the account subdomain, rather than moving the Worker to a custom domain, keeps the relay free of DNS and certificate operations and keeps the origin immutable in the watch binary, which ADR 0001 depends on.

## Consequences

- The old personal origin stops resolving the moment the account subdomain is renamed. Any watch still running a build that points at it fails to pair until it is updated. The version bump to 0.2.0 marks that boundary.
- Renaming the account subdomain is **account-wide**: it changes the host of every Worker in the account at once.

## Safety condition, unverified here

Account-wide safety rests on one live fact: that `ticktick-garmin-relay` is the only Worker in this Cloudflare account. That is not provable from this repository, and it is **not** claimed here.

Before the rename, confirm the account inventory against the live API and record the result:

```
wrangler whoami
npx wrangler deployments list --name ticktick-garmin-relay
```

plus the account's Workers list from the Cloudflare dashboard or the `/accounts/{id}/workers/scripts` API. If any other Worker exists, that Worker's public URL changes too, and the rename must be reconsidered before it is performed.

## Review trigger

Revisit if a second Worker is ever added to the account, if the Store requires a branded custom domain, or if Cloudflare changes how account subdomains map to Worker hostnames.
