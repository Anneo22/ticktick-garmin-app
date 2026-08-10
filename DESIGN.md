---
name: TickTick Tasks for Garmin
description: A minimal task route across Garmin watches and the Garmin Bridge pairing surface.
colors:
  surface: "#1A1A1A"
  text: "#D4D4D4"
  coral: "#FD4E5A"
  klein: "#5A5CF5"
  muted: "#888888"
  hairline: "#666666"
typography:
  body:
    fontFamily: "Garmin system, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.55
    letterSpacing: "normal"
rounded:
  action: "12px"
spacing:
  compact: "8px"
  standard: "16px"
components:
  action-primary:
    backgroundColor: "{colors.coral}"
    textColor: "{colors.surface}"
    rounded: "{rounded.action}"
---

# Design system

TickTick Tasks uses one visual idea across the watch, pairing site, launcher icon, and Store art: a route with discrete stops. A task is a stop, navigation is separate from the route, and completion is a deliberate second action.

## Colors

| Token | Value | Role |
| --- | --- | --- |
| Surface | `#1A1A1A` | AMOLED background and icon field |
| Text | `#D4D4D4` | Primary copy |
| Coral | `#FD4E5A` | Selected stop and primary action |
| Klein | `#5A5CF5` | Status dot and active-view underline |
| Muted | `#888888` | Secondary task and status copy |
| Hairline | `#666666` | Route and row separation |

Low-colour watches use Garmin's black, white, and light-grey device palette.

## Watch interaction

- A task-row tap selects only. Retapping it does nothing destructive.
- Only the separate stop node can arm completion on touch watches.
- A separate, full-width confirmation action completes the task.
- Today, Late, and Lists have isolated navigation bounds. MENU cycles the same views.
- Navigation and safe selection remain responsive during sync and always cancel an armed action.
- Pairing is the only full-screen touch target because it is non-destructive and idempotent.
- Compact watches keep the button-first list and show `MENU views` as a visible footer.

`TaskListView.layout()` owns every drawn and tappable rectangle. Drawing and hit testing consume the same stored bounds, so the painted interface and the accepted touch area cannot drift apart.

## Responsive behaviour

Screens at or below 280 px in either dimension use the compact layout. Larger screens show the route spine, a completion gutter up to 72 px wide, and a 64 px confirmation button. Lists longer than three items show the current position and total count.

## Public surface

The phone flow uses the same route mark and colour tokens. It identifies the product as Garmin Bridge, contains no maintainer identity or analytics, and keeps the main action coral while Klein blue remains a small navigational accent.
