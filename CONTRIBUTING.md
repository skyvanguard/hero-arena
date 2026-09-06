# Contributing

Welcome! This is a community project meant to outlive its founders — see
docs/ROADMAP.md Phase 8. This document is the human-facing contract for
contributions; [AGENTS.md](AGENTS.md) is the standing engineering ruleset
(it applies to humans too — it was written for the AI agents that build
this repo, and the same rules keep a human PR reviewable).

## Ground rules

1. **License compatibility (non-negotiable):**
   - Code: Apache-2.0 / MIT / Unlicense, or original. GPL code is
     reference-only (docs/OPEN_SOURCE_RESEARCH.md §2.3) — it may be cited in
     docs, never linked into the game.
   - Assets: original, CC0, or CC-BY with a credit entry (checklist below).
   - Every external dependency needs a review note (docs/OPEN_SOURCE_RESEARCH.md).
2. **Small logical commits**: `feat:` / `fix:` / `docs:` / `test:` /
   `chore:` — one system per commit. A PR is one logical system, not a
   week of mixed work.
3. **Server authority is sacred**: damage, kills, ammo, cooldowns,
   movement validity, score, objective state are computed on the server.
   If a PR trusts a client number for any of those, it is not ready.
4. **Balance numbers** go in `game/content/balance/` (and other content
   Resources) — not in scripts. No magic numbers in gameplay code.
5. **Original IP**: no third-party character names, maps, sounds, or art.
   Study what you need in docs/ (T3_RESEARCH, OVERWATCH_RESEARCH) and keep
   the study out of the game.
6. **Docs evolve with code**: architecture changes update
   docs/ARCHITECTURE.md (decisions log); new systems get a doc section;
   ROADMAP checkboxes flip in the same change that ships the item.

## Branch model

```
design discussion (issue)
        │
        ▼
main ────────────────────────────── always green (CI gate below)
  │  \                               ▲
  │   └── dNN-topic / feat-something │
  │         (short-lived branch,     │
  │          1 logical system,       │
  │          small commits)          │
  └────────── PR → review ───────────┘  (squash-free: small commits kept)
```

- **`main` is always releasable.** It is the tree the docker release image
  builds from, so a red main is a release incident.
- **Branch names**: `dNN-topic` for roadmap-item work (NN = the D-label,
  e.g. `d36-branch-model`), or `feat-…` / `fix-…` for free-form work.
  Branch from a fresh `main`; keep the branch alive at most a few days —
  rebase early, rebase often.
- **One PR = one logical system.** Big features land as a sequence of
  small PRs in dependency order (data before sim before UI), each of them
  independently green. If you cannot describe the PR in one sentence, it
  is two PRs.
- **Commits are kept, not squashed.** The history is part of the project
  (D-labels, round numbers, and reasoning live in messages — keep them
  there).
- **Design questions first**: anything that touches the decisions log in
  docs/ARCHITECTURE.md gets an issue before a PR. The review is about the
  decision, then the implementation.
- Maintainers merge when: CI is green, the DoD below is checked, and the
  diff matches the PR description. No force-pushes to `main`.

## Definition of done (per PR)

From AGENTS.md — a PR that cannot tick every line is not done:

- [ ] Builds: client (`--import` clean) + headless server (docker image builds).
- [ ] Tests pass: the full headless battery
  (`godot --headless --path game res://tests/test_<suite>.tscn` for every
  `tests/test_*.tscn`); net-sim runs for networking changes; bot eval
  harness green for bot changes. Net suites can flake under heavy machine
  load — re-run solo before blaming the PR (docs/NETWORKING.md §7).
- [ ] No new unreviewed dependency (license note in docs/OPEN_SOURCE_RESEARCH.md).
- [ ] Docs touched where architecture changed (ROADMAP checkbox, ARCHITECTURE
  decisions log, the system's doc section).
- [ ] Android check where gameplay input or rendering changed — ideally a
  real device; an emulator note is a start, a device note is the standard
  (docs/PERFORMANCE.md budgets).

## Verification commands (what CI runs, run it locally first)

```bash
G=/path/to/Godot_v4.7.2-stable_linux.x86_64

# 1. all-scripts compile gate (catches parse errors across the project)
cd game && $G --headless --path . --import

# 2. the test battery (one headless process per suite; exit code = fails)
for f in game/tests/test_*.tscn; do
  timeout 400 $G --headless --path game res://$f || echo "FAIL $f"
done

# 3. dedicated-server release gate (real ENet client through a published port)
docker build -f server/Dockerfile -t heroarena/server .
docker run -d --name ha-smoke -p 7777:7777/udp -p 7778:7778/udp heroarena/server
$G --headless --path game res://tools/docker_smoke.tscn   # expect SMOKE PASS
docker rm -f ha-smoke

# 4. mod drop-ins (if the PR touches mods/)
$G --headless --path game res://tools/validate_mods.tscn   # exit code = issues
```

## Asset-license checklist

Every asset that is **not** created in this repo must pass this checklist
before it lands. The checklist is enforced at PR review; the artifacts it
points at (credit file, provenance line) are what the reviewer checks.

1. **What is the license?** Only: original (created for this repo), CC0,
   or CC-BY. (Code-asset hybrids — e.g. shader or audio tools — follow the
   code rules above.) Anything else: reference-only, lives in docs/.
2. **Where is the credit?** CC-BY requires attribution:
   - a row in the provenance ledger `assets/LICENSE-ASSETS.md`
     (asset, path, license, provenance: author + source URL + access
     date) — every asset in the repo is in that table, keep it true, and
   - the in-game credits screen for anything the player sees or hears
     (ui/ credits overlay — add the row in the same PR).
3. **Is the file clean?** No embedded metadata naming another game, no
   filenames with third-party trademarks, no reskinned third-party meshes
   (a reskin of a proprietary asset is a derivative work — original IP
   rule, ground rule 5).
4. **Is the dependency noted?** If the asset came from a library/tool
   (e.g. a font from an open collection), the tool gets a row in
   docs/OPEN_SOURCE_RESEARCH.md §2.3 with its license and why it is
   compatible.
5. **Provenance line in the PR**: "assets: <n> original, <n> CC0
   (<where>), <n> CC-BY (<who, where credited>)" — one line, no ambiguity.

## Mods vs core

- **Core** (sim, net, UI, engine glue) changes follow the full DoD above.
- **Drop-in mods** (heroes/maps/modes/cosmetics/balance entries in
  `game/mods/<id>/`) follow a lighter path: manifest valid (API version
  within `ModLoader.API_VERSION`), `tools/validate_mods.tscn` clean,
  `tests/test_mods.tscn` green, and the roster/map harnesses pass with the
  mod loaded. See docs/MODS.md for the layout rules.
- The **mod API is versioned and additive-only** (D34): a PR that changes
  what a mod file may contain bumps `API_VERSION` and documents the delta
  in docs/MODS.md — that is a decisions-log change, so issue first.

## What a good PR looks like

```
title:  feat: D36 contribution workflow (branch model, PR template, CoC)
body:   one-sentence summary.
        what was tested: <battery count, docker smoke, device if mobile>
        docs touched: <files>
checklist: every DoD box ticked with the evidence next to it
```

The PR template (`.github/pull_request_template.md`) ships this checklist
pre-filled — don't delete boxes you skipped, mark them "n/a: why".
