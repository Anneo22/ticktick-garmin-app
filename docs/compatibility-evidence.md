# Compatibility evidence

Updated: 2026-08-10

The compatibility claim is deliberately narrower than "every Garmin watch." The app targets Garmin products whose SDK metadata supports Connect IQ watch apps, Connect IQ API 2.4 or newer, and at least 96 KiB of application memory.

## Automated evidence

- Garmin SDK: 9.2.0.
- Discovered and compiled SDK products: 126.
- Screen families represented in metadata: 17.
- Minimum compiled API: 2.4.2.
- Minimum compiled application memory: 98,304 bytes.
- Garmin signed export variants: 220.
- Monkey C tests: 61 on Fenix 8 47 mm and 61 on Instinct 2S.
- Release tests are kept out of the production source path so Toybox.Test cannot enter Store binaries.

The exact product set is generated in `watch/device-matrix.json`. `scripts/verify-matrix.sh` compiles every listed SDK product rather than extrapolating from a few screen sizes.

## Manual simulator rendering

Clean launch and task-list rendering were inspected on:

- Fenix 8 47 mm AMOLED, primary target.
- Instinct 2 and Instinct 2S, including the 98,304-byte floor and cutout display.
- Forerunner 735XT, semiround.
- vivoactive HR, narrow rectangle.
- Venu X1, large rectangle.

These checks prove clean launch and layout rendering on representative profiles. They do not prove every physical button mapping, touch gesture, phone transport, live OAuth flow, or TickTick provider response. Those claims remain blocked until live and physical acceptance is complete.

The current interaction pass also inspects a 454 px Fenix task list, its separate completion confirmation, a 163 x 156 Instinct 2S fallback, and synthetic 215 x 180 semiround geometry. The layout tests prove that task rows, completion nodes, navigation, and action buttons do not overlap on representative square and semiround sizes.

## Compatibility policy

A device may be included only if the official compiler accepts the production app for that product and the APIs and memory it needs remain within the declared floor. A model that cannot run Connect IQ watch apps cannot be supported. A compiler pass is necessary but does not overrule a reproducible runtime defect.
