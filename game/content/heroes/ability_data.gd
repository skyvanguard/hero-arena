class_name AbilityData
extends Resource
## Data-driven ability definition (Phase 2). No logic here; AbilityComponent
## interprets kind + params. Server-authoritative: all numbers come from
## this Resource, never from clients.

enum Kind {
	DASH,      ## params: count, distance, speed (impulse)
	BURST,     ## params: pellets, cone_deg, damage, slow_ratio, slow_duration
	BUFF,      ## params: duration, fire_rate_mult, speed_mult, damage_mult, spread_mult
}

@export var id: String = ""
@export var display_name: String = ""
@export var kind: int = Kind.DASH
@export var cooldown: float = 5.0
@export var is_ult: bool = false
@export var params: Dictionary = {}