class_name PlayerProfile
extends RefCounted
## Local account v1 (D19): level + XP + per-hero record, persisted to
## user://profile.save. Client-side and cosmetic — the SERVER never reads
## it (server authority is sacred; progression cannot affect a match).

const SAVE_PATH := "user://profile.save"
var level := 1
## XP toward the NEXT level.
var xp := 0.0
var total_xp := 0.0
var matches := 0
var wins := 0
## hero_id -> {"plays": int, "wins": int, "kills": int} (mastery seed).
var per_hero: Dictionary = {}

static func load(cfg: ProgressionConfig) -> PlayerProfile:
	var p := PlayerProfile.new()
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		f.close()
		if d is Dictionary:
			p.level = int(d.get("level", 1))
			p.xp = float(d.get("xp", 0.0))
			p.total_xp = float(d.get("total_xp", 0.0))
			p.matches = int(d.get("matches", 0))
			p.wins = int(d.get("wins", 0))
			p.per_hero = d.get("per_hero", {})
	return p

func save() -> void:
	var d := {"level": level, "xp": xp, "total_xp": total_xp,
		"matches": matches, "wins": wins, "per_hero": per_hero}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))
		f.close()

## Apply one finished match. Returns {xp_gained, level_before, level_after}
## for the results screen ("+XP" / "LEVEL UP!").
func apply_match(cfg: ProgressionConfig, hero_id: String, won: bool,
		kills: int, is_mvp: bool) -> Dictionary:
	var gained := (cfg.xp_win if won else cfg.xp_lose) \
			+ float(kills) * cfg.xp_kill \
			+ (cfg.xp_mvp if is_mvp else 0.0)
	var before := level
	xp += gained
	total_xp += gained
	matches += 1
	if won:
		wins += 1
	var h: Dictionary = per_hero.get(hero_id, {})
	h["plays"] = int(h.get("plays", 0)) + 1
	h["wins"] = int(h.get("wins", 0)) + (1 if won else 0)
	h["kills"] = int(h.get("kills", 0)) + kills
	per_hero[hero_id] = h
	while xp >= cfg.xp_for_level(level):
		xp -= cfg.xp_for_level(level)
		level += 1
	save()
	return {"xp_gained": gained, "level_before": before, "level_after": level}
