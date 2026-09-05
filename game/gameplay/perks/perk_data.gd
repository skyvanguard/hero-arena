class_name PerkData
extends Resource
## D25 — one in-match perk option (Phase 7). Data-driven content resource:
## the sim reads effects as multipliers applied to the character's modifier
## pipeline; the UI reads name/desc. tier = 1 (level-2 choice) / 2 (level-3).
## roles = which hero roles may see this perk (empty = every role).

@export var id := ""
@export var tier := 1
## HeroData.Role values; empty = universal.
@export var roles: Array[int] = []
## Multiplier effects, applied (multiplied) onto the character's perk_mults.
## Keys: damage, fire_rate, cooldown, speed, max_hp, regen, charge, spread.
## 1.0 = no effect. cooldown < 1 = faster abilities.
@export var effects: Dictionary = {}
## Flat heal applied the moment the perk is picked (0 = none).
@export var heal_on_pick := 0.0
@export var name := "Perk"
@export_multiline var desc := ""
