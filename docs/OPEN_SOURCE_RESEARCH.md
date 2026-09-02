# Open-Source Project Research

**Status:** Phase 0 research (compiled 2026-09-02)
**Method:** GitHub repo search + primary file inspection (project.godot, LICENSE, README via raw.githubusercontent.com). Licenses verified from repo files, not badges. Evaluation axes per the directive: license, engine version, architecture, activity, Android compatibility, performance, networking, maintainability.

---

## 1. Summary Table

| Project | Engine | License (verified) | Activity (last push) | Why it matters to us |
|---|---|---|---|---|
| **godotengine/tps-demo** (1.4k★) | Godot 4.x (master), GDScript | Assets CC-BY 3.0 (code: repo LICENSE.md, mixed) | 2026-08-31 (active, official) | Reference TPS controller + camera + animation setup for Godot 4 |
| **gdquest-demos/godot-4-3d-third-person-controller** (1.0k★) | Godot 4, GDScript | Dual license: code (permissive) + generated assets (separate) | 2026-08-15 (active) | Plug-and-play TPS controller "inspired by RA…"; best dual-license split example |
| **AetherRadar/operation-steel-tide** (11★) | **Godot 4.6 + C#** | **MIT** (code) | 2026-09-02 (pushed today; active) | Closest architecture match: open-source Godot 4 tactical FPS with **AI squadmates, online co-op, 5v5 bomb mode, persistent loot** |
| **jasonswearingen/TPS-MP** (66★) | Godot 3.2, GDScript | **MIT** | 2023-12-14 ("living archive") | Minimal authoritative MP TPS pattern (Godot 3; concepts portable) |
| **vantixorg/vantix** (63★) | Godot 4.6 + C# | **Apache-2.0 (code only, assets excluded)** | 2026-06-19 (in development) | "Tactical multiplayer shooter **and framework**" — explicit client/server framework intent |
| **rohanrhu/vegetables** (14★) | Godot 3.x, GDScript | **GPL-3.0** | 2020-12-06 (dormant) | "Vegetables": multiplayer deathmatch shooter; **GPL = copyleft caveat** (see §3) |
| **grazianobolla/godot-monke-net** (247★) | Godot 4, C# | **No license file** (all-rights-reserved risk) | 2026-04-03 | Client/server authoritative multiplayer addon (read-the-code value, not a dependency) |
| **zimerfeld/ZIMARO** (4★) | Godot, GDScript | Custom/"other" | 2026-08-07 (active) | TPS **sandbox with allied bots + reactive enemies** — bot architecture reference |
| **SlayHorizon/godot-tiny-mmo** (274★) | Godot 4, GDScript | MIT | 2026-07-23 | Cross-platform MMO client/server patterns (snapshot sync, replication) |
| **Whimfoome/godot-FirstPersonStarter** (1.0k★) | Godot 4, GDScript | MIT | 2024-05-05 | Clean FPS starter (input, weapon, reload patterns) |
| **3ddelano/epic-online-services-godot** (313★) | Godot 4, C++/GD | MIT | 2026-09-01 (active) | Epic Online Services integration (backbone for online services later) |
| **expressobits/inventory-system** (727★) | Godot 4, C++ | MIT | 2026-02-20 | Modular inventory (data-driven, multiplayer-compatible) |
| **0xFA11/MultiplayerNetworkingResources** (8.7k★) | n/a (curated list) | — | 2026-08-27 | Networking literature index (lockstep, prediction, reconciliation, lag comp) |
| **SmartFoxServer SFS_Shooter_GD4 / SFS_MatchMaking_GD4** (10★/4★) | Godot 4, C# | MIT | 2024 | Dedicated-server + matchmaking *server backend* example (SFS is commercial) |
| **teeeece/godot_open_target_shooter** (62★) | Godot 3.5, GDScript | MIT | 2026-06-20 | TPS time-trial (aim/movement tuning patterns) |
| **Demetrius-Dixon/Monkanics** (6★) | Godot 4, GDScript | Custom | 2026-08-27 | FOSS arena shooter (small, readable) |

Honorable mentions: **CyberSys/godot4-fast-paced-network-fps-tps** (2★, MIT, authoritative-server net framework, 2022), **MystixCode/Godot4Net** (16★, GPL-2.0, low-level net), **SFS examples**, **Quaint-Studios/Sustenet** (43★, MIT, Rust/Zig net layer).

---

## 2. Key Findings

### 2.1 There is no dominant "open-source mobile hero shooter" to fork

The field is fragmented: official/educational demos (tps-demo, GDQuest controller), small active C# Godot 4.6 projects (Operation Steel Tide, Vantix), and older Godot 3 examples (TPS-MP, Vegetables). **No project has: mobile-first touch controls + 3v3 hero shooter + authoritative server + bots + open license + active maintenance all together.** We are building, not forking. We *reference* and *learn from*; we do not merge.

### 2.2 Engine + language landscape

- **Godot 4 is where all active open-source shooter work lives.** Every active (2025–2026) Godot shooter uses 4.x; the two most active (Operation Steel Tide, Vantix) use **Godot 4.6 + C#**.
- **C# is the emerging choice for serious Godot 4 multiplayer projects** (monke-net, Vantix, Operation Steel Tide, SFS examples) — typed, faster than GDScript for heavy logic, single-file compilation.
- **GDScript remains the default for demos/prototypes** and is sufficient for gameplay logic at our scale; Godot 4 also supports it as the "feel" language.
- **Unity open-source shooter projects exist** but are mostly 2D/top-down or tutorial-grade; the big Unity shooters (e.g., Corgi Engine commercial, various mobile FPS assets) are asset-store, not open source.

