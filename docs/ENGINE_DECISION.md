# Engine Decision — Godot 4 vs Unity

**Status:** Phase 0 decision (compiled 2026-09-02)
**Inputs:** OPEN_SOURCE_RESEARCH.md (project landscape), T3/OVERWATCH research (game requirements), directive §36 (evaluation axes).
**Recommendation: Godot 4 (current stable 4.7.2), GDScript-first with C# available for hot paths. Not Unity.**

---

## 1. Candidates & Current Versions (verified 2026-09-02)

| Engine | Current stable | License | Source availability |
|---|---|---|---|
| **Godot 4** | **4.7.2** (4.6.x and 4.5.x also in the archive; 4.x is the active line) | **MIT** (entire engine) | Fully open source; modifiable |
| **Unity** | **6000.3.23f1** (Unity 6 technical line; 6000.0.x is the LTS line) | **Proprietary** (runtime/editor); source-available under Unity Source License for qualified users | Not open source; modifications constrained |

## 2. Evaluation Against the Directive's Axes

### 2.1 Android performance

- **Godot:** Mobile-first renderer path (Mobile renderer, low overhead), official Android export (.apk/.aab), small base binary. Fits our stylized/low-poly target (readability > photorealism, directive §26) extremely well. Real-device performance must still be measured per directive §25 — Godot on low-end devices is *good*, not magic; we budget accordingly (PERFORMANCE.md).
- **Unity:** The industry benchmark for mobile shooters; best-in-class profiling, IL2CPP, per-asset optimization. Photoreal capability we don't need; the extra headroom costs package size and editor overhead.
- **Verdict:** Unity wins on absolute ceiling; **Godot wins on fit** — our art target is exactly where Godot's sweet spot is. A stylized 3v3 arena at 30–60 FPS is comfortably in Godot territory on mid-range phones.

### 2.2 Development speed

- **Godot:** GDScript iterates in seconds; scenes are composable; the TPS patterns we need are demonstrated in active open projects (OPEN_SOURCE_RESEARCH §2.4).
- **Unity:** C# is strong; editor is heavy; the mobile-TPS open-source ecosystem is thinner (research found mostly tutorials).
- **Verdict:** Edge to Godot for our scope; C# option exists in Godot if we need typed hot paths later.

### 2.3 Multiplayer / networking (critical axis — directive §21)

- **Godot:** Built-in high-level multiplayer (ENet reliable/unreliable, WebRTC data channels, peer-to-peer *and* server-client), scene-tree replication (RPC, remote transforms, multiplayer spawner), **headless export for dedicated servers** (same codebase, no renderer). No lag-compensation/prediction built in — we build that layer (documented in NETWORKING.md; literature in the curated list). The active Godot MP shooter scene (monke-net, Vantix, Operation Steel Tide, tiny-mmo) proves the stack works at this scale (6–12 entities is trivial).
- **Unity:** Unity Netcode for GameObjects (reliable) + low-level transport (KCP/ENet); strong tooling, but the MP layer is a separate package with its own versioning; server builds need the (heavier) server build pipeline.
- **Verdict:** Slight edge to Godot: networking is *in* the engine, the dedicated-server story is a first-class export, and the community pattern set matches our needs exactly. Both require a custom prediction/reconciliation/lag-comp layer regardless.

### 2.4 Graphics

- **Godot:** Forward+/Mobile renderers; good for stylized 3D, baked lighting, SDFGI, baked GI, particle VFX (GPUParticles2D/3D), shader-based readability effects. Not an RTX engine — irrelevant for us.
- **Unity:** HDRP/LRP/UHDRP breadth; overkill for our readability-first target.
- **Verdict:** Godot sufficient; our §26 priorities (readability > feedback > performance > identity) are shader + lighting work, not pipeline work.

### 2.5 Tooling

- **Godot:** Single ~100 MB editor, MIT-licensed, headless mode for CI (script tests, scene validation, server smoke tests — directive §41), Asset Library for plugin distribution (community mod hook, §31).
- **Unity:** Full editor + Hub + license server; CI via Unity Test Runner / Cloud; heavier toolchain.
- **Verdict:** Edge to Godot for a small, AI-agent-driven team (headless, scriptable, no license daemon).

