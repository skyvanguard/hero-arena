class_name HeroVariantSet
extends Resource
## D22 cosmetic variant set for ONE hero (data, not code - AGENTS: no magic
## numbers). palette[0] is always the hero's default color (identical to
## HeroData.color, verified by test); unlock_levels[i] is the MASTERY level
## required to select variant i. Cosmetic-only: nothing here gates gameplay
## (no pay-to-win - every variant is earned by playing the hero).

## Untyped arrays on purpose: .tres deserialization of typed Color arrays
## is fragile across 4.x versions; code casts with a fallback.
@export var hero_id: String = ""
@export var palette: Array = []
@export var unlock_levels: Array = []

func color_of(idx: int, fallback: Color) -> Color:
	if idx >= 0 and idx < palette.size():
		var c = palette[idx]
		if c is Color:
			return c
	return fallback

func unlock_of(idx: int) -> int:
	if idx >= 0 and idx < unlock_levels.size():
		return int(unlock_levels[idx])
	return 0

## Highest palette index the given mastery level may select.
func unlocked_count(mastery_level: int) -> int:
	var n := 0
	for i in palette.size():
		var need := 0
		if i < unlock_levels.size():
			need = int(unlock_levels[i])
		if mastery_level >= need:
			n = i + 1
		else:
			break
	return maxi(n, 1)
