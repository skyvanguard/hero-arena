# Roadmap

**Status:** Phase 0 plan (compiled 2026-09-02)
**Method:** vertical slices (directive §37) — every phase ends with something *playable or runnable on the target hardware*, never months of isolated system work. Phase 0 (this) delivers research + architecture only.

---

## 0. Phase 0 — Research & Architecture (CURRENT)

**Deliverables:**
- [x] docs/T3_RESEARCH.md — T3 Arena mechanics, roster, modes, monetization, community diagnosis
- [x] docs/OVERWATCH_RESEARCH.md — roles/sub-roles, perks, matchmaking, progression, reception
- [x] docs/OPEN_SOURCE_RESEARCH.md — 17+ projects evaluated (license, engine, activity, patterns)
- [x] docs/ENGINE_DECISION.md — Godot 4.7.x selected (vs Unity 6) with risk register
- [x] docs/ARCHITECTURE.md — system overview, module map, data model, decisions log
- [x] docs/ROADMAP.md — this file
- [x] Technical recommendation presented (Godot 4, authoritative headless server, data-driven content, bots as server controllers)

**Exit criteria:** docs reviewed; engine + license decided; repo initialized (code Apache-2.0, assets CC0/CC-BY per file).

## 1. Phase 1 — Core Prototype (vertical slice)

**Goal: the smallest thing that proves the game is FUN on Android** (directive §37 checklist, verbatim):

- [x] Android build pipeline (Godot 4.7.2 headless export → signed debug APK, SDK/Java config, install verified on Android 34 emulator — `export_presets.cfg`, `docs/PERFORMANCE.md`; real-device install pending with the perf note)
- [x] 1 small 3D arena map (placeholder-quality, correct *scale* — lanes/cover/verticality) — `game/gameplay/modes/arena.gd`, headless-verified
- [x] Third-person character (capsule, movement states, coyote/buffer) — `core/state/character_entity.gd`, tested
- [x] TPS camera (drag-look, shoulder offset; fixed-offset instead of SpringArm — 4.7 rework) — `gameplay/character/hero.gd`, tested
- [x] Mobile touch controls (left move stick, right aim stick, fire, jump, reload) — `core/input/touch_controls.gd`; on-device check pending (line 36)
- [x] 1 weapon (hitscan, ammo, reload, headshot mult) — `core/combat/weapon.gd`, tested (sound pending asset pipeline)
- [x] Damage + health (HP bar, hit flash, damage numbers, regen-to-cap) — tested
- [x] Death + respawn (6 s world-clock timer, 2 s protection) — `core/state/world.gd`, tested
- [x] 1 enemy bot (search/engage/retreat, 4 difficulty param packs as data) — `gameplay/bots/bot_controller.gd`, tested
- [x] Desktop KB/mouse binding of the same input contract (dev convenience) — `core/input/desktop_input.gd`
- [x] Headless sim test harness + first gameplay tests (movement, hit, death, reload, bot) — `tests/test_main.gd`, 16/16 green
- [ ] Real-device perf note: FPS on a low-end + mid-range Android phone, memory, thermals (PERFORMANCE.md baseline)

**Exit criteria:** a person can install the APK, pick the character, run/shoot/kill the bot, die, respawn, on a real phone at ≥30 FPS. All in one 5-minute session. This is the go/no-go gate for the engine decision (D1 risk: if Godot misses the floor, revisit before Phase 2).

## 2. Phase 2 — First Hero

- [x] Original hero #1 — KESTREL (identity doc in GAME_DESIGN.md; kit live in `content/heroes/kestrel.tres`)
- [x] Hero select screen (data-driven `HeroRegistry`; roster cards + DEPLOY, touch/Enter — verified on emulator)
- [x] Data-driven hero registry (`content/heroes/registry.gd`) — adding a hero = one .tres + one line
- [x] Ability framework v1 (data-driven .tres definitions; cast/cooldown/charge) — `content/heroes/*_data.gd`, `gameplay/hero/ability_component.gd`
- [x] Ultimate with combat-driven charge (dmg dealt/taken + kills; HUD ult bar) — tested
- [x] Placeholder → original VFX + SFX for the hero's full kit — 9 synthesized original SFX (`tools/gen_sfx.gd`), kit VFX (dash/burst/ult aura), muzzle flash + gun recoil; pipeline docs in `docs/ASSET_PIPELINE.md` + `assets/LICENSE-ASSETS.md`
- [x] Animation v1 (procedural cosmetics: recoil/flash/movement-driven VFX)
- [ ] Skeletal animation set (idle/run/jump/shoot/ability/death — original, with Phase 3 models)
- [x] Hero tests headless (kit, registry, recoil, cooldowns, charge math, ability effects) — `tests/test_hero.gd`, 40/40 green

