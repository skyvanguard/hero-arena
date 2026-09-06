extends Node
## D29 events framework suite (round 46): data-driven limited-time events
## (participation/win/objective rewards; cosmetic-only; no hero-forcing).
## Covers: bank integrity + validate() catches, participation goal exact
## threshold, mode filters (single + multi-mode), inactive events, one-shot
## completion (no re-grant), the reward variant selectable at mastery 1
## (cosmetic early access) with the mastery-gate control, cosmetic-only
## mastery regression, the apply_match integration (events_completed key,
## old call sites without mode_id), old-save compatibility, and the overlay
## view rows. 15 checks.
var cfg: ProgressionConfig
var passed := 0
var failed := 0

func _ready() -> void:
	_run()

func _cfg() -> ProgressionConfig:
	var r = load("res://content/progression.tres")
	return r if r is ProgressionConfig else ProgressionConfig.new()

func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		passed += 1
		print("  ok  " + name)
	else:
		failed += 1
		printerr("  FAIL " + name + ("  [" + detail + "]" if detail != "" else ""))

func _ids(u: Array) -> Array:
	var out: Array = []
	for x in u:
		out.append(str(x.get("id", "")))
	return out

func _run() -> void:
	cfg = _cfg()
	# 1: the content bank loads with the shipped events and validates clean.
	var bank := EventBank.load_bank()
	check("events: bank loads (3 events) and validates clean",
			bank.events.size() == 3 and EventBank.validate(bank) == [],
			"%s" % str(EventBank.validate(bank)))
	# 2: validate() catches bad content (mode id, reward resolution, dup id).
	var bad := EventBank.new()
	var be1 := EventData.new()
	be1.id = "b1"
	be1.modes = ["moonbase"]
	var be2 := EventData.new()
	be2.id = "b1"
	be2.reward_hero = "kestrel"
	be2.reward_variant = 99
	bad.events = [be1, be2]
	var verrs: Array = EventBank.validate(bad)
	check("events: validate catches bad mode, dup id, unresolvable reward",
			verrs.size() >= 3,
			"%s" % str(verrs))
	# 3: participation (forge_week: 10 matches) - exact threshold.
	var p1 := PlayerProfile.new()
	for i in 9:
		p1.apply_match(cfg, "kestrel", false, 0, false, 0, 0, "tdm")
	check("events: 9 of 10 participation matches -> progress 9, no completion",
			int(p1.event_progress.get("forge_week", -1)) == 9
			and not p1.event_done.has("forge_week"))
	var r10: Dictionary = p1.apply_match(cfg, "kestrel", false, 0, false, 0, 0, "tdm")
	check("events: the 10th match completes forge_week + grants the reward",
			p1.event_done.has("forge_week")
			and _ids(r10.events_completed).has("forge_week")
			and (p1.event_variant_unlocks.get("bastion", []) as Array).has(2),
			"%s" % str(r10.events_completed))
	# 4: mode filter - capture_push only counts capture wins.
	var p2 := PlayerProfile.new()
	p2.apply_match(cfg, "blitz", true, 0, false, 0, 0, "tdm")
	check("events: a tdm win does not count for the capture event",
			int(p2.event_progress.get("capture_push", 0)) == 0)
	p2.apply_match(cfg, "blitz", true, 0, false, 0, 0, "capture")
	check("events: a capture win counts (progress 1)",
			int(p2.event_progress.get("capture_push", -1)) == 1)
	# 5: multi-mode objective event - tdm MVP excluded, escort MVP counted.
	var p3 := PlayerProfile.new()
	p3.apply_match(cfg, "mira", true, 3, true, 0, 0, "tdm")
	p3.apply_match(cfg, "mira", true, 3, true, 0, 0, "escort")
	check("events: objective event filters tdm, counts escort MVPs",
			int(p3.event_progress.get("objective_sprint", -1)) == 1)
	# 6: an inactive event never progresses (a standalone bank with a FRESH
	#     entry - mutating the cached content resource would leak across the
	#     whole suite, so the test uses its own object).
	var bank_off := EventBank.new()
	var ev_off := EventData.new()
	ev_off.id = "forge_week"
	ev_off.active = false
	ev_off.goal_target = 10
	bank_off.events = [ev_off]
	var p4 := PlayerProfile.new()
	EventBank.events_completed(p4, false, false, "tdm", bank_off)
	check("events: an inactive event never progresses",
			int(p4.event_progress.get("forge_week", 0)) == 0)
	# 7: one-shot - after completion no re-complete, no duplicate grant.
	var r11: Dictionary = p1.apply_match(cfg, "kestrel", false, 0, false, 0, 0, "tdm")
	check("events: completion is one-shot (no re-grant, no dup variant)",
			not _ids(r11.events_completed).has("forge_week")
			and (p1.event_variant_unlocks.get("bastion", []) as Array).count(2) == 1)
	# 8: the reward makes variant 2 selectable at mastery 1 (cosmetic early
	#     access); without the grant the mastery gate still clamps to 0.
	var vbank := HeroVariantBank.load_bank()
	p1.set_variant("bastion", 2)
	var c_granted: Color = HeroVariantBank.color_for(vbank, p1, "bastion",
				Color.MAGENTA)
	var p5 := PlayerProfile.new()
	p5.set_variant("bastion", 2)
	var c_control: Color = HeroVariantBank.color_for(vbank, p5, "bastion",
				Color.MAGENTA)
	var set_b: HeroVariantSet = vbank.set_for("bastion")
	check("events: granted variant selectable at mastery 1 (control clamped)",
			c_granted.is_equal_approx(set_b.color_of(2, Color.MAGENTA))
			and c_control.is_equal_approx(set_b.color_of(0, Color.MAGENTA)))
	# 9: cosmetic-only - the mastery progression math itself is driven by
	#     the per-hero stats (the event grant touches none of it).
	var p6 := PlayerProfile.new()
	for i in 3:
		p6.apply_match(cfg, "mira", true, 4, true, 0, 0, "escort")
	var after: Dictionary = p6.mastery_progress_of(cfg, "mira")
	check("events: completion is cosmetic-only (mastery = stats, grant untouched)",
			int(after.get("level", 0)) == 2
			and p6.event_done.has("objective_sprint"),
			"%s" % str(after))
	# 10: apply_match integration - the old 7-arg call site (no mode_id) keeps
	#      working and mode-filtered events simply do not count it.
	var p7 := PlayerProfile.new()
	var r_old: Dictionary = p7.apply_match(cfg, "mira", true, 0, true)
	check("events: old 7-arg call site works; mode-filtered events idle",
			r_old.has("events_completed")
			and (r_old.events_completed as Array).size() == 0
			and int(p7.event_progress.get("objective_sprint", 0)) == 0
			and int(p7.event_progress.get("forge_week", 0)) == 1,
			"has=%s size=%s obj=%s forge=%s" % [r_old.has("events_completed"),
				(r_old.events_completed as Array).size(),
				p7.event_progress.get("objective_sprint", 0),
				p7.event_progress.get("forge_week", 0)])
	# 11: old-save compatibility - a pre-D29 JSON loads with empty event
	#      state and the new keys round-trip through the save.
	var f := FileAccess.open(PlayerProfile.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"level": 3, "xp": 10.0, "total_xp": 400.0,
			"matches": 20, "wins": 8, "per_hero": {}, "variants": {},
			"controls": {}, "total_kills": 100, "total_headshots": 5,
			"total_mvp": 2, "best_streak": 4, "achievements": {},
			"ach_variant_unlocks": {}}))
	f.close()
	var p8: PlayerProfile = PlayerProfile.load(cfg)
	check("events: pre-D29 save loads with empty event state",
			p8.event_progress.is_empty() and p8.event_done.is_empty()
			and p8.event_variant_unlocks.is_empty())
	p8.apply_match(cfg, "mira", true, 0, false, 0, 0, "tdm")
	var p9: PlayerProfile = PlayerProfile.load(cfg)
	check("events: event state round-trips through the save",
			int(p9.event_progress.get("forge_week", -1)) == 1,
			"p8=%s p9=%s" % [str(p8.event_progress), str(p9.event_progress)])
	# 12: the overlay view rows carry the name + the cosmetic reward wording.
	var rows: Array = EventBank.view_rows([{"name": "Forge Week",
			"reward": "Unlocks BASTION variant 2 (cosmetic)"},
			{"name": "Plain Event", "reward": ""}])
	check("events: view rows carry name + reward wording",
			rows.size() == 2 and str(rows[0]).contains("Forge Week")
			and str(rows[0]).contains("BASTION")
			and not str(rows[1]).contains("("),
			"%s" % str(rows))
	print("EVENTS SUITE: %d passed, %d failed" % [passed, failed])
	get_tree().quit(failed)
