# Hero Arena (working title)

**An original, open-source, mobile-first 3v3 hero shooter.**

A spiritual successor to *T3 Arena* — not a clone: the fast, readable, small-team fun of T3's 3v3 identity, the hero depth and in-match evolution of *Overwatch*, minus the problems players complained about. Fun with **zero humans online** (smart bots), fair and fast **matchmaking with transparency**, and an architecture built so the **community can keep it alive** (open engine, dedicated servers, mods).

> Take what made T3 Arena fun, take the depth and hero design philosophy of Overwatch, eliminate the problems players complained about, and build the game as an open, extensible project.

## Status

**Phase 0 — Research & Architecture** (2026-09-02)

- Research complete: T3 Arena, Overwatch, open-source landscape, engine evaluation
- Engine decided: **Godot 4.7.x** (MIT) — see docs/ENGINE_DECISION.md
- Next: Phase 1 vertical slice (Android + map + character + camera + touch + weapon + damage + death/respawn + 1 bot)

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
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute (license rules, commit style) |

*(NETWORKING.md, MOBILE.md, PERFORMANCE.md, GAME_DESIGN.md grow from Phase 1 onward — see ARCHITECTURE.md §3.)*

## License

Code: **Apache-2.0** (see [LICENSE](LICENSE)). Assets: individually licensed (original art, CC0/CC-BY with credits) — see per-folder LICENSE-ASSETS files as the asset pipeline lands in Phase 2.

## What we are NOT

- Not a T3 Arena clone (original IP, original heroes, original maps — see T3_RESEARCH.md §8 for what we learned from it)
- Not an Overwatch reskin (we study systems, not characters)
- Not a desktop game with touch bolted on (mobile-first per ARCHITECTURE.md D1/D2)
- Not a live-service with a paywall on fun
