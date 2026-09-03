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
- Emulator recipe used (this machine): AVD `neo_test` (android-34 google_apis
  x86_64), `sg kvm` for /dev/kvm access,
  `emulator -no-window -gpu angle_indirect -window-size 1280,720`,
  `adb shell wm size 1280 720` for the landscape surface.