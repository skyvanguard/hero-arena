class_name EventBank
extends RefCounted
## D29 (events framework): the data-driven event bank.
##
## `events_completed` runs at match end (from PlayerProfile.apply_match,
## after the counters update) against every ACTIVE event whose mode filter
## admits the match: the goal progress is incremented, and when it reaches
## the target the event is marked DONE (one-shot - it never completes
## twice) and its cosmetic reward is granted (a variant unlock in
## profile.event_variant_unlocks - the variant bank takes the max of the
## mastery gate, the achievement grants and the event grants, so the
## cosmetic-only rule holds by construction: no stat field is touched).
const BANK_PATH := "res://content/events/events.tres"
var events: Array = []

static func load_bank() -> EventBank:
	var b := EventBank.new()
	# Untyped on purpose: EventBank is a RefCounted container, not a
	# Resource - a typed Resource return makes the `is` check a parse error.
	var r = ResourceLoader.load(BANK_PATH, "", ResourceLoader.CACHE_MODE_REUSE)
	if r is EventBank:
		# Array is a copy (not the cached resource's); the EventData entries
		# are shared resources - the engine treats them as READ-ONLY (a test
		# that mutates a loaded entry leaks into the cache).
		b.events = r.events.duplicate(false)
	return b

## Content-integrity pass (mirrors AchievementBank/SeasonBank.validate):
## ids, goal sanity, mode ids, reward resolution, unique reward pairs.
static func validate(b: EventBank) -> Array:
	var errs: Array = []
	var seen: Dictionary = {}
	var pairs: Dictionary = {}
	for e in b.events:
		if not (e is EventData):
			errs.append("bad entry")
			continue
		var ev: EventData = e
		if ev.id == "":
			errs.append("empty id")
		elif seen.has(ev.id):
			errs.append("dup id " + ev.id)
		seen[ev.id] = true
		if ev.goal_target < 1:
			errs.append(ev.id + " target < 1")
		if int(ev.goal_kind) < 0 or int(ev.goal_kind) >= EventData.GoalKind.size():
			errs.append(ev.id + " bad goal kind")
		for m in ev.modes:
			if not ModeRegistry.ids().has(str(m)):
				errs.append(ev.id + " bad mode " + str(m))
		if ev.reward_hero != "":
			var key := ev.reward_hero + ":" + str(ev.reward_variant)
			if pairs.has(key):
				errs.append("dup reward " + key)
			pairs[key] = true
			var vs: HeroVariantSet = HeroVariantBank.load_bank().set_for(ev.reward_hero)
			if vs == null or ev.reward_variant < 0 \
					or ev.reward_variant >= vs.palette.size():
				errs.append(ev.id + " reward does not resolve")
	return errs

## Human-readable reward line ("" when none) - cosmetic wording only.
static func reward_text(ev: EventData) -> String:
	if ev.reward_hero == "":
		return ""
	var hero_name: String = ev.reward_hero.to_upper()
	for h in HeroRegistry.HEROES:
		if h is HeroData and str(h.id) == ev.reward_hero:
			hero_name = str(h.display_name).to_upper()
			break
	return "Unlocks %s variant %d (cosmetic)" % [hero_name, ev.reward_variant]

## Evaluate one finished match against every active event (the counters
## are already updated by apply_match). One-shot per event; returns the
## display dicts for the results overlay (same shape as achievements).
## `bank` defaults to the content bank (tests may pass a modified one).
static func events_completed(profile: PlayerProfile, won: bool, is_mvp: bool,
		mode_id: String, bank: EventBank = null) -> Array:
	var out: Array = []
	var b := bank if bank != null else load_bank()
	for e in b.events:
		if not (e is EventData):
			continue
		var ev: EventData = e
		if not ev.active or profile.event_done.has(ev.id):
			continue
		if ev.modes.size() > 0 and not ev.modes.has(mode_id):
			continue
		var counts := false
		match int(ev.goal_kind):
			EventData.GoalKind.MATCHES:
				counts = true
			EventData.GoalKind.WINS:
				counts = won
			EventData.GoalKind.MVP:
				counts = is_mvp
		if not counts:
			continue
		profile.event_progress[ev.id] = \
				int(profile.event_progress.get(ev.id, 0)) + 1
		if int(profile.event_progress[ev.id]) >= ev.goal_target:
			profile.event_done[ev.id] = true
			if ev.reward_hero != "":
				var list: Array = profile.event_variant_unlocks.get(ev.reward_hero, [])
				if not list.has(ev.reward_variant):
					list.append(ev.reward_variant)
					profile.event_variant_unlocks[ev.reward_hero] = list
			out.append({"id": ev.id, "name": ev.display_name, "desc": ev.desc,
					"reward": reward_text(ev)})
	return out

## View rows for the results overlay (mirrors AchievementBank.view_rows).
static func view_rows(completed: Array) -> Array:
	var rows: Array = []
	for c in completed:
		var line := "*DONE*  " + str(c.get("name", ""))
		var rw := str(c.get("reward", ""))
		if rw != "":
			line += "   (" + rw + ")"
		rows.append(line)
	return rows
