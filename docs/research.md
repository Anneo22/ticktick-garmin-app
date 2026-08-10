# Research snapshot

Updated: 2026-08-05

## What Garmin apps are

Garmin Connect IQ supports five application types. This project is a device app because it needs a full interactive task interface and web communication. It is not a watch face, data field, audio provider, or glance-only widget.

Garmin's standard development path is Monkey C plus the Connect IQ SDK, product metadata, simulator, developer signing key, IQ export, and Store review. Garmin's publishing guide requires the manifest to list supported products and the exported IQ file to contain their binaries.

OAuth is standard, but keeping a service client secret inside a public watch binary is not safe. Garmin documents browser-based authenticated web services and phone handoff. This project uses a short-code relay so TickTick's client secret and encrypted access token remain server-side while the watch holds only its own random bearer.

## Existing projects

- Garmin maintains an Apache-2.0 collection of Connect IQ reference apps and libraries at <https://github.com/garmin/connectiq-apps>. It is the best open-source baseline for project patterns, not a ready TickTick client.
- Task Link is the direct commercial comparison from the supplied Garmin Store and developer links. Its developer says it supports several task providers, preserves provider order, completes or reopens tasks, browses offline, and offers a limited free tier with paid full access. This project differs by being TickTick-only, independent, and designed without a separate subscription.
- The supplied Reddit thread also records an early Inbox omission in Task Link that the developer later reported fixed. It reinforces the need to test provider semantics live instead of inferring Inbox or Today from labels.

No maintained open-source TickTick-specific Garmin watch app was found in the research pass. That is a search result, not proof none exists. The reusable open-source material is Garmin's official samples plus ordinary OAuth relay and Cloudflare Worker patterns.

## Build conclusion

LLMs can accelerate nearly all authored material, but there is no LLM-native or LLM-only Garmin standard. The defensible workflow is to let an LLM produce candidate code and let Garmin's compiler, simulator, signed export, live TickTick API, physical watch, and Store review accept or reject it.

## Sources

- Garmin app types: <https://developer.garmin.com/connect-iq/connect-iq-basics/app-types/>
- Garmin authenticated web services: <https://developer.garmin.com/connect-iq/core-topics/authenticated-web-services/>
- Garmin Store publishing: <https://developer.garmin.com/connect-iq/core-topics/publishing-to-the-store/>
- Garmin official open-source examples: <https://github.com/garmin/connectiq-apps>
- TickTick Open API: <https://developer.ticktick.com/docs/openapi.md>
- Task Link discussion supplied by the user: <https://www.reddit.com/r/ticktick/comments/1vfk5f5/ticktick_on_garmin_i_built_the_watch_app_i_wanted/>
