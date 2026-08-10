---
name: TickTick Tasks for Garmin
description: A minimal task route across Garmin watches and the Garmin Bridge pairing surface.
colors:
  surface: "#1A1A1A"
  text: "#D4D4D4"
  coral: "#FD4E5A"
  klein: "#5A5CF5"
  muted: "#A0A0A0"
  hairline: "#333333"
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
| Coral | `#FD4E5A` | Selected stop, selected route segment, confirmation, and primary action |
| Klein | `#5A5CF5` | Synced state and active-view underline |
| Muted | `#A0A0A0` | Secondary task and status copy |
| Hairline | `#333333` | Route and row separation |

Low-colour watches use Garmin's black, white, and light-grey device palette.

## Watch interaction

- A task-row tap selects only. Retapping it does nothing destructive.
- Only the separate stop node can arm completion on touch watches.
- A separate, full-width confirmation action completes the task.
- Today, Inbox, and Lists have isolated navigation bounds and remain visible together on Fenix-class screens.
- Overdue tasks are the tail of Today. Moving backward from the first current task wraps to that overdue tail, matching TickTick's single Today flow without adding a fourth tab.
- Lists opens TickTick's lists. A tap anywhere on a list row opens its tasks, and a right swipe returns to Lists.
- MENU cycles the three task destinations and Account. Account stays off the visible band so it does not compete with daily navigation.
- Navigation and safe selection remain responsive during sync and always cancel an armed action.
- Pairing is the only full-screen touch target because it is non-destructive and idempotent.
- Compact watches keep the button-first list and show `MENU views` as a visible footer.

`TaskListView.layout()` owns every drawn and tappable rectangle. Drawing and hit testing consume the same stored bounds, so the painted interface and the accepted touch area cannot drift apart.

## Responsive behaviour

Screens at or below 280 px in either dimension use the compact layout. Larger screens show the route spine, a completion gutter up to 72 px wide, and a 64 px confirmation button. Fenix-class screens show three task or list rows; smaller colour screens show two. More items scroll with the current selection. Long task and list names stay on one fitted line, with due information on its own line when present.

The Fenix composition is fixed: a large centred title, a blue sync state, three route stops, a coral selected stop and connector, subtle row dividers, and three fully labelled destinations. Selection has no chevron or second cursor.

## Public surface

The phone flow uses the same route mark and colour tokens. It identifies the product as Garmin Bridge, contains no maintainer identity or analytics, and keeps the main action coral while Klein blue remains a small navigational accent.
