class_name ModLoader
extends RefCounted
## D34 (mod support v1): drop-in mod discovery + resolution.
##
## Layout (a mod is a directory of .tres content; see docs/MODS.md):
##   <root>/<id>/mod.tres            ModManifest (required)
##   <root>/<id>/heroes/*.tres       HeroData (appended to the roster)
##   <root>/<id>/maps/*.tres         Map (appended to the map pool)
##   <root>/<id>/modes/*.tres        Mode resource (appended to the modes)
##   <root>/<id>/cosmetics/hero_variants.tres  HeroVariantBank (its sets are
##                             added for hero_ids that have no base set)
##   <root>/<id>/balance/entries/*.tres        BalanceEntry (hero tuning)
##   <root>/<id>/balance/<file>.tres  whole-file override of the matching
##                             res://content/<file>.tres (progression,
##                             matchmaking, coach, events, shop, achievements,
##                             seasons, perks/perks) - the last accepted mod
##                             in sort order wins
##
## Roots: res://mods (bundled, part of the project) then user://mods (user
## drop-in). Same id in both: the USER copy wins. Within a root, mods are
## processed in ascending id order.
##
## Versioned API: API_VERSION is the game's mod-API generation. A mod with
## api_version > API_VERSION is REJECTED ("needs a newer game"); older ones
## are accepted (the API is additive-only per docs/MODS.md).
const API_VERSION := 1
const BUNDLED_ROOT := "res://mods"
const USER_ROOT := "user://mods"

static var mods: Array = []  # [{id, dir, manifest, accepted, reason}]
static var _loaded := false
static var _resolve_cache: Dictionary = {}
static var _files_cache: Dictionary = {}

static func scan() -> void:
	# (named scan(), not load(): the bare name resolves to Godot's global
	#  load() builtin, which requires an argument)
	if _loaded:
		return
	_loaded = true
	mods = []
	var seen: Dictionary = {}
	for root in [BUNDLED_ROOT, USER_ROOT]:
		for mdir in _dirs(root):
			var id: String = mdir.get_file()
			# User root is scanned second and OVERWRITES a bundled copy of the
			# same id (a user drop-in shadows the bundled mod of the same id).
			var entry := _accept(id, mdir)
			seen[id] = entry
	for k in seen.keys():
		mods.append(seen[k])
	mods.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))

## Test hook: re-scan (new user://mods content) + drop derived caches.
static func reset() -> void:
	_loaded = false
	mods = []
	_resolve_cache = {}
	_files_cache = {}

static func is_accepted(id: String) -> bool:
	scan()
	for m in mods:
		if str(m["id"]) == id:
			return bool(m["accepted"])
	return false

static func accepted_dirs() -> Array:
	scan()
	var out: Array = []
	for m in mods:
		if bool(m["accepted"]):
			out.append(str(m["dir"]))
	return out

## Balance override: res://content/progression.tres -> the last accepted
## mod's balance/progression.tres, or the base path when no override.
static func resolve(base_res_path: String) -> String:
	scan()
	if _resolve_cache.has(base_res_path):
		return str(_resolve_cache[base_res_path])
	var out := base_res_path
	if not base_res_path.begins_with("res://content/"):
		_resolve_cache[base_res_path] = out
		return out
	var rel := base_res_path.trim_prefix("res://content/")
	for m in mods:
		if not bool(m["accepted"]):
			continue
		var cand: String = str(m["dir"]).path_join("balance/" + rel)
		if ResourceLoader.exists(cand):
			out = cand
	_resolve_cache[base_res_path] = out
	return out

## All <dir>/<kind>/*.tres of accepted mods (ascending mod id, then file
## name). kind: "heroes" | "maps" | "modes" | "balance/entries" | ....
static func mod_files(kind: String) -> Array:
	scan()
	if _files_cache.has(kind):
		return _files_cache[kind]
	var out: Array = []
	for d in accepted_dirs():
		var dir := DirAccess.open(d.path_join(kind))
		if dir == null:
			continue
		var names: Array = []
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if not dir.current_is_dir() and f.ends_with(".tres"):
				names.append(f)
			f = dir.get_next()
		names.sort()
		for n in names:
			out.append(d.path_join(kind).path_join(n))
	_files_cache[kind] = out
	return out

static func _dirs(root: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var e := dir.get_next()
	while e != "":
		if dir.current_is_dir() and not e.begins_with("."):
			out.append(root.path_join(e))
		e = dir.get_next()
	var paths: Array = []
	for p in out:
		paths.append(p)
	paths.sort()
	return paths

static func _accept(id: String, dir: String) -> Dictionary:
	var entry := {"id": id, "dir": dir, "manifest": null,
			"accepted": false, "reason": ""}
	var mpath := dir.path_join("mod.tres")
	if not ResourceLoader.exists(mpath):
		entry["reason"] = "missing mod.tres"
		return entry
	var r: Resource = ResourceLoader.load(mpath, "", ResourceLoader.CACHE_MODE_REUSE)
	if r == null:
		entry["reason"] = "mod.tres failed to load"
		return entry
	if not (r is ModManifest):
		entry["reason"] = "mod.tres is not a ModManifest"
		return entry
	var m: ModManifest = r
	if m.id != id:
		entry["reason"] = "manifest id \"%s\" != directory id \"%s\"" % [m.id, id]
		return entry
	if m.display_name == "":
		entry["reason"] = "empty display_name"
		return entry
	if m.version == "":
		entry["reason"] = "empty version"
		return entry
	if m.api_version < 1:
		entry["reason"] = "api_version < 1"
		return entry
	if m.api_version > API_VERSION:
		entry["reason"] = "requires mod API %d (game has %d - update the game)" % [m.api_version, API_VERSION]
		return entry
	entry["manifest"] = m
	entry["accepted"] = true
	entry["reason"] = "ok"
	return entry
