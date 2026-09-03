class_name AbilityData
extends Resource
## Data-driven ability definition (Phase 2). No logic here; AbilityComponent
## interprets kind + params. Server-authoritative: all numbers come from
## this Resource, never from clients.

enum Kind {
	DASH,      ## params: count, distance, speed (impulse)
	BURST,     ## params: pellets, cone_deg, damage, slow_ratio, slow_duration, projectile (bool)
	BUFF,      ## params: duration, fire_rate_mult, speed_mult, damage_mult, spread_mult
	HEAL,      ## params: radius, amount (instant heal to self + allies in radius)
	FIELD,     ## params: duration, radius, heal_per_s, speed_boost (aura on owner, ticks allies)
	BOOST,     ## params: radius, duration, speed_boost, rate_boost (instant team buffs)
	ZONE,      ## params: distance, radius, duration, slow_ratio (grounded slow field)
}

@export var id: String = ""
@export var display_name: String = ""
@export var kind: int = Kind.DASH
@export var cooldown: float = 5.0
@export var is_ult: bool = false
@export var params: Dictionary = {}