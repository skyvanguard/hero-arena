# Hero Arena (working title)

**An original, open-source, mobile-first 3v3 hero shooter.**

A spiritual successor to *T3 Arena* — not a clone: the fast, readable, small-team fun of T3's 3v3 identity, the hero depth and in-match evolution of *Overwatch*, minus the problems players complained about. Fun with **zero humans online** (smart bots), fair and fast **matchmaking with transparency**, and an architecture built so the **community can keep it alive** (open engine, dedicated servers, mods).

> Take what made T3 Arena fun, take the depth and hero design philosophy of Overwatch, eliminate the problems players complained about, and build the game as an open, extensible project.

## Status

**All roadmap phases shipped** (2026-09-06, through Phase 8) — the full
directive: 3v3 (1v1–6v6 by config) across four modes on four original maps,
six original heroes (plus one community mod), perks/progression/seasonal
cosmetics, events, matchmaking v2, AI coaching, four bot difficulties offline
and as queue fill, lobby + party-aware matchmaking, authoritative dedicated
server (docker, one command, room codes), mod support v1 with validation and
a starter community mod, and a complete doc set (architecture walkthrough
included, [docs/WALKTHROUGH.md](docs/WALKTHROUGH.md)). Open sign-off: the
real-device performance table (needs an Android device — see
docs/PERFORMANCE.md). See [docs/ROADMAP.md](docs/ROADMAP.md) for the
phase-by-phase status.

- Research complete: T3 Arena, Overwatch, open-source landscape, engine evaluation
- Engine decided: **Godot 4.7.x** (MIT) — see docs/ENGINE_DECISION.md

## Play it

- **Android:** [APK on the Releases page](https://github.com/skyvanguard/hero-arena/releases)
  (allow installing unknown apps). Offline bots and the practice range work with
  no server; online play needs a lobby + server (below).
- **Desktop (Linux x86_64):** [heroarena.x86_64.x86_64 on the Releases page](https://github.com/skyvanguard/hero-arena/releases)
  (chmod +x, run with the .pck file beside it).
- **Run a server yourself (LAN):** docker run -p 7777:7777/udp -p 7778:7778/udp
  heroarena/server — then join from the hero-select JOIN field (host:port), or
  point a lobby at it. See [docs/NETWORKING.md](docs/NETWORKING.md).

## Reporting problems

Use the [issue tracker](https://github.com/skyvanguard/hero-arena/issues) — bug
reports and feature ideas both welcome (templates included).

## Phase 0 notes (2026-09-02)


## Core promises (the product principles)

1. **3v3 first** — every player matters; 1v1–6v6 supported by configuration, not code
2. **Fun alone** — offline bot matches, training, challenges; no cloud dependency
3. **No pay-to-win** — heroes unlock at 100% power; progression is cosmetic
4. **Smart bots** — a core feature with 4 difficulty tiers, not a queue-filling apology
5. **Fast, fair, transparent matchmaking** — strict → widened → bot-filled; you see why you were placed
6. **Readable, responsive combat** — stylized 3D, hitmarkers, damage arrows, 3–8 minute matches
7. **Community-owned longevity** — open source (code Apache-2.0), dedicated servers, mods

## Documentation

| Doc | What it answers |
|---|---|
| [docs/T3_RESEARCH.md](docs/T3_RESEARCH.md) | What T3 Arena was, what it got right, what killed it |
| [docs/OVERWATCH_RESEARCH.md](docs/OVERWATCH_RESEARCH.md) | Roles/sub-roles, perks, matchmaking, progression — systems and reception |
| [docs/OPEN_SOURCE_RESEARCH.md](docs/OPEN_SOURCE_RESEARCH.md) | 17+ open-source projects evaluated (licenses verified) |
| [docs/ENGINE_DECISION.md](docs/ENGINE_DECISION.md) | Godot 4 vs Unity — full axis evaluation + risk register |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design: authoritative server, data-driven content, modules |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Phases 0–8 with exit criteria and the definition of success |
| [AGENTS.md](AGENTS.md) | Rules for AI development agents on this repo |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute (branch model, definition of done, asset-license checklist) |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | How we treat each other in the repo and the lobby |
| [docs/MOBILE.md](docs/MOBILE.md) | Android-first: touch input, D24 control customization, building, on-device measurement |
| [docs/NETWORKING.md](docs/NETWORKING.md) | The net stack: wire protocol, snapshots, lobby protocol v1.6, reconnect, suites |
| [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | Mobile frame budgets, measured baselines, the real-device table |
| [docs/WALKTHROUGH.md](docs/WALKTHROUGH.md) | Animated architecture walkthrough (regenerable headless GIF) |TECTURE.md §3.)*

## License

Code: **Apache-2.0** (see [LICENSE](LICENSE)). Assets: individually licensed (original art, CC0/CC-BY with credits) — see per-folder LICENSE-ASSETS files as the asset pipeline lands in Phase 2.

## What we are NOT

- Not a T3 Arena clone (original IP, original heroes, original maps — see T3_RESEARCH.md §8 for what we learned from it)
- Not an Overwatch reskin (we study systems, not characters)
- Not a desktop game with touch bolted on (mobile-first per ARCHITECTURE.md D1/D2)
- Not a live-service with a paywall on fun
