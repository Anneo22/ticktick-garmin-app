# Development and LLM boundary

There is no standardized way to build and publish a Garmin app entirely through LLMs.

The standardized parts are Garmin's Connect IQ project structure, Monkey C compiler, product metadata, simulator, developer signing key, IQ export, compatibility selection, and Store review. The TickTick side adds its documented OAuth and Open API contract. This repository turns those authorities into reproducible scripts and tests:

1. `scripts/discover-watch-devices.mjs` derives candidates from installed Garmin metadata.
2. `scripts/verify.sh` validates fixtures, type-checks and tests the relay, compiles every included product, and runs watch tests at the primary and minimum-memory targets.
3. `scripts/package.sh` reruns the verification and creates the signed IQ package.
4. The maintainer's local, untracked `STATE.md` keeps credentials, physical hardware, public URLs, and Store review visible as external acceptance gates.

An LLM can write code, generate tests, inspect simulator output, compare contracts, review security boundaries, and prepare Store material. It cannot legitimately replace:

- TickTick and Garmin developer accounts or credentials.
- Live confirmation of TickTick's provider behaviour.
- Physical-watch transport and input testing.
- Garmin's compiler, signing/export checks, or Store review.

The useful standard is therefore not "LLM-only." It is evidence-driven automation where generated work is accepted only by independent compilers, tests, live services, hardware, and reviewers.
