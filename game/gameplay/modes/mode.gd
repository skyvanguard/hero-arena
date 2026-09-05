class_name Mode
extends Resource
## Mode framework v1 (Phase 6, round 30, ARCHITECTURE D16): a match's RULES
## as a data-driven resource. World owns every piece of match state (score,
## objective state, characters); a Mode defines the WIN CONDITION and may
## drive per-step objective logic through the two hooks below. The match
## host (net/server_main.gd, main.gd) instantiates one from
## MatchConfig.mode_id via ModeRegistry and assigns it to world.mode before
## the first step; world.mode == null keeps the built-in TDM legacy path
## (pre-framework matches and the existing suites are untouched).
##
## Score convention: a Mode reports the SCORE THE HUD SHOWS via score_of()
## (TDM: kills; Control: point captures) — the wire snapshot carries that
## one number per side.
@export var mode_id := "tdm"
@export var display_name := "Team Deathmatch"

## One-time objective initialization (the match host calls this right after
## assigning world.mode): the mode seeds the World's objective state from
## its own @export params (bases, lanes, the control point, ...).
func setup(world: World) -> void:
	pass

## Per-step objective logic (World.step calls this AFTER the entities have
## stepped, BEFORE the over-check).
func step(world: World, _dt: float) -> void:
	pass

## Win / timeout check. Must call world.finish_match(winner) once the
## condition is met (-1 = draw).
func check_over(world: World) -> void:
	pass

## A character died (World.kill calls this after the kill event). Modes
## that hold per-character objective state (Capture: flag drop) react here.
func on_kill(_world: World, _killer: CharacterEntity, _victim: CharacterEntity) -> void:
	pass

## The per-side score the HUD/snapshot should show.
func score_of(world: World) -> Array:
	return [int(world.score.get(0, 0)), int(world.score.get(1, 0))]
