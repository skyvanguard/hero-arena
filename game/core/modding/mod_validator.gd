class_name ModValidator
extends RefCounted
## D34 (mod support v1): the mod validation tool (data, shared by the
## CLI scene tools/validate_mods.tscn and the test suite). Checks, per
## accepted mod: the manifest, hero kit integrity, map integrity, mode
## type, cosmetic set shape, balance entry shape, and whole-file override
## types (the override must be the SAME resource type as the base file).
## Returns a list of issue strings (empty = valid).

## Balance override file -> expected type (res://content/<key>).
const OVERRIDE_TYPES: Dictionary = {
	"progression.tres": "ProgressionConfig",
	"matchmaking.tres": "MMConfig",
	"coach/coach.tres": "CoachConfig",
	"events/events.tres": "EventBank",
	"shop/shop.tres": "ShopBank",
	"achievements/achievements.tres": "AchievementBank",
	"cosmetics/seasons.tres": "SeasonBank",
	"perks/perks.tres": "PerkPool",
}

static func validate_all() -> Array:
	ModLoader.scan()
	var issues: Array = []
	for m in ModLoader.mods:
		var mid := str(m["id"])
		if not bool(m["accepted"]):
			issues.append(mid + ": rejected - " + str(m["reason"]))
			continue
		issues.append_array(_validate_mod(m))
	return issues

static func _validate_mod(m: Dictionary) -> Array:
	var issues: Array = []
	var mid := str(m["id"])
	var dir: String = str(m["dir"])
	# Heroes: kit integrity + no id collision with the base roster.
	var base_ids: Dictionary = {}
	for h in HeroRegistry._base_heroes:
		base_ids[str(h.id)] = true
	for p in ModLoader.mod_files("heroes"):
		if not str(p).begins_with(dir):
			continue
		var r: Resource = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REUSE)
		var tag: String = mid + "/" + str(p.get_file())
		if not (r is HeroData):
			issues.append(tag + ": not a HeroData")
			continue
		var hd: HeroData = r
		if hd.id == "" or hd.id != p.get_file().get_basename():
			issues.append(tag + ": hero id != file name")
		if base_ids.has(hd.id):
			issues.append(tag + ": id collides with a base hero (base wins)")
		if hd.display_name == "":
			issues.append(tag + ": empty display_name")
		if hd.role < 0 or hd.role > 3 or hd.sub_role < 0 or hd.sub_role > 5:
			issues.append(tag + ": role/sub_role out of range")
		if hd.max_hp <= 0 or hd.base_speed <= 0:
			issues.append(tag + ": max_hp/base_speed must be > 0")
		for k in ["clip_size", "damage", "fire_rate", "headshot_mult",
				"max_range", "reload_time", "spread_deg"]:
			var okw: bool = (hd.weapon is Dictionary) and hd.weapon.has(k) and (hd.weapon[k] is int or hd.weapon[k] is float) and hd.weapon[k] > 0
			if not okw:
				issues.append(tag + ": weapon missing/bad key " + k)
		if hd.passive == null or not (hd.passive is PassiveData) or hd.passive.id == "":
			issues.append(tag + ": passive missing/not a PassiveData")
		if hd.ult == null or not (hd.ult is AbilityData) or not hd.ult.is_ult:
			issues.append(tag + ": ult missing/not an AbilityData or is_ult=false")
		for a in hd.abilities:
			if not (a is AbilityData) or (a as AbilityData).is_ult:
				issues.append(tag + ": ability missing/not an AbilityData")
	# Maps: integrity.
	for p in ModLoader.mod_files("maps"):
		if not str(p).begins_with(dir):
			continue
		var r: Resource = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REUSE)
		var tag: String = mid + "/" + str(p.get_file())
		if not (r is Map):
			issues.append(tag + ": not a Map")
			continue
		var mp: Map = r
		if mp.map_id == "" or mp.map_id != p.get_file().get_basename() or mp.display_name == "":
			issues.append(tag + ": map_id != file name or empty display_name")
		if mp.size <= 0.0:
			issues.append(tag + ": size must be > 0")
		if mp.spawn_team0.size() == 0 or mp.spawn_team1.size() == 0 or mp.spawn_team0.size() != mp.spawn_team1.size():
			issues.append(tag + ": spawn points missing/unbalanced")
		if mp.boxes.size() != mp.box_sizes.size():
			issues.append(tag + ": boxes/box_sizes size mismatch")
	# Modes: type only (a Mode-derived resource).
	for p in ModLoader.mod_files("modes"):
		if not str(p).begins_with(dir):
			continue
		var r: Resource = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REUSE)
		if not (r is Mode):
			issues.append(mid + "/" + p.get_file() + ": not a Mode")
	# Cosmetics: bank shape per set.
	for p in ModLoader.mod_files("cosmetics"):
		if not str(p).begins_with(dir):
			continue
		var r: Resource = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REUSE)
		var tag: String = mid + "/" + str(p.get_file())
		if not (r is HeroVariantBank):
			issues.append(tag + ": not a HeroVariantBank")
			continue
		for s in (r as HeroVariantBank).sets:
			if not (s is HeroVariantSet) or str(s.hero_id) == "" or s.palette.size() != 5 or s.unlock_levels.size() != 5:
				issues.append(tag + ": bad variant set (hero_id/palette 5/unlock 5)")
	# Balance entries: shape.
	for p in ModLoader.mod_files("balance/entries"):
		if not str(p).begins_with(dir):
			continue
		var r: Resource = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REUSE)
		var tag: String = mid + "/" + str(p.get_file())
		if not (r is BalanceEntry):
			issues.append(tag + ": not a BalanceEntry")
			continue
		var be: BalanceEntry = r
		if be.hero_id == "" or be.hero_id != p.get_file().get_basename():
			issues.append(tag + ": hero_id != file name")
		if be.hp_mult <= 0.0 or be.damage_mult <= 0.0 or be.fire_rate_mult <= 0.0 \
				or be.speed_mult <= 0.0 or be.ult_charge_mult <= 0.0:
			issues.append(tag + ": multipliers must be > 0")
	# Balance overrides: same resource type as the base file.
	var bdir := dir.path_join("balance")
	var bd := DirAccess.open(bdir)
	if bd != null:
		bd.list_dir_begin()
		var f := bd.get_next()
		while f != "":
			var fp := bdir.path_join(f)
			if not bd.current_is_dir() and f.ends_with(".tres"):
				_check_override(issues, mid, fp, dir)
			f = bd.get_next()
	return issues

static func _check_override(issues: Array, mid: String, fp: String, dir: String) -> void:
	var rel := fp.trim_prefix(dir.path_join("balance") + "/")
	if not OVERRIDE_TYPES.has(rel):
		issues.append(mid + "/balance/" + rel + ": unknown override file (expected one of: "
				+ ", ".join(OVERRIDE_TYPES.keys()) + ")")
		return
	var r: Resource = ResourceLoader.load(fp, "", ResourceLoader.CACHE_MODE_REUSE)
	if r == null:
		issues.append(mid + "/balance/" + rel + ": failed to load")
		return
	var want: String = OVERRIDE_TYPES[rel]
	if _class_name(r) != want:
		issues.append(mid + "/balance/" + rel + ": must be a " + want
				+ " (found " + _class_name(r) + ")")

static func _class_name(r: Resource) -> String:
	if r == null:
		return "<null>"
	var s: GDScript = r.get_script()
	if s == null:
		return "<no script>"
	return s.get_global_name()
