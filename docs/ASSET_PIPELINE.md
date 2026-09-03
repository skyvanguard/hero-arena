# ASSET_PIPELINE.md — content assets (Phase 2)

Original IP only: every asset in this repo is either original or permissive
license (see assets/LICENSE-ASSETS.md). No proprietary assets, ever
(AGENTS.md standing rule).

## Folder conventions

```
game/assets/
  audio/sfx/<sfx>_<category>_<name>_<variant>.wav   # one-shot sound effects
  audio/music/<track>.ogg                           # (Phase 6+)
  vfx/                                              # VFX material/prefab sources (Phase 3+)
  anim/                                             # animation sets (Phase 3+, with original models)
  ui/                                               # UI art (Phase 6 polish)
game/tools/                                         # asset generation tools (headless-runnable)
```

## Naming

- SFX: `sfx_<category>_<name>[_<variant>].wav` — category in
  `fire|hit|kill|jump|reload|dash|burst|ult|respawn`; variant 01/02/... when
  a sound has randomization slots.
- All lowercase snake_case. Hero-specific: `sfx_<hero>_<ability>_<variant>`
  (e.g. `sfx_kestrel_glide_02`).
- VFX/anim: `<hero>_<ability>_<part>`; generic: `fx_<effect>_<part>`.

## Audio import settings (current)

- WAV 16-bit PCM mono 22050 Hz (small, plenty for short SFX). Godot imports
  to `.sample`; the `Sfx` node (core/audio/sfx.gd) pools 8 AudioStreamPlayers
  and maps world events (shot/hit/kill/jump/reload/respawn/ability_cast) to
  sounds with per-role volume (player vs. others).
- Regenerate all SFX deterministically:
  `godot --headless --path game -s res://tools/gen_sfx.gd` (seed 20260903).

## VFX approach (Phase 2 state)

- Code-built, placeholder-grade: tracers (thin unshaded boxes — Godot 4.7
  removed Line3D), particle bursts (GPUParticles3D one-shots), ult aura ring
  (WorldFX + UltAura). All render-side; the sim never depends on them.
- Original VFX pass (custom particles, glow, hero-specific signatures) lands
  with the original hero models in Phase 3.

## Animation

- Phase 2: procedural cosmetics only (gun is a static model; kit identity
  comes from movement + VFX + SFX).
- Phase 3: original (or permissive-licensed) skeletal animation sets —
  idle/run/jump/shoot/ability/death — per hero, named `anim_<hero>_<state>`.
