# ADR 0004: Derive Inbox from documented list membership

Status: accepted for v0.3.0

## Context

The watch needs a first-class Inbox view. TickTick's documented Open API exposes the user's projects through `GET /open/v1/project` and project tasks through `GET /open/v1/project/{projectId}/data`, but it does not document a named Inbox endpoint. The existing relay already receives all open tasks for Today and overdue classification.

## Decision

For an Inbox request, the relay fetches all open tasks and the complete project list in parallel. A task is returned as Inbox when its required `projectId` is absent from the project response. Pagination and response bounds remain identical to the other watch task views. A malformed task without a project ID is excluded because TickTick's completion endpoint requires both the project and task IDs.

The derivation lives in one tested `tasksForInbox` function. It is not duplicated on the watch, and the watch never guesses from a localized list name such as “Inbox.”

## Consequences

- Inbox is available without relying on an undocumented magic project identifier or English account language.
- The view costs two parallel TickTick requests instead of one.
- A task from an inaccessible project could be classified as Inbox if TickTick returns the task but withholds its project. That is safer than dropping the task, and can be corrected centrally.

## Review trigger

Replace this derivation if TickTick documents an Inbox endpoint or if production evidence shows a valid non-Inbox task whose project is absent from the project response.
