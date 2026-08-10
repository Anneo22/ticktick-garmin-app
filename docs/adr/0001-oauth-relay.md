# ADR 0001: use a minimal OAuth pairing relay

Status: accepted, 2026-08-05

## Decision

The public watch app will pair through a small TickTick-only relay. TickTick's OAuth client secret and user access token stay server-side. The watch receives an opaque relay session token and can invoke only named operations.

## Why

Garmin can open an OAuth page through Garmin Connect Mobile, but that mechanism does not safely perform a confidential-client token exchange inside a public watch binary. Embedding the TickTick client secret would expose it to every installer. A generic reverse proxy would also turn a leaked watch token into excessive authority.

The relay therefore has one narrow job: complete OAuth, store the TickTick token encrypted, validate a hashed watch session token, and translate a bounded operation set. It is not a general backend and does not own task data beyond transient responses.

## Consequences

- Public use has a small hosting dependency, even though the app itself is free.
- A privacy policy, retention statement, abuse controls, and operational monitoring are required for Store publication.
- Pairing and API calls continue to work without a custom phone app.
- A personal sideload can use the same relay contract locally without changing watch code.

## Review trigger

Revisit only if TickTick adds a public OAuth flow that does not require a client secret on the device, or Garmin provides a secure confidential-client exchange service suitable for this provider.
