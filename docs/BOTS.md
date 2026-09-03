# BOTS.md — bot system (Phase 4)

Bots are server-side controllers: a bot is a `BotController` node added to a
hero exactly like a human input source. Anything a human does, a bot does
through the same entry points (`move_input`, `aim_target`, `want_fire`,
ability casts) — human/bot parity is guaranteed by construction (D3).

## Stack

    BotController  (setup(hero, target, world, difficulty) + step(world, dt))
    ├── BotPerception  vision cone (FOV+range+LOS) / hearing / known-table
    └── BotDecision    intent ladder + role responsibilities

- Stepped **inside** `CharacterEntity.step` when the hero has no human
  controller — bots need no external pulse and run identically in the
  dedicated server (headless).
- Intents: `RETREAT → ATTACK → INVESTIGATE → REGROUP → HOLD` (first match
  wins). HOLD = hold position + scan turn at `scan_speed`.
- Role tweaks: TANK fights closer + holds the line; SUPPORT regroups harder
  and fights at range; all roles use the shot-hearing callout (INVESTIGATE).
  Flank / protect / revive arrive with the Phase 6 modes.

## Retunables (all data — `content/balance/bots/*.tres`)

| Parameter | Meaning | beginner / normal / advanced / expert |
|---|---|---|
| reaction | s before a fresh target is shootable | 0.9 / 0.5 / 0.25 / 0.12 |
| aim_error_deg | angular error cone (5 Hz resample) | 1.8 / 0.9 / 0.6 / 0.3 |
| engage_range / ideal_range | m — open fire / preferred fight distance | 20/10 … 34/18 |
| retreat_hp / retreat_confirm | hp fraction to fall back / s below before committing | 0.25/0.5 … 0.15/0.5 |
| strafe_min / strafe_max | lateral speed (× base speed) | 1.4/2.4 … 0.4/0.9 |
| vision_range / vision_fov_deg | m / ° cone | 30/70 … 60/135 |
| hearing_range / lost_sight_timeout | m / s before a target is "lost" | 12/1.6 … 34/0.6 |
| scan_speed | rad/s while HOLD-scanning | 0.6 … 1.8 |
| ability_quality | probability gate for ability timing | 0.35 … 1.0 |
| grouping_threshold | ally hp fraction that triggers REGROUP | 0.5 … 0.65 |

Tiers must stay strictly ordered (enforced by `tests/test_bots.tscn`):
better tiers see more, react faster, and aim truer.

## Combat model notes

- Aim is **angular** (rotate the direction to the known position by a random
  deviation inside the cone), aimed from head height
  (`CharacterEntity.AIM_HEIGHT`). Do not reintroduce fixed meter offsets —
  they make accuracy independent of range.
- Heads are a 0.28 m `StaticBody3D` sphere above the 0.4 m body capsule
  (hitbox gap 1.8–2.22 m is intentional). `intersect_ray` in Godot 4.7 does
  **not** report `Area3D` — keep the head sensor a StaticBody and detect
  headshots via `CharacterEntity.hit_is_head`.
- Every ray a character casts must exclude the whole character
  (`CharacterEntity.own_rids()`) — queries starting inside the shooter's own
  head sensor otherwise see nothing.
- Bots reload on their own (`start_reload()` when the clip is dry in combat,
  pre-load out of combat). Humans keep the R key.
- Retreat needs `retreat_confirm` seconds below `retreat_hp` and re-engages
  at `retreat_hp + 0.15` (hysteresis). Removing either makes bots unkillable
  or suicidal.

## Memory (render side)

HUD 2D canvas writes must be write-on-change / coarse-step, and the kill
feed uses a fixed label pool — see the header of `core/input/hud.gd` and
the Phase 4 section of PERFORMANCE.md (per-frame canvas writes OOM'd a 3v3
in ~20 s on the GL emulator).

## Testing

`tests/test_bots.tscn` (13 checks): tier data ordering, vision
(in-cone / out-of-cone / LOS-blocked), hearing (+ position), decisions
(ATTACK / RETREAT / REGROUP), navigation closure, **3v3 normal: kills
happen**, **3v3 expert squad out-K/Ds beginner squad**.
