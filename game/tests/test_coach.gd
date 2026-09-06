extends Node
## D32 AI coaching suite (round 48): the deterministic post-match coach
## (rule-based "AI" over AUTHORITATIVE stats - server stats_rows). Covers
## the data-driven config, each rule's fire/suppress conditions, the
## per-mode objective lines, the output budget (warnings first, capped),
## the no-hero-forcing rule, short-row guards, and determinism. 14 checks.
var cfg: CoachConfig
var passed := 0
var failed := 0

func _ready() -> void:
	_run()

func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		passed += 1
		print("  ok  " + name)
	else:
		failed += 1
		printerr("  FAIL " + name + ("  [" + detail + "]" if detail != "" else ""))

## row = [team, kills, deaths, damage, headshots, best_streak]
func _row(kills: int, deaths: int, hs: int, streak: int) -> Array:
	return [0, kills, deaths, kills * 40, hs, streak]

func _has(tips: Array, sub: String) -> bool:
	for t in tips:
		if str(t).contains(sub):
			return true
	return false

func _run() -> void:
	cfg = Coach.load_config()
	# 1: the config loads with sane, data-driven thresholds.
	check("coach: config loads with sane thresholds",
			cfg != null and cfg.hs_rate_warn < cfg.hs_rate_good and cfg.hs_rate_good < 1.0
			and cfg.kd_warn > 0.0 and cfg.kd_warn <= 1.0
			and cfg.max_tips >= cfg.max_warnings and cfg.max_warnings >= 1
			and cfg.mode_lines.size() == 4,
			"%s" % str(cfg.mode_lines.size()))
	# 2: the aim tip fires on a low headshot rate with volume...
	var t_low: Array = Coach.tips(cfg, _row(5, 1, 0, 0), "tdm", true, false)
	check("coach: aim tip fires on 0% headshots over 5 kills",
			_has(t_low, "Headshot rate is low (0% of 5 kills)"),
			"%s" % str(t_low))
	# ...and is suppressed at a good rate and below the kill volume.
	var t_good: Array = Coach.tips(cfg, _row(5, 1, 2, 0), "tdm", true, false)
	var t_few: Array = Coach.tips(cfg, _row(1, 0, 0, 0), "tdm", true, false)
	check("coach: aim tip suppressed at 40% rate and under the kill volume",
			not _has(t_good, "Headshot rate") and not _has(t_few, "Headshot rate"))
	# 3: the survival tip fires on a poor kill/death ratio...
	var t_die: Array = Coach.tips(cfg, _row(2, 5, 0, 0), "tdm", false, false)
	check("coach: survival tip fires at 2 kills / 5 deaths",
			_has(t_die, "You died 5 times for 2 kills"), "%s" % str(t_die))
	# ...and is suppressed at a healthy ratio.
	var t_ok: Array = Coach.tips(cfg, _row(5, 3, 2, 0), "tdm", false, false)
	check("coach: survival tip suppressed at 5 kills / 3 deaths",
			not _has(t_ok, "You died"))
	# 4: the MVP positive fires only for the MVP...
	var t_mvp: Array = Coach.tips(cfg, _row(4, 2, 2, 1), "tdm", true, true)
	var t_nomvp: Array = Coach.tips(cfg, _row(4, 2, 2, 1), "tdm", true, false)
	check("coach: MVP praise only for the MVP",
			_has(t_mvp, "top performer") and not _has(t_nomvp, "top performer"))
	# 5: the streak praise fires at the goal, not below (and MVP wins the
	#    positive slot over the streak).
	var t_s4: Array = Coach.tips(cfg, _row(4, 1, 2, 4), "tdm", true, false)
	var t_s3: Array = Coach.tips(cfg, _row(3, 1, 2, 3), "tdm", true, false)
	check("coach: streak praise at goal 4, not at 3; MVP takes the slot",
			_has(t_s4, "4-kill streak") and not _has(t_s3, "kill streak")
			and not _has(t_mvp, "kill streak"))
	# 6: each objective mode gets its own data-driven line.
	var modes: Array = ["tdm", "control", "capture", "escort"]
	var seen: Array = []
	var all_distinct := true
	for m in modes:
		var tm: Array = Coach.tips(cfg, _row(3, 1, 1, 0), m, true, false)
		var ml := str(cfg.mode_lines.get(m, ""))
		if not _has(tm, ml.substr(0, 12)):
			all_distinct = false
		seen.append(ml)
	var uniq: Dictionary = {}
	for s in seen:
		uniq[str(s)] = true
	check("coach: all four modes get their distinct objective lines",
			all_distinct and uniq.size() == 4, "%s" % str(uniq.size()))
	# 7: an unknown mode contributes no line (and does not crash).
	var t_unk: Array = Coach.tips(cfg, _row(3, 1, 1, 0), "moonbase", true, false)
	check("coach: unknown mode adds no line",
			t_unk.size() == 1 and str(t_unk[0]) == str(cfg.tip_win),
			"%s" % str(t_unk))
	# 8: the output budget - two warnings + three positives -> exactly
	#    max_tips tips, warnings first.
	var t_full: Array = Coach.tips(cfg, _row(3, 5, 0, 4), "capture", true, true)
	check("coach: budget = max_tips with warnings first",
			t_full.size() == 3 and str(t_full[0]).contains("Headshot rate")
			and str(t_full[1]).contains("You died")
			and str(t_full[2]).contains("top performer"),
			"%s" % str(t_full))
	# 9: a clean win with nothing to fix -> the single positive line.
	var t_clean: Array = Coach.tips(cfg, _row(4, 2, 2, 1), "tdm", true, false)
	check("coach: clean win yields the positive tip (before the mode line)",
			t_clean.size() == 2 and str(t_clean[0]).contains("Solid win"),
			"%s" % str(t_clean))
	# 10: short rows (old stats shape) are guarded - no crash, survival
	#      still evaluated from the columns that exist.
	var t_short: Array = Coach.tips(cfg, [0, 2, 5], "tdm", false, false)
	check("coach: short rows guarded (no crash, survival still works)",
			_has(t_short, "You died 5 times for 2 kills"), "%s" % str(t_short))
	# 11: no hero forcing - no tip ever names a hero (behavior-only).
	var hero_names: Array = []
	for h in HeroRegistry.HEROES:
		if h is HeroData:
			hero_names.append(str(h.display_name).to_lower())
	var forced := ""
	for m in ["tdm", "control", "capture", "escort"]:
		for rr in [[2, 5, 0, 0], [5, 1, 0, 4], [4, 2, 2, 1]]:
			for w in [true, false]:
				for mv in [true, false]:
					for t in Coach.tips(cfg, _row(int(rr[0]), int(rr[1]),
							int(rr[2]), int(rr[3])), m, w, mv):
						var tl := str(t).to_lower()
						for hn in hero_names:
							if tl.contains(hn) and forced == "":
								forced = hn
	check("coach: no tip names a hero (behavior-only advice)", forced == "",
			"named: " + forced)
	# 12: determinism - the same authoritative stats give the same tips.
	var a1: Array = Coach.tips(cfg, _row(3, 4, 1, 2), "escort", false, false)
	var a2: Array = Coach.tips(cfg, _row(3, 4, 1, 2), "escort", false, false)
	check("coach: deterministic (same stats -> same tips)", a1 == a2,
			"%s vs %s" % [str(a1), str(a2)])
	print("COACH SUITE: %d passed, %d failed" % [passed, failed])
	get_tree().quit(failed)
