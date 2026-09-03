class_name PassiveData
extends Resource
## Data-only passive (Phase 2; role/sub-role registry lands in Phase 3).
## Kestrel's 'Wingbeats': hit-streak stacks -> speed & spread bonuses.

enum Kind {
	HIT_STREAK,  ## params: stack_hits, window, tiers (array of {speed_mult, spread_mult})
	SPRINT,      ## params: speed_mult — constant movement-speed multiplier (sprint identity)
	ARMOR,       ## params: dmg_reduce — flat fraction of incoming damage negated (tank identity)
	FLEX,        ## params: cd_mult — ability cooldown multiplier < 1 (flex identity)
	ZONE,        ## params: radius, rate_mult — fire-rate bonus while an enemy is in radius (controller identity)
	FIELD,       ## params: radius, heal_per_s — constant tick-heal to allies in radius (field identity)
}

@export var id: String = ""
@export var display_name: String = ""
@export var kind: int = Kind.HIT_STREAK
@export var params: Dictionary = {}