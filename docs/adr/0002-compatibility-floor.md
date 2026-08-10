# ADR 0002: compatibility follows API and memory evidence

Status: accepted, 2026-08-05

## Decision

The source compatibility floor begins at Connect IQ API 2.4 because the app uses `Application.Storage` and `Application.Properties`. Store products are enabled only after the official SDK compiles them and the representative simulator matrix passes.

Background refresh is an optional product capability, not a condition for installing the app. The foreground task path remains complete without it.

## Why

Garmin devices span incompatible API levels, screen shapes, input methods, heaps, and storage budgets. Claiming every Garmin watch is false. API 2.4 preserves a large older-device surface while providing the object store needed for an offline cache. Responses are capped at 16 KB, below the documented 32 KB per-value storage ceiling, and pages contain at most 20 tasks.

## Consequences

- Some old Connect IQ watches and all non-Connect-IQ devices are excluded.
- Low-memory products may require a smaller task page and queue cap through resource overrides.
- Exact product IDs come from installed Garmin device metadata. They are never guessed from marketing names.

## Review trigger

Raise the floor only when compiler or simulator evidence shows the lower tier cannot implement the release-critical task path safely.
