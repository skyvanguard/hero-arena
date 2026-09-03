class_name HeroRegistry
extends RefCounted
## Data-driven hero roster (Phase 2: 1 hero; Phase 3 fills to 6).
## Adding a hero = dropping a .tres in content/heroes/ + one line here.

const HEROES: Array = [
	preload("res://content/heroes/kestrel.tres"),
	preload("res://content/heroes/blitz.tres"),
	preload("res://content/heroes/bastion.tres"),
]

static func count() -> int:
	return HEROES.size()

static func default_hero() -> HeroData:
	return HEROES[0]

static func by_id(id: String) -> HeroData:
	for h in HEROES:
		if (h as HeroData).id == id:
			return h
	return null
