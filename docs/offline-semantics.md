# Offline mutation semantics

The watch is allowed to queue only operations that have a safe retry story.

- The queue is strict FIFO and contains at most eight mutations.
- Each mutation gets a stable client-generated `mutationId` before the first network attempt.
- The watch retries the same mutation ID after a watch-to-relay transport failure. The relay can then return the stored result without applying the change twice.
- If the relay reaches TickTick but cannot determine whether TickTick applied the request, it records `mutation_outcome_unknown`. The watch must not replay or optimistically remove that task. It shows an uncertain state and refreshes for reconciliation.
- The relay stores the idempotency result by relay session and mutation ID until unpairing. An applied result is safe to return again; a pending or unknown result is never replayed upstream.
- At capacity the app refuses another offline mutation and keeps the task visible. It never drops the oldest change.
- Offline completion is allowed. Offline create, edit, move, and delete remain disabled until their dependency and conflict semantics are separately proven.
- The queue drains before a foreground refresh, one request at a time. A retryable failing head blocks later mutations and the watch shows the pending count. A non-retryable or uncertain head is removed from the retry queue and surfaced for user reconciliation.

This policy favors recoverability over pretending every mutation is safe offline.
