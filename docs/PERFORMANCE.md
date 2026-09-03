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
| _pending_ | — | mobile | — | — | Phase 1 gate: first real low-end Android ≥ 30 FPS |

## Known environment notes

- Headless emulators (no window / no KVM-gpu) can fail Vulkan present with
  VK_ERROR_OUT_OF_DATE. For emulator smoke tests, temporarily switch
  `renderer/rendering_method` to `gl_compatibility`; shipping builds use `mobile`.
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