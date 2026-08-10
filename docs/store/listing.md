# Connect IQ Store listing draft

## Name

TickTick Tasks

## Short description

Read and update TickTick tasks from a compatible Garmin watch, with a small offline cache and no third-party subscription.

## Description

TickTick Tasks puts the task list you already use on your Garmin watch. Pair your TickTick account once, then browse Today, Inbox, Lists, and the tasks inside each list. Overdue tasks sit behind Today and appear when you scroll backward from the first task. Complete a task with a separate confirmation, or refresh when you need the latest state.

The app keeps a bounded local cache and can queue safe completions when the connection drops. Pending changes stay visible and retry in order. The watch talks to a narrow TickTick relay that protects the OAuth client secret and exposes only named task operations.

The first release supports compatible Connect IQ watches that pass the compiler and simulator evidence. It is designed for button navigation and Garmin's mapped touch actions across AMOLED, MIP, round, semiround, and rectangular screens. Older Garmin watches without the required Connect IQ APIs or memory are not supported.

TickTick Tasks is free, contains no ads or analytics, and does not require another task-service subscription. A TickTick account is required. This independent app is not affiliated with TickTick or Garmin.

## Release features

- Pair and unpair through a short code.
- Browse Today, Inbox, Lists, and the tasks inside each list, with overdue tasks behind Today.
- Keep Today, Inbox, and Lists visible together on wide watches; tap, swipe, or use the watch buttons.
- Use buttons, swipes, or isolated touch targets without turning navigation taps into task completion.
- Browse bounded pages of tasks and complete with two-step confirmation.
- Cache a bounded page and show offline or pending state.
- Retry safe mutations without applying them twice.
- Unpair from the watch with an explicit warning when pending completions will be discarded.

## Claims still blocked before submission

- Physical Fenix 8 acceptance of this exact redesigned release binary.

Live TickTick OAuth, Today sync, and task completion have been accepted against the production relay on a Fenix 8. The final redesigned binary still needs one physical interaction pass before Store submission.
