# Watch-relay contract v1

All watch-facing responses use a small JSON envelope:

```json
{"ok":true,"data":{}}
```

or:

```json
{"ok":false,"error":{"code":"stable_code","message":"short human message","retryable":false}}
```

Rules:

- Timestamps are ISO 8601 strings with an explicit offset or `Z`.
- Missing optional values are omitted, not sent as `null`.
- Task lists are paginated and capped by the relay. The watch never downloads an unbounded account dump.
- Opaque relay tokens and device secrets are never written to fixtures or logs.
- The relay exposes named operations, not an arbitrary TickTick URL proxy.

## Pairing

`POST /v1/pair/start` creates a ten-minute pairing attempt. The watch stores the high-entropy `deviceSecret` until pairing finishes and shows `userCode` plus `verificationUrl` to the user.

`POST /v1/pair/status` accepts the device secret. Pending and paired responses are safe to retry. The device secret becomes the relay bearer after approval, while the relay stores only its hash.

## Tasks

`GET /v1/tasks?view=today&utcOffsetMinutes=60&cursor=...` returns a bounded task page using the watch's local UTC offset and the task due date, falling back to its start date. Supported views begin with `today`, `overdue`, and `project`. The relay preserves TickTick's upstream list order. The watch treats the last-task-ID cursor as opaque and requests it at the end of a loaded page. If that anchor disappears, the relay rejects the stale cursor rather than silently skipping or reordering tasks. Inbox is not promised until a public TickTick API representation is proven.

`POST /v1/tasks/{taskId}/complete` is the only v0.1 mutation. It includes a client-generated `mutationId` so retries can be idempotent at the relay boundary. Create, edit, move, delete, and reopen are deliberately absent until their watch interaction and conflict semantics are proven.