### 2.3 License landscape (critical for us)

| License | Projects | Us as a permissive open-source project? |
|---|---|---|
| MIT / Apache-2.0 / Unlicense | tps-demo code, Operation Steel Tide (MIT), Vantix (Apache-2.0), GDQuest (dual), Whimfoome, monke-net examples | ✅ Compatible — code can be referenced/adopted with attribution |
| **GPL-2.0/3.0** | Vegetables (GPL-3.0), Godot4Net (GPL-2.0), 2D demos | ⚠️ **Copyleft: mixing GPL code into a permissive-licensed game is problematic.** Use as reference only, or keep strictly separated (separate process) if reused |
| CC-BY (assets) | tps-demo assets, GDQuest assets | ⚠️ Free with attribution + ShareAlike caveats for *derived* assets; we will **not reuse** their art, only study structure |
| **No license file** | monke-net, ZIMARO (custom), several | ❌ Legally all-rights-reserved — read and learn, don't copy |

**Rule for this project (to be codified in CONTRIBUTING.md):** code we import must be MIT/Apache/Unlicense (or our own). Assets must be permissive (CC0/MIT/CC-BY-with-credits) or original. Anything GPL is reference-only.

### 2.4 Architecture patterns worth stealing

1. **Operation Steel Tide (Godot 4.6 + C#)**: the only active, licensed, feature-complete open Godot shooter with *AI squad + online co-op + 5v5 objective mode*. Study its: netcode split, AI command structure, scene organization, export config for dedicated servers.
2. **Vantix**: "shooter *and framework*" — explicit client/server framework layering (transport / state / prediction). Apache-2.0 code-only license is a model for us (code Apache/MIT, assets separately licensed).
3. **GDQuest controller**: the canonical Godot 4 TPS controller decomposition (character, camera, animation, input buffering) — start our Phase 1 controller from this *pattern* (not its code).
4. **TPS-MP (Godot 3)**: minimal authoritative TPS — server-side state + client prediction skeleton; useful for our networking doc examples.
5. **ZIMARO / T3-style sandbox bots**: "allied bots + reactive enemies" — the bot architecture (perception → decision → execution) is what our §13 requires.
6. **godot-tiny-mmo**: snapshot/replication patterns for many-entities — scales to our 6-player + bot worlds.
7. **MultiplayerNetworkingResources**: the literature list for lag compensation, reconciliation, entity interpolation — the reading list for Phase 5.

### 2.5 Android compatibility notes

- **Godot**: first-class Android export (Java/Kotlin wrapper, .apk/.aab), official; C# Android works (mono/AOT). Community Godot Android shooters are common. Godot 4's mobile renderer (Forward+/Mobile) is tuned for phones.
- **Unity**: the industry default for mobile (best-in-class Android tooling, IL2CPP, perf profiling); but closed-source engine.
- Neither reference project ships a mobile build of a 3v3 hero shooter specifically — we will be the reference.

### 2.6 Ecosystem tools (not projects, but part of the open-source stack)

- Godot Editor: MIT, runs on desktop; headless for CI.
- GDExtension: C++/Rust addons with stable ABI (used by several projects above).
- Godot Asset Library: in-editor plugin/asset distribution (community mods hook).
- Epic Online Services Godot (MIT): auth/voice/matchmaking backbone option for Phase 5+ (or build our own — see NETWORKING.md).

---

## 3. Recommendations

1. **Build on Godot 4.x (current stable 4.7.2; consider pinning 4.6.x LTS-track for a release cadence) — details in ENGINE_DECISION.md.**
2. **Do not fork any single repo.** Create our own repo; reference the projects above in code comments/docs where patterns are borrowed.
3. **License our code Apache-2.0** (patent grant matters for game tech; permissive) or MIT — decision in ENGINE_DECISION.md/README. **Assets:** original or CC0/CC-BY with a LICENSE-ASSETS file, à la Vantix/GDQuest.
4. **Track the active projects quarterly**: Operation Steel Tide, Vantix, gdquest-demos, godotengine/tps-demo, godot-monke-net — they are where the state of the art is moving.
5. **Watch Godot 4.7→4.8 release notes** for multiplayer API changes (high-level multiplayer is still evolving).
6. **Avoid GPL contamination** in game/ and server/; if a GPL library proves essential later, isolate it in its own process with a documented boundary.

---

## 4. Source List

- GitHub (repos, files, licenses verified 2026-09-02 via api.github.com + raw.githubusercontent.com):
  godotengine/tps-demo · gdquest-demos/godot-4-3d-third-person-controller · AetherRadar/operation-steel-tide · jasonswearingen/TPS-MP · vantixorg/vantix · rohanrhu/vegetables · grazianobolla/godot-monke-net · zimerfeld/ZIMARO · SlayHorizon/godot-tiny-mmo · Whimfoome/godot-FirstPersonStarter · 3ddelano/epic-online-services-godot · expressobits/inventory-system · 0xFA11/MultiplayerNetworkingResources · SmartFoxServer SFS_*_GD4 · teeeece/godot_open_target_shooter · Demetrius-Dixon/Monkanics · CyberSys/godot4-fast-paced-network-fps-tps · MystixCode/Godot4Net · Quaint-Studios/Sustenet
