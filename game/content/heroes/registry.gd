class_name HeroRegistry
extends RefCounted
## Data-driven hero roster (Phase 2: 1 hero; Phase 3 fills to 6).
## Adding a hero = dropping a .tres in content/heroes/ + one line here.

## Base roster (const content); D34: mod heroes are appended lazily (the
## first heroes()/count()/by_id()/default_hero() call merges res://mods +
## user://mods heroes/ - base ids win on collision).
static var HEROES: Array = [
	preload("res://content/heroes/kestrel.tres"),
	preload("res://content/heroes/blitz.tres"),
	preload("res://content/heroes/bastion.tres"),
	preload("res://content/heroes/mira.tres"),
	preload("res://content/heroes/patch.tres"),
	preload("res://content/heroes/nimbus.tres"),
]
static var _base_heroes: Array = HEROES.duplicate()
static var _mods_merged := false

## Test hook: drop mod heroes + let the next heroes() re-merge.
static func _test_reset() -> void:
	_mods_merged = false
	HEROES = _base_heroes.duplicate()

static func heroes() -> Array:
	if not _mods_merged:
		_mods_merged = true
		ModLoader.scan()
		var have: Dictionary = {}
		for hh in HEROES:
			have[str((hh as HeroData).id)] = true
		for p in ModLoader.mod_files("heroes"):
			var r: Resource = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REUSE)
			if r is HeroData and not have.has(str((r as HeroData).id)):
				HEROES.append(r)
				have[str((r as HeroData).id)] = true
			else:
				push_warning("HeroRegistry: skipping bad mod hero " + p)
	return HEROES

static func count() -> int:
	return heroes().size()

static func default_hero() -> HeroData:
	return HEROES[0]

static func by_id(id: String) -> HeroData:
	for h in HEROES:
		if (h as HeroData).id == id:
			return h
	return null
