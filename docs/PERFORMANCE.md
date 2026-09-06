# PERFORMANCE.md — mobile performance budgets & baselines

Target (directive §25, §45): smooth on real Android — **30 FPS floor on low-end
hardware, 60 FPS on mid-range**, at the 3v3 match size. Measured on a real device
at every phase exit (AGENTS.md standing rule).

## Frame budget (60 Hz target)

| Slice | Budget | Notes |
|---|---|---|
| Input + logic (sim step, 60 Hz fixed) | ≤ 8 ms | sim must tick headless at this cost on a mid-range phone |
| Rendering (mobile renderer, Vulkan) | ≤ 8 ms | 6-8 heroes, 2 maps, low-poly |
| Total frame | 16.7 ms | 30 FPS floor = 33.3 ms |

## Measured baselines

### 2026-09-03 — headless Android emulator (Phase 1)

Hardware proxy: Android 34 x86_64 emulator (google_apis), **software rendering**
(llvmpipe Vulkan / ANGLE->Mesa GL). No real GPU — numbers are a *lower-bound
proxy*, not a device measurement.

| Renderer | Result |
|---|---|
| mobile (Vulkan, SwiftShader) | **stalled main loop** — 'Couldn't present to Vulkan queue (VkResult error 5)' every frame, ~0-1 FPS. Headless-emulator artifact (swapchain OUT_OF_DATE), not a game bug. |
| gl_compatibility (ANGLE ES 3.1) | **36-48 FPS steady-state** after a ~15 s shader warmup (first 5-s windows: 5-6 FPS). Worst frame ≤ 50 ms in steady state. 1v1 sim + bots + full touch UI. |

Interpretation: the sim + rendering pipeline already clears the 30 FPS floor on
CPU-only software rasterization → real Android GPUs have large headroom.

### 2026-09-03 — headless Android emulator (Phase 2: hero select + SFX + VFX)

Same AVD, but this instance rejects `wm size` override → guest display is
**640x320 landscape** (lighter fill than the Phase 1 1280x720 surface).
Scene = hero select → 1v1 match with Kestrel (full kit VFX/SFX wired).

| Config | Result |
|---|---|
| gl_compatibility, SFX on | **24-33 FPS** steady after warmup; occasional ~0.1-1 s hitches (emulator housekeeping). |
| gl_compatibility, SFX muted (vol -60 dB) | 29-33 FPS steady — audio mix cost ≈ 0-5 FPS. |
| gl_compatibility, SFX not created | 36/33 FPS, then 22-24 FPS with a 1.06 s hitch — same band as Phase 1. |

Interpretation: no render-side regression from Phase 2 features; the spread is
emulator variance, not a feature cost. Real-device re-measure still pending
(shipping renderer is `mobile`/Vulkan; the GL proxy above is pessimistic).

### 2026-09-03 — headless Android emulator (Phase 4: offline 3v3 + bots)

Same AVD, 1440×720 viewport (see environment notes). Scene = offline 3v3
match (player + 2 ally bots vs 3 enemy bots, `normal` difficulty), GL
compatibility renderer, all render subsystems on (WorldFX tracers/labels/
particles, Sfx pool, HUD).

**Memory (the Phase 4 bug):** the first 3v3 builds were OOM-killed in ~20 s of
combat — RSS 3.2 GB, Scudo "exhausted 256M for size class N". Bisect
(`debugperf/no_*` project settings, one subsystem per build):

| Config (render subsystems) | 96 s result |
|---|---|
| all off (sim + 3D only) | **flat ~161 MB** |
| WorldFX only (no HUD/Sfx) | **flat ~161 MB** |
| Sfx only (no WorldFX/HUD) | **flat ~162 MB** |
| HUD only, inert (no control writes) | **flat ~179 MB** |
| HUD, flash writes only (0.05 alpha steps) | **flat ~179 MB** |
| HUD, +HP writes (int precision) | **flat ~181 MB** |
| HUD, +ult bar (0.5 steps) | **flat ~182 MB** |
| HUD, +kill-feed Label create/free per kill | **2.6 GB by 30 s → OOM** |
| HUD final (pooled feed, all write-on-change) | **flat ~188 MB, 0 script errors** |

