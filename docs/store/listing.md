# Connect IQ Store listing draft

## Name

TickTick Tasks

## Short description

Read and update TickTick tasks from a compatible Garmin watch, with a small offline cache and no third-party subscription.

## Description

TickTick Tasks puts the task list you already use on your Garmin watch. Pair your TickTick account once, then browse Today, overdue, and project task lists, complete tasks, and refresh when you need the latest state.

The app keeps a bounded local cache and can queue safe completions when the connection drops. Pending changes stay visible and retry in order. The watch talks to a narrow TickTick relay that protects the OAuth client secret and exposes only named task operations.

The first release supports compatible Connect IQ watches that pass the compiler and simulator evidence. It is designed for button navigation and Garmin's mapped touch actions across AMOLED, MIP, round, semiround, and rectangular screens. Older Garmin watches without the required Connect IQ APIs or memory are not supported.

TickTick Tasks is free, contains no ads or analytics, and does not require another task-service subscription. A TickTick account is required. This independent app is not affiliated with TickTick or Garmin.

## Release features

- Pair and unpair through a short code.
- Browse Today, overdue, and projects.
- Use buttons, swipes, or isolated touch targets without turning navigation taps into task completion.
- Browse bounded pages of tasks and complete with two-step confirmation.
- Cache a bounded page and show offline or pending state.
- Retry safe mutations without applying them twice.
- Unpair from the watch with an explicit warning when pending completions will be discarded.

## Claims still blocked before submission

- Physical Fenix 8 button and touch acceptance.
- Live TickTick OAuth and Today-filter acceptance against a production relay.
