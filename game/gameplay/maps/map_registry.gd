class_name MapRegistry
extends RefCounted
## Map registry (Phase 6, D18): data-driven maps as .tres Resources under
## content/maps/. Unknown id -> the default map (never fails a host).
const DEFAULT_ID := "crossdocks"
const DIR := "res://content/maps/"

static func ids() -> Array:
	return ["crossdocks", "foundry", "sawmill", "saltline"]

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
	var path := DIR + mid + ".tres"
	if mid in ids() and ResourceLoader.exists(path):
		var r: Resource = load(path)
		if r is Map:
			return r
	return get_map(DEFAULT_ID)
