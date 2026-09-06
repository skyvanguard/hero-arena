class_name MapRegistry
extends RefCounted
## Map registry (Phase 6, D18): data-driven maps as .tres Resources under
## content/maps/. Unknown id -> the default map (never fails a host).
const DEFAULT_ID := "crossdocks"
const DIR := "res://content/maps/"

static func ids() -> Array:
	# Base maps by directory scan (no hardcoded pool) + D34 mod maps.
	var out: Array = []
	var dir := DirAccess.open(DIR)
	if dir != null:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if not dir.current_is_dir() and f.ends_with(".tres"):
				out.append(f.get_basename())
			f = dir.get_next()
	for p in ModLoader.mod_files("maps"):
		var bn: String = p.get_file().get_basename()
		if not out.has(bn):
			out.append(bn)
	return out

## D27 (anti-repetition): the valid vote pool for the NEXT match - every
## registered map except the one named (the just-played / current map).
## Falls back to the full list when the pool would be empty (the degenerate
## single-map case). `ids` defaults to the registry (tests may pass a stub).
static func rotation_pool(exclude: String = "", ids: Array = []) -> Array:
	var all: Array = ids if ids.size() > 0 else ids()
	var out: Array = []
	for i in all:
		if str(i) != exclude:
			out.append(i)
	return out if out.size() > 0 else all

static func get_map(id: String) -> Map:
	var mid := id if id != "" else DEFAULT_ID
	if mid in ids():
		var path := DIR + mid + ".tres"
		if not ResourceLoader.exists(path):
			for p in ModLoader.mod_files("maps"):
				if p.get_file() == mid + ".tres":
					path = p
					break
		var r: Resource = load(path)
		if r is Map:
			return r
	return get_map(DEFAULT_ID)
