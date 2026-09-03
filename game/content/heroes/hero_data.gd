class_name HeroData
extends Resource
## Full hero kit as data (directive: 6 differentiated heroes, role/sub-role,
## data-driven content). One Resource per hero in content/heroes/.

enum Role { ASSAULT, TANK, SUPPORT, CONTROLLER }
enum SubRole { SUSTAINED, SPRINT, ARMOR, FLEX, FIELD, ZONE }

@export var id: String = ""
@export var display_name: String = ""
@export var role: int = Role.ASSAULT
@export var sub_role: int = SubRole.SUSTAINED
@export var color: Color = Color(0.35, 0.62, 0.95)
@export var max_hp: int = 100
@export var base_speed: float = 6.0
@export var jump_velocity: float = 5.8
## Weapon profile (applied to the Weapon node at build time).
@export var weapon: Dictionary = {
	"damage": 12.0, "headshot_mult": 2.5, "fire_rate": 8.0,
	"clip_size": 30, "reload_time": 1.8, "max_range": 120.0, "spread_deg": 0.5,
}
@export var passive: PassiveData
@export var abilities: Array = []  ## AbilityData (index 0 = Q1, 1 = Q2)
@export var ult: AbilityData
## Combat-driven ultimate charge (D8): charge gained per damage dealt/taken.
@export var ult_max: float = 100.0
@export var charge_per_damage_dealt: float = 0.35
@export var charge_per_damage_taken: float = 0.10
@export var charge_per_heal_dealt: float = 0.0
@export var charge_per_kill: float = 15.0