class_name PerkPool
extends Resource
## D25 — the perk table + XP curve for one match (Phase 7). Content lives
## here (no magic numbers in the sim): XP rates, level thresholds, perks.

@export var perks: Array = []  # Array[PerkData]
## XP per point of damage dealt / heal dealt.
@export var xp_per_damage := 0.05
@export var xp_per_heal := 0.04
@export var xp_kill := 12.0
@export var xp_headshot_bonus := 4.0
## XP thresholds: level 2 at level2_at, level 3 at level3_at (max level 3).
@export var level2_at := 40.0
@export var level3_at := 100.0

func get_perk(pid: String) -> PerkData:
	for p in perks:
		var d: PerkData = p
		if d.id == pid:
			return d
	return null

func index_of(pid: String) -> int:
	for i in perks.size():
		var d: PerkData = perks[i]
		if d.id == pid:
			return i
	return -1
