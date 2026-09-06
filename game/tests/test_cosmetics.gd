extends Node
## Cosmetics + mastery suite (Phase 6, round 36, D22): 14 checks -
## the variant bank (per-hero palettes, default color pinned, unlock
## schedule), per-hero mastery as a pure function of the stat seed
## (weights + shared level curve, level-up, mvp seed, old-save backward
## compat), variant selection persistence + unlock gating + color
## resolution (clamping locked picks), and the headless UI: hero-select
## mastery line + variant dots + swatch color, and a full offline match
## whose player character wears the selected variant and whose results
## screen shows the per-hero mastery line.
## Run: godot --headless --path game res://tests/test_cosmetics.tscn
## Exit code = number of failed checks.

var passes := 0
var fails := 0

func check(name: String, cond: bool, detail := "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		fails += 1
		print("FAIL ", name, ("  [" + detail + "]" if detail != "" else ""))

func _wipe_profile() -> void:
	var sp := ProjectSettings.globalize_path("user://profile.save")
	if FileAccess.file_exists(sp):
		DirAccess.remove_absolute(sp)

func _ready() -> void:
	randomize()
	_wipe_profile()
	var cfg: ProgressionConfig = load("res://content/progression.tres")
	await _bank(cfg)
	await _mastery(cfg)
	await _variants(cfg)
	await _ui(cfg)
	print("COSMETICS SUITE: %d passed, %d failed" % [passes, fails])
	get_tree().quit(fails)

# ---- 1-3: the variant bank (data) ------------------------------------------
func _bank(cfg: ProgressionConfig) -> void:
	var bank: HeroVariantBank = HeroVariantBank.load_bank()
	var ok_sets := bank.sets.size() == HeroRegistry.heroes().size()
	var all_have := true
	var pin_ok := true
	for h in HeroRegistry.heroes():
		var hd: HeroData = h
		var s: HeroVariantSet = bank.set_for(hd.id)
		if s == null or s.palette.size() < 4:
			all_have = false
		if s != null and s.palette.size() > 0 and s.palette[0] != hd.color:
			pin_ok = false
	check("bank: one variant set per registry hero (palette >= 4)",
			ok_sets and all_have, "sets=%d heroes=%d" % [bank.sets.size(),
			HeroRegistry.heroes().size()])
	check("bank: palette[0] is pinned to the hero's default color", pin_ok, "")
	var sched_ok := true
	for s in bank.sets:
		var ss: HeroVariantSet = s
		if ss.unlock_levels.size() != ss.palette.size():
			sched_ok = false
		for i in ss.unlock_levels.size():
			if i == 0 and int(ss.unlock_levels[0]) != 0:
				sched_ok = false
			if i > 0 and int(ss.unlock_levels[i]) < int(ss.unlock_levels[i - 1]):
				sched_ok = false
	check("bank: unlock schedule non-decreasing, first variant free",
			sched_ok, "")

# ---- 4-7: per-hero mastery --------------------------------------------------
func _mastery(cfg: ProgressionConfig) -> void:
	var p := PlayerProfile.new()
	var pr: Dictionary = p.mastery_progress_of(cfg, "kestrel")
	check("mastery: fresh hero is level 1 with zero XP",
			int(pr.level) == 1 and float(pr.xp_into) == 0.0
			and is_equal_approx(float(pr.need), cfg.xp_for_level(1)),
			"%s" % str(pr))
	# 1 win, 3 kills, MVP: 10 + 15 + 15 + 20 = 60 (weights from the config).
	p.apply_match(cfg, "kestrel", true, 3, true)
	check("mastery: XP follows the data weights (match+win+kill+mvp)",
			is_equal_approx(p.mastery_xp_of(cfg, "kestrel"), 60.0)
			and p.mastery_level_of(cfg, "kestrel") == 1,
			"xp=%.1f lv=%d" % [p.mastery_xp_of(cfg, "kestrel"),
			p.mastery_level_of(cfg, "kestrel")])
	var q := PlayerProfile.new()
	q.apply_match(cfg, "mira", true, 5, false)
	q.apply_match(cfg, "mira", true, 5, false)
	# 2 x (10 + 15 + 25) = 100 -> exactly the level-2 threshold.
	var qp: Dictionary = q.mastery_progress_of(cfg, "mira")
	check("mastery: exact-threshold level-up (two 5-kill wins -> LV2)",
			int(qp.level) == 2 and float(qp.xp_into) == 0.0, "%s" % str(qp))
	# Old-save backward compat: a pre-D22 per_hero entry has no "mvp" key.
	var r := PlayerProfile.new()
	r.per_hero["patch"] = {"plays": 3, "wins": 1, "kills": 4}
	# 3*10 + 1*15 + 4*5 + 0*mvp = 65
	check("mastery: pre-D22 saves load (missing mvp key counts as 0)",
			is_equal_approx(r.mastery_xp_of(cfg, "patch"), 65.0),
			"xp=%.1f" % r.mastery_xp_of(cfg, "patch"))

# ---- 8-10: variant selection ------------------------------------------------
func _variants(cfg: ProgressionConfig) -> void:
	var bank: HeroVariantBank = HeroVariantBank.load_bank()
	var s: HeroVariantSet = bank.set_for("kestrel")
	var p := PlayerProfile.new()
	p.set_variant("kestrel", 2)
	var p2: PlayerProfile = PlayerProfile.load(cfg)
	check("variants: selection persists through save/load",
			p2.selected_variant("kestrel") == 2,
			"got=%d" % p2.selected_variant("kestrel"))
	check("variants: level 0 unlocks only the default",
			s.unlocked_count(0) == 1, "got=%d" % s.unlocked_count(0))
	# 22 x (10 + 15 + 25 + 20) = 1540 >= 1507.4 (levels 1..8) -> LV8: every
	# variant in the schedule [0, 2, 4, 6, 8] is unlocked.
	var rich := PlayerProfile.new()
	for i in 22:
		rich.apply_match(cfg, "kestrel", true, 5, true)
	check("variants: high mastery unlocks the full palette",
			s.unlocked_count(rich.mastery_level_of(cfg, "kestrel"))
			== s.palette.size(),
			"lvl=%d unlocked=%d" % [rich.mastery_level_of(cfg, "kestrel"),
			s.unlocked_count(rich.mastery_level_of(cfg, "kestrel"))])
	var fresh := PlayerProfile.new()
	var hd: HeroData = HeroRegistry.HEROES[0]
	var c0: Color = HeroVariantBank.color_for(bank, fresh, hd.id, hd.color)
	check("color_for: fresh profile wears the default color",
			c0 == hd.color, "%s" % str(c0))
	# LV2 (100 XP = two 5-kill wins) unlocks variant 1 (schedule [0, 2, ...]).
	fresh.apply_match(cfg, hd.id, true, 5, false)
	fresh.apply_match(cfg, hd.id, true, 5, false)
	fresh.set_variant(hd.id, 1)
	var c1: Color = HeroVariantBank.color_for(bank, fresh, hd.id, hd.color)
	check("color_for: selected variant resolves to its palette color",
			c1 == s.palette[1], "%s" % str(c1))
	# fresh is mastery LV2 (variant 1 unlocked, 2..4 locked) -> pick 4 clamps
	# to the highest unlocked index (1).
	fresh.set_variant(hd.id, 4)
	var c4: Color = HeroVariantBank.color_for(bank, fresh, hd.id, hd.color)
	check("color_for: a locked pick clamps to the highest unlocked",
			c4 == s.palette[1], "%s" % str(c4))
	var fresh2 := PlayerProfile.new()
	fresh2.set_variant(hd.id, 4)  # mastery level 1 -> everything but 0 locks
	var c4b: Color = HeroVariantBank.color_for(bank, fresh2, hd.id, hd.color)
	check("color_for: fresh profile clamps a locked pick to the default",
			c4b == s.palette[0], "%s" % str(c4b))

# ---- 11-14: headless UI ------------------------------------------------------
func _find_label_text(root: Node, needle: String) -> bool:
	for c in root.get_children():
		if c is Label and str(c.text).find(needle) >= 0:
			return true
		if c is CanvasLayer or c is Control:
			if _find_label_text(c, needle):
				return true
	return false

func _ui(cfg: ProgressionConfig) -> void:
	var bank: HeroVariantBank = HeroVariantBank.load_bank()
	var s: HeroVariantSet = bank.set_for("kestrel")
	# Profile: kestrel at mastery LV2 (two 5-kill wins = 100 XP) with
	# variant 1 (unlocked at LV2) selected.
	_wipe_profile()
	var p := PlayerProfile.new()
	p.apply_match(cfg, "kestrel", true, 5, false)
	p.apply_match(cfg, "kestrel", true, 5, false)
	p.set_variant("kestrel", 1)
	var hs := HeroSelect.new()
	hs.profile = p
	hs.progression = cfg
	add_child(hs)
	await _frames(3)
	check("ui: hero-select shows the per-hero mastery line",
			_find_label_text(hs, "MASTERY LV"), "")
	check("ui: hero-select renders one variant dot per palette entry",
			hs._variant_dots.size() == HeroRegistry.heroes().size() * 5,
			"dots=%d" % hs._variant_dots.size())
	var swatch_ok := false
	for c in hs._cards:
		if c.data is HeroData and str(c.data.id) == "kestrel":
			swatch_ok = c.swatch.color == s.palette[1]
	check("ui: card preview shows the selected variant color", swatch_ok, "")
	hs.queue_free()
	await _frames(2)
	await _offline_match(cfg, p, s)

func _offline_match(cfg: ProgressionConfig, p: PlayerProfile,
		s: HeroVariantSet) -> void:
	# Headless main skips the hero-select and starts an offline match with
	# the default hero (kestrel) straight from _ready - using the profile
	# saved below, so its selected variant must be the one the match wears.
	var old_target := MatchConfig.target_score
	MatchConfig.target_score = 1
	_wipe_profile()
	var p2 := PlayerProfile.new()
	p2.apply_match(cfg, "kestrel", true, 5, false)
	p2.apply_match(cfg, "kestrel", true, 5, false)
	p2.set_variant("kestrel", 1)
	PlayerProfile.save_profile_for_test(p2)  # the profile main will load
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await _frames(3)
	var player = null
	for i in 900:
		await _frames(1)
		player = main.player
		if player != null:
			break
	check("ui: offline match starts with the deployed hero",
			player != null, "player=%s" % str(player))
	# (4.7 quirk: find_children type filter is unreliable - walk direct
	# children; the body/team/head meshes are direct children of the hero.)
	var wears := false
	if player != null:
		for c in player.get_children():
			if c is MeshInstance3D:
				var mi: MeshInstance3D = c
				var m = mi.get_surface_override_material(0)
				if m == null and mi.mesh is PrimitiveMesh:
					m = (mi.mesh as PrimitiveMesh).material
				if m is StandardMaterial3D and m.albedo_color == s.palette[1]:
					wears = true
					break
	check("ui: player character wears the selected variant color", wears, "")
	# Headless main quits the tree the moment the world emits match_over
	# (by design - the headless client is a sim run), so build the overlay
	# directly while the match is still live: the _results guard then makes
	# the real match_over event a no-op.
	var info := {"stats": [[0, 1, 0, 50.0], [1, 0, 1, 10.0]],
			"names": ["Kestrel  (you)", "Bot 1"], "hero_id": "kestrel",
			"level": {"xp_gained": 60.0, "level_before": 1, "level_after": 1}}
	main._show_results(0, [1, 0], 6.0, "", info)
	await _frames(3)
	check("ui: results overlay opens for the offline match",
			main._results != null, "")
	check("ui: results screen shows the per-hero mastery line",
			main._results != null and _find_label_text(main._results, "MASTERY"),
			"")
	main.queue_free()
	await _frames(2)
	MatchConfig.target_score = old_target

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
