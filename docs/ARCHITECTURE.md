# Architecture

**Status:** Phase 0 design (compiled 2026-09-02)
**Engine:** Godot 4.7.x (see ENGINE_DECISION.md) · **Primary language:** GDScript (C# for measured hot paths) · **Model:** authoritative server, same codebase headless
**Scope:** this doc defines the system architecture, module boundaries, data model, and key decisions. Detailed networking is in NETWORKING.md (to be expanded in Phase 5), performance in PERFORMANCE.md, gameplay numbers in GAME_DESIGN.md (Phases 1–2).

---

## 1. System Overview

text:
  Player (Android/PC)
    │  input (touch/KB)            ▲  rendering + feedback
    ▼                              │
  Client (Godot, renderer ON)
    │  actions (predicted)         │  snapshots (interpolated)
    │  state queries               │  events (damage, kill, VFX cues)
    ▼                              ▼
  Network (ENet reliable/unreliable, WebRTC for future)
    │
    ▼
  Match Server (Godot, headless, 1 process per match)
    │  authoritative simulation @ 60 Hz (fixed timestep)
    ▼
  Match State: players, bots, heroes, weapons, abilities, objectives, mode logic

  Services (outside match process, Phase 5+):
    - Lobby/Matchmaking service (queue strategy, bot fill, regions)
    - Account service (local-first; optional cloud sync)
    - Content registry (heroes/maps/modes/perks — data-driven, moddable)

Invariants (directive §21 — "never trust clients"):
- Damage, kills, ammo, cooldowns, movement validity, score, objective state: **server-authoritative**.
- Clients send **inputs/actions** (move vector, aim, fire events, ability casts, reload). They may **predict** locally for feel; the server reconciles (see NETWORKING.md).
- Bots run **server-side** in the same simulation (a bot is just a controller feeding the same interfaces a human client uses — this guarantees human/bot parity, critical for the bot-as-feature goal).

## 2. Repository Layout (Godot-adapted)

text:
  /
  ├── AGENTS.md                 # AI development rules (from directive §40)
  ├── README.md                 # project overview + quickstart
  ├── LICENSE                   # code license (Apache-2.0, decided in Phase 1 commit)
  ├── CONTRIBUTING.md
  ├── docs/
  │   ├── T3_RESEARCH.md  OVERWATCH_RESEARCH.md  OPEN_SOURCE_RESEARCH.md
  │   ├── ENGINE_DECISION.md  ARCHITECTURE.md  ROADMAP.md
  │   ├── NETWORKING.md  MOBILE.md  PERFORMANCE.md  GAME_DESIGN.md
  ├── game/                     # THE Godot project (client + server share this tree)
  │   ├── project.godot
  │   ├── core/                 # engine-agnostic-ish foundations
  │   │   ├── net/              # transport, snapshot codec, prediction, reconciliation
  │   │   ├── state/            # entity state, fixed-timestep world, events bus
  │   │   └── util/             # pools, math, config loading, save/load
  │   ├── gameplay/
  │   │   ├── character/        # base ThirdPersonCharacter, animation, movement
  │   │   ├── combat/           # weapons, damage pipeline, status effects, hit registration
  │   │   ├── abilities/        # ability framework (casts, projectiles, zones, ult)
  │   │   ├── heroes/           # hero definitions + per-hero scenes (data-driven)
  │   │   ├── bots/             # controller stack: perception→decision→execution, difficulty
  │   │   ├── modes/            # mode rules (TDM, Control, Capture, Escort, Clash-like)
  │   │   └── objectives/       # objective entities (points, crystals, payload)
  │   ├── content/              # DATA-DRIVEN content (Resources/.tres + JSON exports)
  │   │   ├── heroes/  weapons/  abilities/  perks/  roles/
  │   │   ├── maps/   modes/    balance/
  │   ├── ui/
  │   │   ├── hud/              # in-match HUD (health, ammo, abilities, objective)
  │   │   ├── touch/            # virtual joystick, buttons, customizable layout
  │   │   └── menus/            # main, hero select, settings, results
  │   ├── audio/  vfx/  characters/  maps/  (asset folders, separately licensed)
  ├── server/                   # dedicated-server build config, docker, ops tooling
  │   ├── Dockerfile  compose.yaml  regions.yaml
  ├── mods/                     # community content drop-in (Phase 8)
  │   ├── heroes/  maps/  weapons/  abilities/  modes/  cosmetics/  balance/
  └── tests/                    # headless Godot tests (GUT or built-in), net sim, bot eval

Rules:
- gameplay/ must run identically headless (no rendering-only code outside ui/vfx).
- All balance numbers live in content/balance/ (Resources) — no magic numbers in logic.
- mods/ mirrors content/: a mod is a folder that overrides/adds data (+ optional scripts with a versioned API).

## 3. Core Modules

### 3.1 Fixed-timestep World (core/state)

- Authoritative simulation ticks at **60 Hz** (server), deterministic-adjacent: same inputs → same state (we do not require full determinism, but we require *idempotent* actions with sequence numbers for reconciliation).
- Entities: CharacterEntity (player or bot), ProjectileEntity, ZoneEntity, ObjectiveEntity, PickupEntity, VFX cue. Each has:
  - "state" (serializable snapshot fields),
  - "inputs" (what a controller may send),
  - "events" (emitted for clients: hit, kill, ability_cast, objective_change, respawn).
- Event bus: server publishes typed events; net layer forwards them to clients (reliable channel for game-meaningful events, unreliable for cosmetic).

### 3.2 Character & Movement (gameplay/character)

- Base ThirdPersonCharacter (pattern from gdquest-demos/tps-demo, rebuilt original): capsule body, grounded/airborne states, coyote time, jump buffering, slope handling, air control.
- **Role passives and sub-role passives attach as components** (data-driven, §3.5) — core movement code never special-cases a hero.
- Per-hero movement identity (dash, double jump, flight, slide) = movement components configured by the hero definition.
- Mobile input contract: left stick (move), right stick (aim/camera), discrete buttons (jump, reload, ability1/2, ult, interact). Input abstraction makes desktop (KB/mouse) a second binding of the same contract.

### 3.3 Combat (gameplay/combat)

- Weapon model (per hero, from T3 research: every hero has a unique primary):
  - Hitscan (instant raycast, server validates against interpolated positions) or Projectile (spawn ProjectileEntity; client-side lead assist optional).
  - Ammo/reserve, reload timing, weapon heat/charge where applicable (Sharpshooter-style data tables — OW research §2.2), fire modes, headshot multipliers, critical rules.
- Damage pipeline (server): source → target → armor/shield split → modifiers (role passives, perk multipliers, status effects, zone effects) → final damage → HP → death check → event.
- HP/armor: **regen-to-cap after N seconds without damage + map health pickups** (T3 pattern, §8.12); overhealth (armor) for tanks.
- Status effects: data-driven (slow, burn, shield, stun, knockback with impulse, invisibility) with durations/stacking rules in content/balance.
- Crowd control budget: CC durations are global config (prevent CC-lock; documented in GAME_DESIGN.md when numbers are set).
- Respawn: configurable timer (target 5–10 s), spawn protection window, objective-aware spawn logic (never spawn on top of the enemy team).
- Kill feed, damage arrows, hitmarkers, elimination feedback — client-side feedback system listening to server events (§3.9 UI).

### 3.4 Ability Framework (gameplay/abilities)

A unified, data-driven framework; heroes are *compositions*, not code:

- Ability definition (.tres Resource):
  - id, hero(s), type (active/ult/passive/projectile/zone/movement/buff),
  - cost (cooldown / ammo / charge / resource),
  - parameters (radius, duration, damage, impulse, projectile speed…),
  - effects list (damage, heal, cc, buff, spawn_projectile, spawn_zone, teleport/dash, shield),
  - tags (for perk targeting, bot decision, cooldown-grouping),
  - i18n strings + VFX/SFX refs.
- Ultimate: **combat-driven charge** (damage dealt + healing, T3/OW pattern), global max, charge modifiers (e.g., support role passive from assists — data-driven, §3.5).
- Passive: always-on components (movement modifiers, damage modifiers, trigger-based: on_kill, on_damage_taken, on_level_up).
- **Perks (directive §8, OW model):** in-match level 1→2 (minor) →3 (major); each level offers **2 choice cards**; choice modifies ability parameters (e.g., projectile speed, reload speed, duration, +effect). Perks are **data**: a perk = a patch applied to an ability/weapon parameter table. Optional modifiers (ult modifiers) extend the same mechanism. Data-driven ⇒ trivially extensible and balance-testable headless.
- **Role / sub-role passives (directive §9):** a registry maps (role, sub_role) → passive component definitions. New role passives = new data, zero core-combat changes (OW sub-role proof: §2.2 of OVERWATCH_RESEARCH).

### 3.5 Hero Definition

- Hero = Resource referencing: role + sub_role, weapon id, ability ids (active1, active2, ult, ult2?, passive), movement components, kit balance block, cosmetic slots (original art only).
- Roster launch: **6 heroes** (2 Assault, 1 Tank, 2 Support/Utility, 1 Controller — per directive §6), each with a distinct movement/combat identity. Identities designed in GAME_DESIGN.md (Phase 2); the *shape* of the kit (weapon + passive + actives + ult + movement identity) is fixed by this architecture.
- No per-hero power levels: unlock = full kit (directive §7). Cosmetics attach at render level only.

### 3.6 Bots (gameplay/bots) — core feature, not placeholder

Server-side controller stack (identical interface to a human client):

text:
  Perception → Decision → Execution → Memory
  (vision/hearing/ (utility scoring +  (movement, aim,  (last seen,
   objective state,  behavior trees    ability timing,   teammate/enemy
   ally state,      per difficulty,   cover seeking,    intentions, own
   own state)       team roles)       objective pursuit)  cooldowns)

- **Objective-aware**: bots score behaviors against the *current mode's* goal (hold point / push payload / kill count), not just "seek enemies" — directive §13.
- **Team behavior**: role-based responsibilities (tank holds space, support stays with group + heals, controller denies, assault trades), regroup/flank logic, revive/protect rules, callouts via the same event bus players hear.
- **Difficulty tiers** (Beginner → Normal → Advanced → Expert) = parameter packs: reaction time, aim error, decision depth, objective weight, info (beginner bots see less — fair by design). Tiers are *data*.
- **Bot difficulty also scales with population**: offline mode = full bot match; online queue fill = mixed, always labeled to the player (transparency, §17).
- Evaluation harness: headless bot-vs-bot and bot-vs-player match runner producing stats (objective time, K/D, ability usage) for CI regression (directive §41).

**As built (Phase 4, round 7):** `BotController` (gameplay/bots/) composes
`BotPerception` + `BotDecision` as children and is added to the hero exactly
like a human input source — `setup(hero, target, world, difficulty)` +
`step(world, dt)`, driven inside `CharacterEntity.step` so bots need no
external pulse. Perception: per-tick vision cone (FOV + range + LOS raycast
against LAYER_WORLD|BODY|HEAD) plus hearing from the world `shot` event,
keeping a `known` table (last position + time) pruned after ~8× the
difficulty's `lost_sight_timeout`. Decision v1 is an intent ladder
(RETREAT → ATTACK → INVESTIGATE → REGROUP → HOLD) with role multipliers
(tank: closer + holds the line; support: regroups harder, fights at range)
and a **retreat-confirmation window** (`retreat_confirm` seconds below
`retreat_hp` before committing, re-engage at `retreat_hp + 0.15`) — without
it, per-tick retreat at the threshold made bots mathematically unkillable by
focused fire. Execution: strafe cadence + approach/hold at a role-biased
fight range; aim error is an **angular** cone (direction rotated by a random
deviation ≤ `aim_error_deg`, resampled at 5 Hz) aimed from head height
(`CharacterEntity.AIM_HEIGHT`) — a fixed meter offset made accuracy
independent of range; auto-reload (`start_reload()` when the clip is dry in
combat, pre-load out of combat). Difficulty packs are `BotDifficulty`
Resources in `content/balance/bots/` (reaction, aim_error_deg, ranges,
strafe, vision/hearing, lost-sight timeout, scan speed, ability_quality,
grouping threshold, retreat parameters) selected via `BotDifficulties.by_id`
and exposed in the UI through the `MatchConfig` autoload (`difficulty`,
`team_size`). Eval harness: `tests/test_bots.tscn` (13 checks incl. live 3v3
"kills happen" and expert-out-K/Ds-beginner). Two core-system fixes came out
of the bot eval: (1) the head hitbox is a **StaticBody3D** (`HeadSensor`)
— Godot 4.7 `intersect_ray` does not report `Area3D`, so an Area head made
heads unhittable and headshots silent; headshot detection walks the collider
chain for `HeadSensor` (`CharacterEntity.hit_is_head`); (2) ray queries must
exclude the *whole character* (`CharacterEntity.own_rids()` = body + head
sensor) — a query started inside the shooter's own head sensor blocked all
LOS. See PERFORMANCE.md for the HUD 2D-canvas memory rule (write-on-change +
pooled kill feed) that 3v3 runs required.

Team behaviors v1 (round 8): **flank spread** (bots sharing a target offset
their ATTACK goal laterally by `flank_spacing` × rank, rank = distance to
target, so a squad doesn't stack on one line of fire) and **stick/protect**
(an idle bot more than `stick_range` from an in-combat ally — attacking, or
took damage < 2 s — REGROUPs toward it). Both are data-driven (difficulty
pack) and headless. TDM **match end** lives in the authoritative `World`
(first of: a team reaching `target_score`, or the `match_duration` clock;
`match_over` emitted once, sim freezes after) with pacing values in
`MatchConfig` (directive §6: 3–8 min matches). The client renders a results
overlay (VICTORY/DEFEAT/DRAW + score + duration) whose own background takes
the dismiss tap — the in-match touch layer's STOP full-rect zones would
otherwise swallow it.

### 3.7 Modes (gameplay/modes) — pluggable rules

- IMode interface: on_match_start / on_tick / on_event / win_condition / scoring / respawn_policy / spawn_logic.
- Launch modes: **Team Deathmatch** (kill target), **Control** (hold to %), **Capture Point** (multi-point sequence), **Escort/Payload**. Architecture: a mode is data + a rules script; new modes = new folder in content/modes (+ optional script).
- Team size is a **configuration** (1v1…6v6), not code: spawn counts, objective sizing, and balance blocks are parameterized by team size (directive §3). 3v3 is the tuned default; other sizes ship when balance blocks exist.
- **Map voting** (directive §24): lobby-level feature (weighted vote + rotation to avoid repetition), mode-agnostic.

### 3.8 Maps

- Launch: **2 maps**, compact (T3-scale), multi-lane, cover, verticality, flank routes, readable sightlines, objective space, distinct spawn points (directive §23).
- Map = scene + config: spawn points per role, objective anchors, pickup placement (health potions — T3 pattern), navmesh (bots + AI pathing), cover points (bot decision data), readout for mobile (visual density limits).
- Nav data is precomputed and versioned with the map.

### 3.9 UI / Touch (ui/)

- **Mobile-first HUD** (directive §11, §27): left virtual joystick, right aim stick, fire/ability1/ability2/ult/reload/jump/interact buttons — all **repositionable/resizable** (persisted layout), sensitivity/opacity/aim settings, per-device aspect handling (notch, safe areas, landscape-first).
- HUD shows: HP/armor, ammo, ability cooldowns + ult charge, objective state + direction, teammate pips/health, enemy indicators, kill feed, damage arrows, hitmarkers — clean and glanceable (readability priority).
- Menus: main (Play/Practice/Heroes/Settings/Community), hero select (role filter, hero intro), results (stats + rewards + coaching tips), settings (controls, audio, graphics presets, aim, region/ping display).
- **AI coaching (directive §14, optional, Phase 7+):** post-match analysis from server-side stats (objective participation %, deaths vs team, ability uptime) → short text tips. Computed server-side (stats are authoritative), rendered client-side.

### 3.10 Networking (summary — detail in NETWORKING.md)

- Transport: Godot high-level multiplayer (ENet) to a dedicated headless server; WebRTC path reserved.
- **Snapshots** @ 20–30 Hz (unreliable-ordered): entity positions, rotations, HP, ammo, cooldown states, objective states.
- **Events** @ reliable: casts, hits, kills, objective changes, respawns, perk unlocks.
- **Client prediction** for local movement + fire rate; **reconciliation** on snapshot arrival; **interpolation** (~100 ms buffer) for remote entities; **lag compensation** (server rewinds 100–200 ms for hitscan validation); **hit validation** with per-player tolerance (aim-assist-eligible windows).
- **Reconnect**: session token + state resync (full snapshot + recent events).
- **Matchmaking** (lobby service): party-aware queue (directive §15/§16) — strict skill+latency → widen skill → widen region → **bot fill at 60 s+** (configurable thresholds); displays Region/Ping/Server/skill band/party composition on match found (§17).
- **As-built v1 (round 9, detail in NETWORKING.md):** transport = ENetMultiplayerPeer driven through Godot 4.7 `SceneMultiplayer` (a RefCounted MultiplayerAPI — not a Node; requires `set_root_path` + manual `poll()`); own wire codec (magic-byte dispatch, LE, f32 bit codec); humans are server-side `NetPlayerController` instances (controller parity with bots, D3); client views are physics-invisible (shared physics space in loopback).
- **As-built v1.1 (round 10, detail in NETWORKING.md):** protocol v2 (hello session u32, slot token u32 + match-over result, input time_est f32); **server input sanitization + u16 wrap-aware seq gate** (move/aim clamped, stale frames and stale edges dropped — property-tested); **lag-comp hitscan** = single `world.hitscan()` truth (current physics ray + analytic 3-sphere rewind over a 60 Hz pose history, window 200 ms, delay from client time_est); **client prediction** = private World + twin character driven by the real NetPlayerController from the same 20 Hz samples (D3 parity extended client-side) with hard-snap reconciliation above 0.35 m; **reconnect** = slot freeze + token reattach (same CharacterEntity) with bounded client retry; **SimLink** = swappable transport (per-direction latency/loss) for the net-sim suite (150 ms RTT + 2% loss green). LAN discovery + internet: later Phase 5 rounds.
- **Regions**: initial SA/NA/EU/AS with LATAM priority (directive §18); regions.yaml + latency table in server ops; client shows per-server ping.

### 3.11 Offline & Community (directive §19/§20)

- **Offline = same client + local headless server in-process** (one binary, "local match" mode): training, bot matches, tutorials, challenges, practice range — zero cloud dependency.
- **LAN**: local server discovery + direct connect (Phase 5 first, per directive "start with LAN testing").
- **Dedicated/community servers** (Phase 8): docker image (server/Dockerfile), one container per match, simple API (create/join/list), mod folder mount — the community can run the game forever.

### 3.12 Content Pipeline & Modding (directive §31)

- Every content item (hero, weapon, ability, perk, map, mode, balance block, cosmetic) is a **Resource with a stable id + schema version**.
- content/ is the shipped set; mods/ overlays by id (override) or adds new ids. Validation tool (headless) checks schema, references, and balance bounds before a mod loads.
- Core API surface for mods is versioned and documented (CONTRIBUTING.md); the engine (Godot) stays MIT and moddable at the GDExtension level.

### 3.13 Performance Architecture (budgets in PERFORMANCE.md)

- Object pooling: projectiles, VFX, pickups, damage numbers (no runtime allocs in the sim).
- LOD + occlusion culling on maps; baked lighting; texture compression (ETC2/ASTC for Android); resolution scaling + quality presets (low 30 / mid 60 / high 60–120).
- Server budget: 1 match (up to 6v6 + bots) on a 2-core container at 60 Hz (measured in Phase 5).
- Rendering: batched static geometry per map, GPU particles with pool caps, scalable shadows (off/low on low-end).
- **Measure on real Android hardware** (directive §25) from the Phase 1 vertical slice onward — never desktop-only.

## 4. Key Decisions Log (Phase 0)

| # | Decision | Rationale | Alternatives considered |
|---|---|---|---|
| D1 | Godot 4.7.x, GDScript-first | Open-source mission, mobile fit, ecosystem match, agent-friendliness | Unity (proprietary engine — fails §32) |
| D2 | Authoritative headless server, same codebase | Anti-cheat, community servers, bot parity, reconnect | P2P (fragile, hard to host); separate server language (duplication) |
| D3 | Bots are server-side controllers | Feature, not filler; parity with humans; testable headless | Client-side bots (desync, cheatable); separate AI process (latency, complexity) |
| D4 | 3v3 tuned default; team size = config | T3 lesson: 5v5 broke identity; OW 6v6 experiments confirm small-team pressure | Hard-coded 3v3 (loses §3 flexibility) |
| D5 | Data-driven heroes/weapons/abilities/perks/modes | §8/§9/§31 extensibility; headless balance testing; modding | Per-hero scripts (OW-style, but less moddable) |
| D6 | In-match perks: 2 levels × 2 choices (OW model) | Fits 3–8 min matches; proven by OW S15; choice > numbers | 3+ levels (too long); no perks (loses §8) |
| D7 | Regen-to-cap HP + map pickups (T3 pattern) | Mobile-friendly sustain; objective-adjacent pickups drive positioning | Full regen (boring positioning); no regen (high-death frustration) |
| D8 | Combat-driven ult charge (T3/OW) | Rewards play, no idle charging, consistent across modes | Time-based (T3's mode-specific ult complaint) |
| D9 | One map per phase-pair, 2 maps at Phase 6 | Compact, readable, mobile-scale | Big maps (T3's maps were right-sized; OW-scale too big for 3v3 mobile) |
| D10 | Local-first accounts, optional cloud | Offline-first mandate; no cloud dependency for core play | Account-gated (loses §19) |
| D11 | Net v1 (round 9): ENet via Godot 4.7 SceneMultiplayer; 60 Hz server, 20 Hz snapshots (unreliable) + reliable events, 100 ms interpolation. **v1.1 (round 10) refresh:** + input sanitization/seq gate, session-token reconnect (same-character reattach), lag-comp hitscan (200 ms analytic rewind, single world.hitscan truth), client prediction via a twin driven by the real NetPlayerController (hard-snap > 0.35 m), SimLink net-sim transport (150 ms RTT + 2% loss suite) | v1 shipped the authoritative loop + LAN connect first (LAN-first mandate §21); v1.1 adds feel + robustness behind the same authority rules — prediction runs the sim through the same controller interface (D3), lag-comp only bends validation (never damage), reconnect reuses the server character (no state resync needed) | Prediction from day one (feel now, complexity now); 30 Hz snapshots (bandwidth for feel); full physics re-sim for lag-comp |

## 5. Test Strategy (overview — directive §41)

- **Gameplay**: headless sim tests — movement, shooting (hitscan + projectile), damage pipeline modifiers, cooldowns, death/respawn, perk application, mode win conditions. (Godot built-in test framework or GUT; CI on PRs.)
- **Networking**: deterministic net-sim harness — latency/packet-loss injection, prediction reconciliation error bounds, lag-comp window correctness, reconnect flow, server-authority property tests (client lies are rejected).
- **Mobile**: touch input mapping tests (synthesized touches), resolution matrix (≥5 aspect ratios), FPS/memory/thermal profiles on a real device checklist per PERFORMANCE.md.
- **Bots**: headless bot eval suite — navigation success, objective time vs difficulty, K/D bands, team-formation checks; regression in CI.
- **Server ops**: dedicated-server smoke (docker up, join, play, disconnect, reconnect) in CI.

## 6. Open Questions (to resolve in Phases 1–5)

1. Exact Godot 4.7 vs 4.8 trade-offs at vertical-slice time (pin after first device test).
2. ENet vs WebRTC for the primary transport (ENet first; WebRTC if NAT traversal pain appears).
3. Bot AI: pure behavior tree vs utility-first with BT fallback (start utility scoring + BT; measure).
4. Whether to ship C# from the start for the net codec (benchmark GDScript codec cost in Phase 1).
5. Anti-cheat posture: server-authority + input rate checks first; device attestation later if needed (mobile reality).
6. Voice chat: third-party (EOS Godot, MIT) vs deferred to Phase 7 (start deferred; party text is P1).