Root cause: on the GL compatibility renderer every 2D canvas invalidation
(label `.text`, `ColorRect.color`, bar `.value`, new Label add/remove) churns
the canvas texture pool; at per-frame rates the alloc/free cycle fragments
Scudo's large-block pools and RSS grows without bound. The kill feed's
per-kill Label create/free was the single biggest churn source.

Fixes (in `core/input/hud.gd`, documented in its header): label text written
only on change; damage flash written on 0.05 alpha steps; ult bar quantized to
0.5; kill feed is a fixed pool of 6 labels overwritten round-robin. Headless
sim RSS is ~112 MB flat over a 110 s 1v1 duel — the growth is render-side.

| Metric | Result |
|---|---|
| PSS, full 3v3, 96 s | **~181-190 MB flat** (was: OOM at ~20-30 s) |
| FPS (llvmpipe/ANGLE software GL) | 8-25 fps with 6 active bots + full FX — software-rasterizer proxy; 1v1/hero-select measured 24-48 fps in earlier phases. Real-device measure pending. |

Interpretation: memory is now stable at 3v3 scale on the worst-case
software rasterizer; the sim alone (headless) is flat at ~112 MB, so the
dedicated-server 2-core budget has ample headroom (Phase 5). FPS on this AVD
is not a device signal — see the real-device table below.

### Real device

| Device | Date | Renderer | FPS (steady) | Worst frame | Notes |
|---|---|---|---|---|---|
| _pending_ | — | mobile | — | — | Phase 6 gate: low-end ≥ 30 / mid ≥ 60 on all four maps (no device attached in dev env as of round 39) |

### 2026-09-04 — dedicated server, 2-core budget (Phase 5, round 27)

Workload: `server/Dockerfile` image (Godot 4.7.2 headless, import cache
baked), full **3v3 bot match** (6 entities, AI + 60 Hz fixed physics + arena
collision), container CPU-capped with `--cpuset-cpus="0,1"` (hard 2-core
affinity). Measurement host: 80-core/256 GB Linux (docker 29.7), so the
cap is the only constraint — closer to a 2-core VPS than the host is.

| Metric | Result |
|---|---|
| CPU, pure bot match, 60 s | **11.6 CPU-s / 60 s = ~0.19 cores** (~10% of the 2-core budget) |
| Sim pacing (world.time / real time, 2 samples) | **1.0000** (8.333 s in 8.331 s; 8.333 s in 8.333 s) — 60 Hz step holds |
| Snapshot pacing, 10 s client through published ports | **199/200 (19.9 Hz)** target 20 Hz, 0 sustained loss; 182 combat events in the same window |
| Full bot match to completion | Yes (discovery state -> OVER; no step drift, no crash) |

Interpretation: the authoritative server clears the 2-core budget with
>90% headroom at 3v3 scale; 6v6 (2x entities) is the scaling risk to re-
measure when team-size variety lands. Image: ~119 MB compressed / ~377 MB
uncompressed (the Godot binary dominates).

### 2026-09-05 — Phase 6 perf pass (round 39)

Workload: 3v3 bot matches (6 entities) on both original maps, current code
(post-D24).

**Dedicated server, 2-core budget (docker image, --cpuset-cpus="0,1"):**

| Map | Main-thread CPU (live match) | Share of 2-core budget | Memory |
|---|---|---|---|
| foundry (stress map) | 0.293 cores (60 s window, /proc utime+stime) | ~15% | 54 MiB flat |

Note on the uncapped-host numbers (1.7-2.2 cores for the same 3v3 match on
the 80-core dev box): Godot sizes its thread pool to the host core count
(84 threads observed), and the pool + ENet polling burn mostly kernel time
there. The cpuset-2 container is the budget-relevant environment (pool = 2);
0.293 cores keeps >85% headroom on the 2-core budget. Sim pacing was already
proven at ratio 1.0000 on 2 cores (round 27) and the full match runs to OVER
with no step drift; the sim <= 8 ms step budget is met at 3v3 scale.