### 2.6 Open-source implications (decisive axis — directive §32)

- **Godot (MIT):** Our game can be 100% open source *including the engine*; community can patch the engine itself if needed (the "survive without the developers" goal, §20/§31/§46). All reviewed dependencies have compatible licenses (research §2.3).
- **Unity (proprietary):** Game code can be open source, but the *engine* cannot; the project's survival depends on a company's licensing and continued engine support. Unity's 2023 runtime-fee saga (proposed, then withdrawn) is a cautionary tale for community-run longevity.
- **Verdict:** **Godot, decisively.** This is the axis the directive weights most ("genuinely open-source… the community should be capable of keeping the game alive").

### 2.7 Licensing & monetization

- **Godot:** No royalties, no revenue thresholds, no fee tiers — free at $0 and at $10M.
- **Unity:** Free Personal up to $200K USD/12-mo revenue, then Pro tiers; acceptable for a community game, but a moving target.
- **Verdict:** Godot.

### 2.8 AI-agent compatibility & maintainability

- **Godot:** Everything is text (GDScript, .tscn scenes, .tres resources, .godot project) — trivially inspectable/editable/diffable by agents and humans; scene tree maps 1:1 to the object model; docs + editor are self-hostable.
- **Unity:** Yaml scene files + binary assets + C#; editor-heavy workflow; more moving parts to script around.
- **Verdict:** Edge to Godot for an AI-led development process (this project's reality per §40).

## 3. Risk Register (Godot) & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Godot MP API evolves between 4.x releases | Medium | Pin the engine version per milestone; upgrade behind a transport/state abstraction; follow 4.7→4.8 notes quarterly (OPEN_SOURCE_RESEARCH §3.5) |
| High-level multiplayer lacks prediction/lag-comp | Medium | Build our own netcode layer (Phase 5) on the stable low-level APIs; unit-testable headless (see NETWORKING.md) |
| GDScript speed on low-end CPUs (bot AI + combat sim) | Medium | Budget in PERFORMANCE.md; move hot paths (bot AI for 6+ bots, physics-heavy VFX) to C#/GDExtension if measurements demand — architecture keeps logic data-driven so language swap is contained |
| Smaller ecosystem than Unity for some tools (e.g., anti-cheat, live-ops) | Low-Medium | Authoritative server covers anti-cheat; live-ops is our own backend (moddable, §20); Epic Online Services Godot (MIT) as optional service backbone |
| Android C# (AOT) toolchain quirks | Low | Prototype ships with GDScript (pure managed export); revisit C# only when needed |

## 4. Decision

> **Use Godot 4 (4.7.x stable at decision time) for client and dedicated server (headless). Gameplay logic in GDScript; reserve C# for measured hot paths. All content data-driven (.tres resources / JSON) to enable modding and balance iteration. Unity remains the fallback if Android profiling on real low-end hardware shows Godot missing the 30 FPS floor — the vertical slice (Phase 1) exists precisely to test this on a real device before we commit further.**

Secondary decisions:

- **Language:** GDScript primary. Rationale: fastest iteration, ecosystem pattern match, agent-friendliness. C# stays as an opt-in optimization path, never a rewrite.
- **Engine pin:** 4.7.2 at Phase 1; re-verify at each major milestone.
- **Rendering:** Mobile renderer for the vertical slice; evaluate Forward+ for high-end tier later (scalable per §25).
- **Server:** same Godot codebase, headless export; one process per match (3v3–6v6 is one node per entity — no special server tech needed at this scale).

---

## 5. Source List

- Godot download archive (stable release list): https://godotengine.org/download/archive/ — 4.7.2 current, 2026-09-02
- Godot project landscape (licenses/versions verified): see OPEN_SOURCE_RESEARCH.md
- Unity releases page (6000.3.23f1): https://unity.com/releases/editor — 2026-09-02
- Overwatch/T3 requirements mapped to axes: OVERWATCH_RESEARCH.md §3/§5, T3_RESEARCH.md §8
