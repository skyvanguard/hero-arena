# Contributing

Welcome! This is a community project meant to outlive its founders — see docs/ROADMAP.md Phase 8.

## Ground rules

1. **License compatibility (non-negotiable):**
   - Code: Apache-2.0 / MIT / Unlicense, or original. GPL code is reference-only (docs/OPEN_SOURCE_RESEARCH.md §2.3).
   - Assets: original, CC0, or CC-BY with a credit entry in the folder's LICENSE-ASSETS file.
   - Every external dependency needs a review note (docs/OPEN_SOURCE_RESEARCH.md).
2. **Read AGENTS.md** — it defines how this repo is developed (it applies to humans too).
3. **Small logical commits**: feat: / fix: / docs: / test: / chore: — one system per commit.
4. **Tests**: gameplay changes need headless sim tests; networking changes need net-sim runs; bot changes need the bot eval harness to stay green.
5. **Docs evolve with code**: architecture changes update docs/ARCHITECTURE.md; new systems get a doc section.
6. **Balance numbers** go in game/content/balance/ — not in scripts.
7. **Original IP**: no third-party character names, maps, sounds, or art (study what you need in docs/, keep it out of the game).

## Workflow

- Fork or clone; branch from main; open a PR with a short summary + what was tested (platform, device for mobile changes).
- CI runs headless tests on Linux; mobile verification is done by maintainers (or you — a real-device note in the PR is gold).
- Design questions: open an issue first for anything that touches docs/ARCHITECTURE.md's decisions log.
