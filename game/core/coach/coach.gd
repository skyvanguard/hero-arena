class_name Coach
extends RefCounted
## D32 (AI coaching): the deterministic, rule-based post-match coach.
##
## Reads ONLY the authoritative stats row (server-computed
## world.stats_rows) + the match outcome (won / MVP), and emits at most
## `max_tips` prioritized tips: warnings first (capped at
## `max_warnings`), then positives. Design rules: no magic numbers
## (everything in CoachConfig), no hero-specific advice (behavior-only -
## consistent with the no-hero-forcing rule), headless-testable, and zero
## network dependencies (the tips are a pure function of stats).
const CONFIG_PATH := "res://content/coach/coach.tres"

static func load_config() -> CoachConfig:
	var r := ResourceLoader.load(ModLoader.resolve(CONFIG_PATH), "", ResourceLoader.CACHE_MODE_REUSE)
	return r if r is CoachConfig else CoachConfig.new()

static func tips(cfg: CoachConfig, row: Array, mode_id: String,
		won: bool, is_mvp: bool) -> Array:
	var warns: Array = []
	var pos: Array = []
	var kills := int(row[1]) if row.size() > 1 else 0
	var deaths := int(row[2]) if row.size() > 2 else 0
	var hs := int(row[4]) if row.size() > 4 else 0
	var streak := int(row[5]) if row.size() > 5 else 0
	# Warning 1 - aim: a headshot rate far below par with enough volume.
	if kills >= int(cfg.aim_min_kills):
		var rate := float(hs) / float(kills)
		if rate < float(cfg.hs_rate_warn):
			warns.append(_fill(str(cfg.tip_aim),
					{"hs": str(int(rate * 100.0)), "kills": str(kills)}))
	# Warning 2 - survival: dying more than you kill.
	if deaths >= 2 and float(kills) / float(deaths) < float(cfg.kd_warn):
		warns.append(_fill(str(cfg.tip_survive),
				{"deaths": str(deaths), "kills": str(kills)}))
	# Positives (priority order; the output budget admits at most one of
	# them on top of the warnings).
	if is_mvp:
		pos.append(str(cfg.tip_mvp))
	elif streak >= int(cfg.streak_goal):
		pos.append(_fill(str(cfg.tip_streak), {"streak": str(streak)}))
	elif won:
		pos.append(str(cfg.tip_win))
	var ml := str(cfg.mode_lines.get(mode_id, ""))
	if ml != "":
		pos.append(ml)
	var out: Array = []
	for i in mini(warns.size(), int(cfg.max_warnings)):
		out.append(warns[i])
	for i in pos.size():
		if out.size() >= int(cfg.max_tips):
			break
		out.append(pos[i])
	return out

static func _fill(t: String, subs: Dictionary) -> String:
	var out := t
	for k in subs.keys():
		out = out.replace("{%s}" % k, str(subs[k]))
	return out
