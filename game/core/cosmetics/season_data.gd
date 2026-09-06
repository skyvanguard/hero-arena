class_name SeasonData
extends Resource
## D26 (Phase 7, item 4): one cosmetic SEASON as data. A season is a named
## cosmetic pack - a set of (hero, palette-variant) entries that the game
## labels as the current track. Cosmetic-only by construction: the data
## holds no stat fields, selection still requires the variant to be
## unlocked (mastery or an achievement), and nothing here touches a match.
@export var id := ""
@export var display_name := ""
## Pack entries: [{"hero": String, "variant": int}, ...]
@export var entries: Array = []

func has_entry(hero_id: String, idx: int) -> bool:
	for e in entries:
		var ed: Dictionary = e
		if str(ed.get("hero", "")) == hero_id and int(ed.get("variant", -1)) == idx:
			return true
	return false
