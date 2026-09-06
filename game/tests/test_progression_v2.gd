extends Node
## D26 (Phase 7, item 4): progression v2 - hero mastery (regression),
## data-driven ACHIEVEMENTS (conditions, thresholds, one-shot grants,
## cosmetic rewards) + SEASONAL COSMETICS (pack data, validation,
## cosmetic-only rule). Run:
##   godot --headless --path game res://tests/test_progression_v2.tscn

var ok := 0
var fail := 0
var cfg: ProgressionConfig

func check(label: String, cond: bool, extra: String = "") -> void:
	if cond:
		ok += 1
		print("  ok  " + label)
	else:
		fail += 1
		print("  FAIL " + label + ("  [" + extra + "]" if extra != "" else ""))

func _cfg() -> ProgressionConfig:
	var r = load("res://content/progression.tres")
	return r if r is ProgressionConfig else ProgressionConfig.new()

func _bank() -> AchievementBank:
	return AchievementBank.load_bank()

func _ids(unlocked: Array) -> Array:
	var out: Array = []
	for u in unlocked:
		out.append(str(u.id))
	return out

func _ready() -> void:
	cfg = _cfg()
	# 1) bank data integrity
	var bank := _bank()
	var bad := ""
	var seen: Array = []
	for a in bank.achievements:
		var ad: AchievementData = a
		if ad == null or ad.id == "" or ad.display_name == "" or ad.desc == "" or ad.target <= 0:
			bad += "(bad:entry) ";
			continue
		if seen.has(ad.id):
			bad += "(dup:" + ad.id + ") ";
		seen.append(ad.id)
		if ad.condition == AchievementData.Condition.PLAYS_WITH_HERO and ad.hero == "":
			bad += "(nohero:" + ad.id + ") ";
		if ad.reward == AchievementData.Reward.VARIANT_UNLOCK:
			var vs: HeroVariantSet = HeroVariantBank.load_bank().set_for(ad.reward_hero)
			if vs == null or ad.reward_variant < 0 or ad.reward_variant >= vs.palette.size():
				bad += "(badreward:" + ad.id + ") ";
	check("bank: 10 achievements, unique, valid conditions + rewards", bank.achievements.size() == 10 and bad == "", bad)
	# 2) MATCHES threshold: first match unlocks exactly first_light
	var p1 := PlayerProfile.new()
	var r1: Dictionary = p1.apply_match(cfg, "kestrel", true, 0, false, 0, 0)
	var u1: Array = r1.achievements_unlocked
	check("matches: first match unlocks exactly first_light", _ids(u1) == ["first_light"], str(_ids(u1)))
	# 3) KILLS threshold is exact (99 -> no, 100th -> yes)
	var p2 := PlayerProfile.new()
	p2.total_kills = 99
	var r2a: Dictionary = p2.apply_match(cfg, "mira", false, 0, false, 0, 0)
	check("kills: 99 cumulative does NOT unlock relentless", not _ids(r2a.achievements_unlocked).has("relentless"))
	var r2b: Dictionary = p2.apply_match(cfg, "mira", false, 1, false, 0, 0)
	check("kills: the 100th kill unlocks relentless", _ids(r2b.achievements_unlocked).has("relentless"))
	# 4) HEADSHOTS accumulate across matches (10 + 15 = 25 -> marksman)
	var p3 := PlayerProfile.new()
	p3.apply_match(cfg, "kestrel", false, 2, false, 10, 0)
	var r3: Dictionary = p3.apply_match(cfg, "kestrel", false, 1, false, 15, 0)
	check("headshots: cumulative 25 unlocks marksman", _ids(r3.achievements_unlocked).has("marksman"))
	# 5) WINS accumulate to 10 (momentum)
	var p4 := PlayerProfile.new()
	var got_momentum := false
	for i in 10:
		var rr: Dictionary = p4.apply_match(cfg, "blitz", true, 0, false, 0, 0)
		if _ids(rr.achievements_unlocked).has("momentum"):
			got_momentum = true
	check("wins: 10th win unlocks momentum", got_momentum and p4.wins == 10)
	# 6) MVP accumulates to 10 (match_maker)
	var p5 := PlayerProfile.new()
	var got_mvp := false
	for i in 10:
		var rr: Dictionary = p5.apply_match(cfg, "bastion", true, 3, true, 0, 0)
		if _ids(rr.achievements_unlocked).has("match_maker"):
			got_mvp = true
	check("mvp: 10th MVP unlocks match_maker", got_mvp and p5.total_mvp == 10)
	# 7) ACCOUNT_LEVEL: a sustained winning streak crosses level 10
	var p6 := PlayerProfile.new()
	var got_star := false
	for i in 15:
		var rr: Dictionary = p6.apply_match(cfg, "mira", true, 0, true, 0, 0)
		if _ids(rr.achievements_unlocked).has("rising_star"):
			got_star = true
	check("level: reaching account level 10 unlocks rising_star", got_star and p6.level >= 10, "level=%d" % p6.level)
	# 8) BEST_STREAK: a 5-kill streak in one match (on_fire); the all-time
	#    max is kept by later smaller streaks.
	var p7 := PlayerProfile.new()
	var r7: Dictionary = p7.apply_match(cfg, "nimbus", true, 5, false, 0, 5)
	check("streak: a 5-kill match unlocks on_fire", _ids(r7.achievements_unlocked).has("on_fire") and p7.best_streak == 5)
	p7.apply_match(cfg, "nimbus", false, 3, false, 0, 3)
	check("streak: the all-time best is kept (still 5)", p7.best_streak == 5)
	# 9) PLAYS_WITH_HERO: hero-specific (15 blitz plays, not kestrel)
	var p8 := PlayerProfile.new()
	var got_bt := false
	for i in 15:
		var rr: Dictionary = p8.apply_match(cfg, "blitz", false, 0, false, 0, 0)
		if _ids(rr.achievements_unlocked).has("full_throttle"):
			got_bt = true
	check("per-hero: 15 blitz plays unlock full_throttle but not wing_commander", got_bt and not p8.achievements.has("wing_commander"))
	# 10) one-shot: a second qualifying match never re-unlocks
	var p9 := PlayerProfile.new()
	p9.apply_match(cfg, "kestrel", true, 100, false, 0, 0)
	var r9b: Dictionary = p9.apply_match(cfg, "kestrel", true, 100, false, 0, 0)
	check("one-shot: relentless unlocks exactly once", not _ids(r9b.achievements_unlocked).has("relentless") and p9.achievements.has("relentless"))
	# 11) old save compatibility: a pre-D26 JSON loads with defaults and
	#     the new keys round-trip through the save.
	var f := FileAccess.open(PlayerProfile.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"level": 3, "xp": 10.0, "total_xp": 300.0, "matches": 5, "wins": 2, "per_hero": {"kestrel": {"plays": 2}}, "variants": {}, "controls": {}}))
	f.close()
	var p10 := PlayerProfile.load(cfg)
	check("old save: pre-D26 file loads with zeroed achievement state", p10.total_kills == 0 and p10.total_headshots == 0 and p10.achievements.size() == 0 and p10.best_streak == 0)
	var r10: Dictionary = p10.apply_match(cfg, "kestrel", true, 1, false, 2, 3)
	var p10b := PlayerProfile.load(cfg)
	check("old save: counters + unlocks persist through the save round-trip", p10b.total_kills == 1 and p10b.total_headshots == 2 and p10b.best_streak == 3 and p10b.achievements.has("first_light") and _ids(r10.achievements_unlocked).has("first_light"))
	# 12) reward: the marksman variant unlock grants cosmetic early access
	#     (selectable at mastery 1, where the mastery gate alone says no).
	var p11 := PlayerProfile.new()
	for i in 3:
		p11.apply_match(cfg, "kestrel", false, 1, false, 9, 0)
	check("reward: marksman grants the kestrel variant-2 unlock", (p11.ach_variant_unlocks.get("kestrel", []) as Array).has(2))
	var bankv := HeroVariantBank.load_bank()
	var set_k: HeroVariantSet = bankv.set_for("kestrel")
	p11.set_variant("kestrel", 2)
	var got: Color = HeroVariantBank.color_for(bankv, p11, "kestrel", Color(0.9, 0.1, 0.1))
	check("reward: variant 2 is selectable at mastery 1 (cosmetic early access)", got.is_equal_approx(set_k.color_of(2, Color(0.9, 0.1, 0.1))), str(got))
	var p12 := PlayerProfile.new()
	p12.set_variant("kestrel", 2)
	var clamped: Color = HeroVariantBank.color_for(bankv, p12, "kestrel", Color(0.9, 0.1, 0.1))
	check("control: without the unlock the mastery gate still clamps to 0", clamped.is_equal_approx(set_k.color_of(0, Color(0.9, 0.1, 0.1))), str(clamped))
	# 13) cosmetic-only: granted variants never change the mastery math.
	var p13 := PlayerProfile.new()
	var before: Dictionary = p13.mastery_progress_of(cfg, "kestrel")
	p13.ach_variant_unlocks["kestrel"] = [4]
	var after: Dictionary = p13.mastery_progress_of(cfg, "kestrel")
	check("cosmetic-only: variant grants do not touch mastery", int(before.level) == int(after.level) and float(before.xp_into) == float(after.xp_into))
	# 14) server stats: stats_rows carries headshots + best streak (D26)
	var w := World.new()
	add_child(w)
	var hd_a: HeroData = null
	var hd_b: HeroData = null
	for h in HeroRegistry.HEROES:
		var d: HeroData = h
		if d.id == "kestrel": hd_a = d
		if d.id == "blitz": hd_b = d
	var a := HeroFactory.create(0, false, hd_a.color, hd_a)
	var b := HeroFactory.create(1, false, hd_b.color, hd_b)
	a.position = Vector3(0, 0.9, 0); a.protected_until = -1.0
	b.position = Vector3(3, 0.9, 0); b.protected_until = -1.0
	w.add_child(a); w.add_child(b)
	w.register_character(a); w.register_character(b)
	w.kill(b, a, true)
	w.kill(a, b, false)  # a dies: its streak resets
	var rows: Array = w.stats_rows()
	var ra: Array = rows[0]
	check("stats: rows carry headshots + best streak (a: 1 headshot, streak reset after death)", int(ra[4]) == 1 and int(ra[5]) == 1 and a.streak == 0 and a.best_streak == 1, str(ra))
	var rb: Array = rows[1]
	check("stats: b's kill is a normal kill (no headshot, streak 1)", int(rb[4]) == 0 and int(rb[5]) == 1, str(rb))
	w.free()
	# 15) seasonal cosmetics: bank loads, validates, current pack resolves
	var sb := SeasonBank.load_seasons()
	var errs: Array = SeasonBank.validate(sb)
	var cur := sb.current()
	check("season: bank validates clean and the current pack is non-empty", errs.size() == 0 and cur != null and cur.entries.size() == 6, str(errs))
	check("season: pack entries resolve + no false positives", cur.has_entry("kestrel", 1) and not cur.has_entry("kestrel", 2) and SeasonBank.current_name() != "")
	# 16) overlay text rows (pure, headless)
	var sample: Array = [{"id": "x", "name": "Sample", "desc": "", "reward": "Unlocks KESTREL variant 2 (cosmetic)"}, {"id": "y", "name": "Quiet", "desc": "", "reward": ""}]
	var rows2: Array = AchievementBank.view_rows(sample)
	check("view: rows carry name + reward wording", rows2.size() == 2 and str(rows2[0]).contains("Sample") and str(rows2[0]).contains("KESTREL") and not str(rows2[1]).contains("("))

	print("PROGRESSION-V2 SUITE: %d passed, %d failed" % [ok, fail])
	get_tree().quit(fail)
