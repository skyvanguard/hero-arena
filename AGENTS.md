# AGENTS.md — Development Rules for AI Agents

You are the lead game engineer and architect for this project. Follow directive §40 of the project brief, operationalized here:

## Before major implementation

1. Inspect the repository (git log, recent commits, docs/).
2. Understand the existing architecture (docs/ARCHITECTURE.md is the source of truth; update it with every architectural change).
3. Identify reusable systems before writing new ones.
4. Check dependencies — new ones need a license note in docs/OPEN_SOURCE_RESEARCH.md §2.3 rules.
5. Check licenses (code: Apache-2.0/MIT/Unlicense compatible only; assets: original or CC0/CC-BY with credits).
6. Formulate the smallest robust implementation.
7. Implement → build → test → verify Android compatibility → document.

## Standing rules

- **Never rewrite a working system without a clear reason** (record the reason in the PR/commit).
- Prefer **extending existing abstractions**; prefer composition over inheritance; prefer data-driven (content/ Resources) over hardcoding.
- **No magic numbers**: gameplay values live in content/balance/ Resources.
- **Server authority is sacred** (ARCHITECTURE.md §1): damage, kills, ammo, cooldowns, movement validity, score, objective state are computed server-side. Never trust client input beyond declared action fields.
- **Bots share the controller interface** with human clients — anything a human does, a bot does through the same entry points.
- **Team size is configuration** (1v1…6v6); 3v3 is the tuned default. Never hardcode "3 players".
- **gameplay/ must run headless.** Rendering/UI code stays in ui/ and vfx/; the sim must tick with no display (this is what makes offline mode, dedicated servers, and CI tests possible).
- **Mobile is the target** (directive §25): measure on a real Android device at every phase exit; budgets in docs/PERFORMANCE.md when it exists.
- **Small logical commits** (directive §44): feat: / fix: / docs: / test: / chore: prefixes; one system per commit where possible.
- **Update docs in the same change** that changes architecture (ROADMAP checkboxes, ARCHITECTURE decisions log).
- **Original IP only**: no proprietary assets/code/names (T3_RESEARCH.md §9 and OVERWATCH_RESEARCH.md §8 list what we studied, not what we may copy).
- **Fun > everything**: if a change makes the game less fun without a documented tradeoff, it doesn't ship.

## Definition of done (per change)

- Builds (client + headless server)
- Tests pass (headless sim tests; net-sim for networking changes)
- No new unreviewed dependency
- Docs touched where architecture changed
- Android check where gameplay input/rendering changed
