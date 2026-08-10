# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

TickTick users who wear a Garmin watch and want to review and complete tasks without paying for a separate watch-app subscription. The primary usage scene is a brief, one-handed interaction on a small round watch, with Garmin Connect available on the paired phone only when authentication or network access requires it.

## Product Purpose

Provide a public, subscription-free, TickTick-only Garmin Connect IQ app. Success means a user can pair once, browse Today with its overdue tail, Inbox, Lists, and the tasks inside a list, complete tasks deliberately, keep useful cached state offline, and recover from connectivity failures without becoming stuck.

## Positioning

The app uses TickTick's own authorization and a minimal credential relay, while keeping task interaction native to the Garmin watch and charging no recurring app subscription.

## Operating Context

The watch is operated through both physical buttons and touch. Touch targets must tolerate imprecise taps, but list navigation and task completion must remain unambiguous. The phone-mediated Garmin Connect bridge is required for network requests. A small public web surface handles pairing and TickTick authorization.

## Capabilities and Constraints

- TickTick is the only task service.
- The watch never stores the TickTick client secret or a production access token in source or distributable artifacts.
- Pairing, cached reads, pagination, offline completion, retry, account disconnection, and authorization expiry require explicit, recoverable states.
- A full-screen touch target is allowed only for a non-destructive, idempotent action such as starting or resuming pairing. A task must never be completed by tapping navigation chrome, empty space, or another row.
- Button-only behavior is canonical. Touch is a strict superset that adds convenience without adding a new destructive capability.
- Task completion requires a deliberate selected-task action and a distinct confirmation input. Repeating the same ambiguous tap in the same place is not confirmation.
- Any navigation or cancellation input disarms a pending completion, including while synchronization is active. No accepted input may fail silently.
- The implementation must scale across the supported Connect IQ product matrix, including compact monochrome devices and the Fenix 8 AMOLED.
- Public pages, URLs, metadata, and support routes must not expose the maintainer's personal name or personal email address.

## Brand Commitments

- Product name: TickTick for Garmin.
- Visual family: Garmin Bridge.
- Garmin Bridge palette: near-black `#1A1A1A`, soft white `#D4D4D4`, hot coral `#FD4E5A`, Klein blue `#5A5CF5`, and restrained neutral grays.
- The interface stays minimal, precise, and recognizably Garmin-native. Color communicates hierarchy and state rather than decorating every control.
- The launcher icon must be distinctive and legible at watch-launcher size, not a generic document or copied TickTick mark.

## Evidence on Hand

- Working watch app, relay, automated tests, simulator tooling, and signed release artifacts in this repository.
- A physically verified Fenix 8 pairing and task-completion flow.
- Garmin Bridge visual tokens and icon language in the sibling `garmin-voice-export` project.
- No approved testimonial, usage metric, or commercial claim. Future public copy must not invent one.

## Product Principles

1. Deliberate actions beat clever gestures.
2. The watch always explains its current state and the next available recovery.
3. Large touch targets must not create ambiguous destructive behavior.
4. Garmin-native interaction comes before visual novelty.
5. Public identity belongs to the product, not the maintainer's personal details.

## Accessibility & Inclusion

Maintain readable contrast, fit real copy without clipping, support button-only operation, avoid color-only meaning, and preserve a functional compact monochrome presentation.