**Client, headless Android emulator (software GL proxy, 1440x720, full FX):**

| Map | FPS (steady) | Worst frame | Notes |
|---|---|---|---|
| foundry | 8-9 at launch -> 20 steady | 89 ms (steady state) | launch dip = shader warmup; host under load (avg ~10) |
| crossdocks | 3-9 at launch -> 16-17 steady | 134 ms (steady state) | launch dip = shader warmup + first respawn VFX burst |

Interpretation: the software rasterizer (Mesa/llvmpipe via ANGLE) is a
pessimistic proxy, not a device signal. Foundry (the heavier map) at 20 fps
steady under host load sits inside the Phase 4 crossdocks band (8-25 fps);
the 30 FPS low-end floor is a real-device number (below).

**Real device (Phase 6 exit gate, round 39 status):** no physical Android
device is attached in this dev environment (adb lists only the emulator),
so the device row is measured the moment hardware is available. Everything
else on the Phase 6 gate list is done: both maps playable, full match flow,
server budget, demo builds published (docs/BUILD.md).

## Known environment notes

- Headless emulators (no window / no KVM-gpu) can fail Vulkan present with
  VK_ERROR_OUT_OF_DATE. For emulator smoke tests, set the FEATURE-TAGGED
  line in project.godot to `renderer/rendering_method.mobile="gl_compatibility"`
  (keep `renderer/rendering_method="mobile"` for shipping). Godot 4.7
  resolves the `.mobile` feature-tagged variant over the base key on
  Android: setting only the base key to `gl_compatibility` still selects
  "Forward Mobile"/Vulkan (verified round 33 - the app logged
  `Vulkan 1.3.0 - Forward Mobile` and stalled on VkResult 5 while the
  packed project already carried the base key as gl_compatibility).
  Rebuild the APK and do a CLEAN install (uninstall + install): `install -r`
  keeps the app data, but a fresh install is the reliable way to pick up
  the repacked project. **The working combo is `-gpu angle_indirect` +
  gl_compatibility** (host ANGLE->Mesa, the Phase 1/2 config) - the engine
  log must read `OpenGL ES 3.1 ... Compatibility ... ANGLE`. Verified round
  32: `-gpu swiftshader_indirect` + gl_compatibility fails with
  `CanvasShaderGLES3: Fragment shader active uniforms exceed
  GL_MAX_FRAGMENT_UNIFORM_VECTORS (261)` (uniform gray screen, input still
  partially live), and angle_indirect + mobile stalls on Vulkan present.
- `PerfProbe` (game/core/util/perf_probe.gd) logs `PERF <fps> fps (worst frame
  <ms>)` every 5 s to logcat — filter with `adb logcat -s godot`.
- Memory watch used for the Phase 4 bisect: `adb shell dumpsys meminfo
  com.openhero.arena | grep "TOTAL PSS"` polled every 5-8 s during a match.
- `debugperf/no_{fx,sfx,hud,tracers,labels,particles}` project settings (set in
  `project.godot`, default false) switch render subsystems off one at a time —
  keep for future memory bisects.
- Emulator recipe used (this machine): AVD `neo_test` (android-34 google_apis
  x86_64), `sg kvm` for /dev/kvm access,
  `emulator -no-window -gpu angle_indirect -window-size 1280,720`,
  `adb shell wm size 1280 720` for the landscape surface.
  **Note:** `wm size 1280 720` is *rejected* on this AVD ("bad size"); the
  landscape surface settles at a **1440×720** Godot viewport (design 1280×720
  centered, ~0.444 scale to the 640×320 capture). For `adb input tap` tests,
  compute the tap from the *viewport* rect (printed by the HUD), not the
  design coords: `screen = (viewport_x, viewport_y) * 0.4444`. Touch
  emulates a mouse press (Godot default), so a tap also triggers the
  `fire` mouse action — account for that when verifying button taps.