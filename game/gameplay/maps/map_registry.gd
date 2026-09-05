class_name MapRegistry
extends RefCounted
## Map registry (Phase 6, D18): data-driven maps as .tres Resources under
## content/maps/. Unknown id -> the default map (never fails a host).
const DEFAULT_ID := "crossdocks"
const DIR := "res://content/maps/"

static func ids() -> Array:
	return ["crossdocks", "foundry"]

static func get_map(id: String) -> Map:
	var mid := id if id != "" else DEFAULT_ID
	var path := DIR + mid + ".tres"
	if mid in ids() and ResourceLoader.exists(path):
		var r: Resource = load(path)
		if r is Map:
			return r
	return get_map(DEFAULT_ID)
