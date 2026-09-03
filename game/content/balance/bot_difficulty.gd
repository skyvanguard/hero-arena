class_name BotDifficulty
extends Resource
## Difficulty parameter pack (Phase 4) — data, not code (AGENTS: no magic
## numbers; gameplay values live in content/balance/). One .tres per tier;
## the BotController/Perception/Decision modules read everything from here.
## Tiers (directive §2): beginner/normal/advanced/expert.

@export var id: String = ""
@export var label: String = ""

## --- Combat (execution) ---
## Seconds from first sighting to first shot (reaction model).
@export var reaction := 0.5
## Aim cone error in degrees (aim error model, resampled every 0.2 s).
@export var aim_error_deg := 2.5
## Will shoot up to this range; prefers fighting at ideal_range.
@export var engage_range := 26.0
@export var ideal_range := 14.0
## Retreat to spawn below this HP fraction.
@export var retreat_hp := 0.35
## Seconds HP must stay below retreat_hp before committing to retreat
## (short window keeps bots killable by focused fire; re-engage at
## retreat_hp + 0.15 once regen recovers above that line).
@export var retreat_confirm := 0.5
## Strafe cadence (s between direction flips).
@export var strafe_min := 0.9
@export var strafe_max := 1.8

## --- Perception (difficulty-gated info) ---
@export var vision_range := 40.0
@export var vision_fov_deg := 90.0
## Shots by enemies within this radius are heard (hearing model).
@export var hearing_range := 18.0
## Seconds a lost target stays 'known' (memory).
@export var lost_sight_timeout := 1.2
## Scan turn speed (rad/s) while searching/holding.
@export var scan_speed := 1.0

## --- Team / ability use ---
## 0..1 quality gate for ability timing (beginner bots miss their cues).
@export var ability_quality := 0.5
## Regroup toward an ally below this HP fraction.
@export var grouping_threshold := 0.55
## Distance (m) from the nearest in-combat ally beyond which an idle bot
## drifts back to the squad (stick/protect; bigger tiers hold tighter).
@export var stick_range := 10.0
## Meters of lateral spacing per team-mate sharing a target (flank spread:
## stops a squad from stacking on one line of fire).
@export var flank_spacing := 3.0