**Exit criteria:** hero #1 is *a character* — you can understand them in seconds and feel the kit in minutes. No other hero needed yet (the framework proves out on one).

## 3. Phase 3 — Hero Framework + Roster to 6

- [x] Role/sub-role passive registry (data-only: HIT_STREAK / SPRINT / ARMOR in `content/heroes/passive_data.gd`; new kind = data + one match arm) — SPRINT/ARMOR live on Blitz/Bastion; FIELD/FLEX/ZONE with heroes #4-6
- [x] Weapon framework v1 (hitscan w/ per-pellet spread + stepped projectile entities + headshot multipliers) — `core/combat/weapon.gd` (mode/pellets), `core/combat/projectile.gd`; heat/charge tables with heroes #4-6
- [x] Heroes #2–#6 (2 Assault, 1 Tank, 2 Support/Utility, 1 Controller per directive §6) — each with distinct movement/combat identity. All 6 built & tested (Blitz/Bastion/Mira/Patch/Nimbus in Phase 3 rounds 3–4); identities in GAME_DESIGN.md
- [x] Practice range (hero testing, dummy targets, timer) — offline, no cloud: `gameplay/practice/` (range builder + server-side manager), `ui/practice_hud.gd`, PRACTICE RANGE button on the select screen, 11-check headless suite (tests/test_practice.tscn) incl. the real player camera-aim path; emulator-verified end to end
- [x] Balance config system (content/balance/) — `Balance` (role bands + per-hero entry index) + `BalanceEntry` per-hero tuning multipliers (hp/damage/fire-rate/speed/ult-charge), applied server-side by HeroFactory at spawn; the headless roster test generates the DPS/TTK table from this config and enforces the config bands (baseline pass: all multipliers 1.0)
- [x] Roster tests: per-hero kit validation + DPS/TTK balance table with **config-driven role bands** (`tests/test_roster.tscn`, **all 6 heroes green** incl. support heal/boost + controller zone checks). Also enforces: one balance entry per hero + ult-charge pacing ≤ 12 kills worst-case. CC-lock: tracked (CC budget = Bastion Quake Stomp + Nimbus Ion slow, both slow-only — no locks).

**Exit criteria:** 6 heroes selectable, each feels like a different game in ≤5 minutes; practice range works fully offline; balance table generated by test.

**Status: MET (round 6).** All 6 heroes selectable from the select screen (emulator-verified, each with a distinct movement/combat identity in GAME_DESIGN.md); practice range runs fully offline (no cloud/bots, 11-check suite + device pass); the DPS/TTK balance table is generated by `tests/test_roster.tscn` from `content/balance/`. All 5 headless suites green; shipping (mobile-renderer) APK rebuilt and smoke-tested.

## 4. Phase 4 — Bot System

- [ ] Perception module (vision cones, hearing, objective/ally state, difficulty-gated info)
- [ ] Decision module (utility scoring + behavior trees; role responsibilities)
- [ ] Execution module (pathing on navmesh, cover seeking, aim with error model, ability timing)
- [ ] Team behavior (regroup, flank, protect, revive rules, callouts)
- [ ] 4 difficulty tiers (Beginner→Expert, parameter packs) + objective awareness per mode
- [ ] Bot eval harness in CI (navigation success, K/D bands, objective time, formation)
- [ ] Offline bot match (3v3 vs bots, difficulty selectable) — the "zero humans" guarantee (directive §2)

**Exit criteria:** a player can play a full offline 3v3 (self + 2 bots vs 3 bots) in TDM and Control that feels *played by someone*, with Beginner bots actually teachable and Expert bots threatening.

## 5. Phase 5 — Multiplayer

- [ ] Dedicated headless match server (same codebase; 60 Hz fixed step; session tokens)
- [ ] Net layer v1: snapshots (20–30 Hz), events (reliable), interpolation, client prediction + reconciliation, lag compensation for hitscan (100–200 ms window)
- [ ] Reconnect (drop/resume mid-match)
- [ ] Server-authority property tests (client lies rejected: damage, ammo, cooldown, movement)
- [ ] Net-sim harness: latency (50/150/300 ms) + packet loss (2/10%) profiles
- [ ] **LAN play first** (local discovery, direct connect) per directive §21
- [ ] Internet play (region table, ping display, Region/Ping/Server in UI)
- [ ] Matchmaking prototype: party-aware queue with the 4-stage strategy (strict → widen skill → widen region → bot fill) + match-found transparency panel (directive §16/§17)
- [ ] Server ops: docker image, 2-core budget measurement (PERFORMANCE.md)

