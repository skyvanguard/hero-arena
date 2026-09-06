# MOBILE.md — Android-first build, input & performance notes

Directive §25: **Android is the primary target.** Desktop is a dev
convenience, not a release platform. This document is the standing
reference for mobile input, building, and the performance process;
measured numbers live in [PERFORMANCE.md](PERFORMANCE.md).

## App identity

- Package: `com.openhero.arena` (see game/project.godot).
- Orientation: **landscape** — the 1280×720 design surface is landscape;
  `window/stretch/mode="canvas_items"` + `aspect="expand"` scale the UI
  to any device aspect ratio (tall phones get expanded play area, not
  letterboxing).
- Shipping renderer: `renderer/rendering_method="mobile"` (Vulkan Forward
  Mobile) — the Android target renderer (docs/BUILD.md).

## Input

Two input backends share one controller interface (the sim never knows
who is playing):

- **Touch** (`core/input/touch_controls.gd`, CanvasLayer):
  - left half = **virtual joystick** (move),
  - right half = **drag to aim** (fire while dragging),
  - action buttons (ability / ult / interact) placed by the layout
    resolver.
- **Desktop** (`core/input/desktop_input.gd`): WASD + mouse aim + keys;
  the mouse aim reads the same sensitivity multiplier as touch, so a
  layout tuned on one platform behaves predictably on the other.

### D24 control customization

The touch layout resolves from a **baseline** (content data:
`ControlLayout`) × **user settings** (persisted in the player profile:
`ControlSettings`) via the pure function
`ControlSettings.effective(layout, settings, viewport)`. Customizable in
the hero-select CONTROLS panel:

| Setting | Range | Notes |
|---|---|---|
| fire-button side | left / right | mirrors the whole right cluster |
| button / joystick scale | 0.75 – 1.5 | |
| control opacity | 0.30 – 1.00 | |
| aim sensitivity | 0.25 – 3.0 | shared with desktop mouse aim |

Defaults reproduce the original hard-coded layout exactly. Settings are
ergonomics only — **no pay-to-win, no wire traffic** (local profile JSON).

### Text entry (D35 room codes)

Private-match room codes are entered through a `LineEdit` in the
hero-select lobby panel; on Android this raises the soft keyboard
automatically (Godot default behavior — no special handling). Codes are
uppercased + validated client-side before hitting the lobby
(`LobbyProtocol.is_room_code`).

## Building for Android

See [BUILD.md](BUILD.md) for the full recipe (keystore, export presets).
Short form:

```bash
# release APK, shipping renderer (Vulkan Forward Mobile)
cd game
/path/to/godot --headless --path . --export-release Android build/demo/heroarena.apk
adb install -r build/demo/heroarena.apk      # or a clean install for
                                              # renderer-setting changes
```

Emulator smoke-testing needs the `gl_compatibility` feature-tag flip +
clean install (PERFORMANCE.md, "Known environment notes") — the headless
AVD cannot present Vulkan. The emulator is a **pessimistic proxy**, never
the release signal.

## On-device measurement process

- **FPS / worst frame**: `PerfProbe` (game/core/util/perf_probe.gd) logs
  `PERF <fps> fps (worst frame <ms>)` every 5 s — filter with
  `adb logcat -s godot`.
- **Memory**: `adb shell dumpsys meminfo com.openhero.arena | grep "TOTAL
  PSS"` polled every 5–8 s during a match (the Phase 4 OOM bisect used
  exactly this).
- **Acceptance**: the 30 FPS low-end / 60 FPS mid-range floors on all
  maps, 3v3, full FX — recorded in the PERFORMANCE.md real-device table
  at every phase exit (AGENTS.md standing rule).

## Known mobile gotchas (learned, don't relearn)

1. **2D canvas invalidation churn** (Phase 4, OOM at 3v3): on the
   compatibility renderer, per-frame writes to Label.text / ColorRect /
   bar values fragment the allocators. Every HUD write is
   change-gated or quantized (core/input/hud.gd header documents each
   rule). A new HUD element must write on change, not per frame.
2. **Renderer settings don't hot-swap**: changing the rendering method
   needs a **clean install** (uninstall first) — `install -r` can keep
   the old packed project behavior (verified rounds 32-33).
3. **Emulator display size**: some AVD images reject `wm size` overrides
   (the Phase 2 instance ran 640×320) — check the guest resolution
   before reading emulator FPS numbers.
4. **Sim/render separation is the whole architecture**: the sim runs
   headless (tests, dedicated server), so every mobile fix must be
   verifiable in CI before it ever touches a device.
