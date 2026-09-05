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
@export var level_base := 100.0
@export var level_growth := 1.25

func xp_for_level(n: int) -> float:
	return level_base * pow(level_growth, maxi(n - 1, 0))