**Exit criteria:** two phones on the same LAN play 3v3 with bots filling; then over the internet with bot fill at 60 s; drops/reconnects survive; property tests green.

## 6. Phase 6 — First Complete Match (FIRST MAJOR MILESTONE)

**Deliver (directive §6, verbatim):**
- [ ] 3v3 competitive + casual (TDM + Control + Capture + Escort available)
- [ ] 2 original maps (compact, lanes, cover, verticality, flanks, objectives, spawns) + map voting in lobby
- [ ] 6 heroes, fully unlockable (no power gating — directive §7)
- [ ] Bots (4 difficulties) usable offline and as queue fill
- [ ] Mobile controls (customizable HUD: position/size/sensitivity/opacity/aim settings)
- [ ] 1 complete game mode end-to-end (match flow: lobby → countdown → play → results → rewards → requeue) — the others follow from the mode framework
- [ ] Online/LAN multiplayer (from Phase 5)
- [ ] Match length 3–8 minutes (timer + kill targets tuned)
- [ ] Results screen (stats, MVP, rewards) + basic progression (account level, hero mastery, cosmetics slots)
- [ ] Real-device perf pass: low-end 30 / mid 60 on both maps (PERFORMANCE.md sign-off)
- [ ] Public demo build (APK + PC) + open issue tracker live

**Exit criteria = directive §45 "definition of success," verbatim:** a user installs the APK, launches, chooses a hero, enters 3v3 (humans or bots), moves, shoots, uses abilities, coordinates, understands the objective, dies, respawns, wins or loses, in ~3–8 minutes, smoothly on real Android.

## 7. Phase 7 — Systems

- [ ] **Perks** (in-match level 2/3, 2 choices each; data-driven; ult modifiers as extension)
- [ ] **Role/sub-role passives** tuned for the full roster (registry proven in Phase 3)
- [ ] Additional modes + map pool growth (2 more maps)
- [ ] Progression v2 (hero mastery, achievements, seasonal cosmetics — cosmetic only)
- [ ] Monetization-ready shop architecture (optional; cosmetics-only rule enforced by content schema)
- [ ] Map voting polish (anti-repetition rotation)
- [ ] Matchmaking v2 (win-probability model, grouping-advantage handling, region prioritization for LATAM)
- [ ] AI coaching (optional post-match tips from authoritative stats)
- [ ] Events framework (participation/win/objective rewards; no hero-forcing)

**Exit criteria:** perks create *choices* not just numbers (playtest metric: ≥2 different picks across 10 players on same hero); coaching tips are actionable; event runs headless in CI.

## 8. Phase 8 — Community

- [ ] Dedicated server release (docker, one command: docker run …/hero-shooter-server)
- [ ] Mod support v1 (heroes/maps/weapons/abilities/modes/cosmetics/balance drop-in; validation tool; versioned mod API)
- [ ] Custom match hosting (private servers, lobby API, room codes)
- [ ] Contribution workflow (branch model, PR templates, CODE_OF_CONDUCT, asset-license checklist)
- [ ] Docs complete (CONTRIBUTING, NETWORKING, MOBILE, PERFORMANCE all current; architecture walkthrough video or GIFs)
- [ ] First community mod published to the mod index

**Exit criteria:** a stranger can clone the repo, build, run a server, and load a community hero mod in <1 hour (measured with a volunteer, documented).

---

## Cross-Phase Guardrails

1. **Android test at every phase exit** (directive §25): no phase closes without a real-device check.
2. **Open source at every commit** (directive §32): code Apache-2.0; assets individually licensed; no proprietary dependencies without a review note.
3. **Fun is the metric** (directive §46.1): every phase ends with a playtest note (who played, what felt good, what felt bad) in the milestone doc.
4. **No scope creep without a decision log entry** (ARCHITECTURE.md §4 format).
5. **Bots are tested like players** (directive §41): CI bot eval from Phase 4 onward.
6. **3v3 stays tuned** (directive §3): any team-size change goes through balance blocks, never hardcoded.

## Milestone Timeline (indicative, not a promise)

| Milestone | Phase | Gate |
|---|---|---|
| Vertical slice on Android | 1 | go/no-go engine check |
| First hero | 2 | kit legibility |
| 6 heroes + practice range | 3 | identity test |
| Smart bots, offline 3v3 | 4 | "fun alone" guarantee |
| LAN + internet multiplayer | 5 | authority tests green |
| **First complete match (major)** | 6 | directive §45 verbatim |
| Perks/progression/coaching | 7 | choice + fairness checks |
| Community servers + mods | 8 | stranger-onboarding test |
