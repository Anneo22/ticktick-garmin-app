# Garmin reviewer notes draft

Status: incomplete until this exact release binary passes the physical Fenix 8 interaction check and the reviewer account procedure is ready.

The app requires a TickTick OAuth grant. On first launch, press START to create a pairing code. Open [the public pairing page](https://ticktick-garmin-relay.garmin-bridge.workers.dev/pair), enter the code, approve TickTick access, then press START on the watch again.

The app requests the Connect IQ Communications permission. It does not request Garmin health, sensor, activity, location, contacts, payment, or background permissions.

Use `<reviewer TickTick account procedure>` for review. Do not place reviewer credentials in this file or the Store listing.

Primary hardware acceptance target: fēnix 8 47 mm AMOLED. The submitted compatibility list must match `watch/device-matrix.json` and the latest successful release verification.
