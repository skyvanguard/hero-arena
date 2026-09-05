class_name ProgressionConfig
extends Resource
## Progression v1 (D19): XP values and the level curve as DATA (AGENTS: no
## magic numbers in code). Cosmetic-only progression — nothing here gates
## gameplay or sells advantage (no pay-to-win, the directive).

## XP for finishing a match on the winning team.
@export var xp_win := 120.0
## XP for finishing on the losing team (participation still pays).
@export var xp_lose := 40.0
## XP per kill in the match.
@export var xp_kill := 25.0
## Bonus for being the match MVP (most kills, tie-break damage).
@export var xp_mvp := 60.0
## xp_for_level(n) = level_base * level_growth^(n-1) — a gentle exponential.
## Used for BOTH the global account level and per-hero mastery (D22) — one
## curve, two applications.
@export var level_base := 100.0
@export var level_growth := 1.25

## D22 per-hero MASTERY weights (separate from global XP): mastery is a
## per-hero specialization track fed by that hero's play stats (the
## per_hero seed: matches/wins/kills/mvp). Cosmetic-only - it gates
## cosmetic variants, never gameplay.
@export var mastery_match := 10.0
@export var mastery_win := 15.0
@export var mastery_kill := 5.0
@export var mastery_mvp := 20.0

func xp_for_level(n: int) -> float:
	return level_base * pow(level_growth, maxi(n - 1, 0))
