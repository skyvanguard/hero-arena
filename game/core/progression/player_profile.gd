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
## hero_id -> {"plays": int, "wins": int, "kills": int, "mvp": int}
## (mastery seed, D22: mastery is a pure function of these stats).
var per_hero: Dictionary = {}
## D22 cosmetic variant selection: hero_id -> palette index (0 = default).
var variants: Dictionary = {}
## D26 achievement counters (cumulative, server-stat-derived, cosmetic).
var total_kills := 0
var total_headshots := 0
var total_mvp := 0
var best_streak := 0
## D26: id -> true (one-shot; never re-unlocks).
var achievements: Dictionary = {}
## D26: hero_id -> Array[variant_idx] unlocked by achievements (cosmetic
## early access; the mastery gate still applies on top - the variant bank
## takes the max of both).
var ach_variant_unlocks: Dictionary = {}
## D29: event id -> int (progress toward the event goal).
var event_progress: Dictionary = {}
## D29: event id -> true (one-shot; an event never completes twice).
var event_done: Dictionary = {}
## D29: hero_id -> Array[variant_idx] unlocked by events (cosmetic early
## access; the variant bank takes the max of mastery + ach + event grants).
var event_variant_unlocks: Dictionary = {}
## D31: currency_id -> int ("gear" is earned in matches; no real money).
var currency: Dictionary = {}
## D31: shop item id -> true (one-shot; never re-bought).
var shop_owned: Dictionary = {}
## D31: hero_id -> Array[variant_idx] unlocked by shop purchases (cosmetic).
var shop_variant_unlocks: Dictionary = {}
## D24 control customization (ControlSettings.to_dict(); old saves default
## {} = stock layout).
var controls: Dictionary = {}

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
			# Old saves (pre-D22) have no variants block - default (0) wins.
			p.variants = d.get("variants", {})
			# Old saves (pre-D24) have no controls block - stock layout wins.
			p.controls = d.get("controls", {})
			# Old saves (pre-D26) have no achievement block - defaults win.
			p.total_kills = int(d.get("total_kills", 0))
			p.total_headshots = int(d.get("total_headshots", 0))
			p.total_mvp = int(d.get("total_mvp", 0))
			p.best_streak = int(d.get("best_streak", 0))
			p.achievements = d.get("achievements", {})
			p.ach_variant_unlocks = d.get("ach_variant_unlocks", {})
			# Old saves (pre-D29) have no event blocks - defaults win.
			p.event_progress = d.get("event_progress", {})
			p.event_done = d.get("event_done", {})
			p.event_variant_unlocks = d.get("event_variant_unlocks", {})
			# Old saves (pre-D31) have no shop blocks - defaults win.
			p.currency = d.get("currency", {})
			p.shop_owned = d.get("shop_owned", {})
			p.shop_variant_unlocks = d.get("shop_variant_unlocks", {})
			# JSON round-trips ints as floats - normalize the cosmetic grant
			# lists to ints so Array.has(int) works after a reload (buy_item
			# dedup, the variant dots, color_for).
			for src in [p.ach_variant_unlocks, p.event_variant_unlocks,
					p.shop_variant_unlocks]:
				for h in src.keys():
					var norm: Array = []
					for v in src[h]:
						norm.append(int(v))
					src[h] = norm
	return p

## Test helper: serialize this profile straight to the save path without
## the per-call save() side effects the gameplay path already performs.
static func save_profile_for_test(p: PlayerProfile) -> void:
	p.save()

func save() -> void:
	var d := {"level": level, "xp": xp, "total_xp": total_xp,
		"matches": matches, "wins": wins, "per_hero": per_hero,
		"variants": variants, "controls": controls,
		"total_kills": total_kills, "total_headshots": total_headshots,
		"total_mvp": total_mvp, "best_streak": best_streak,
		"achievements": achievements, "ach_variant_unlocks": ach_variant_unlocks,
		"event_progress": event_progress, "event_done": event_done,
		"event_variant_unlocks": event_variant_unlocks,
		"currency": currency, "shop_owned": shop_owned,
		"shop_variant_unlocks": shop_variant_unlocks}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))
		f.close()

## Apply one finished match. headshots/match_streak are D26 (achievement
## counters); they default so pre-D26 call sites keep working. mode_id is
## D29 (event mode filters); it defaults to "" (old call sites: events
## with a mode filter simply do not count them). Returns
## {xp_gained, level_before, level_after, achievements_unlocked,
## events_completed} for the results screen.
func apply_match(cfg: ProgressionConfig, hero_id: String, won: bool,
		kills: int, is_mvp: bool, headshots: int = 0,
		match_streak: int = 0, mode_id: String = "") -> Dictionary:
	var gained := (cfg.xp_win if won else cfg.xp_lose) \
			+ float(kills) * cfg.xp_kill \
			+ (cfg.xp_mvp if is_mvp else 0.0)
	var before := level
	xp += gained
	total_xp += gained
	matches += 1
	if won:
		wins += 1
	total_kills += kills
	total_headshots += maxi(headshots, 0)
	best_streak = maxi(best_streak, maxi(match_streak, 0))
	if is_mvp:
		total_mvp += 1
	var h: Dictionary = per_hero.get(hero_id, {})
	h["plays"] = int(h.get("plays", 0)) + 1
	h["wins"] = int(h.get("wins", 0)) + (1 if won else 0)
	h["kills"] = int(h.get("kills", 0)) + kills
	h["mvp"] = int(h.get("mvp", 0)) + (1 if is_mvp else 0)
	per_hero[hero_id] = h
	while xp >= cfg.xp_for_level(level):
		xp -= cfg.xp_for_level(level)
		level += 1
	# D26: one-shot achievement evaluation (cosmetic rewards only).
	var unlocked: Array = AchievementBank.newly_unlocked(self)
	# D29: event progress + one-shot completions (cosmetic rewards only).
	var events := EventBank.events_completed(self, won, is_mvp, mode_id)
	# D31: gear earning (data-driven rates; the only currency today).
	var gear: int = ShopBank.gear_for(won)
	if gear > 0:
		add_currency(ShopBank.CURRENCY, gear)
	save()
	return {"xp_gained": gained, "level_before": before, "level_after": level,
		"achievements_unlocked": unlocked, "events_completed": events}

## D31: every cosmetic grant source (achievement / event / shop variant
## unlocks) - the variant bank + the variant dots iterate this list, so
## a new grant source is one line here and it is honored everywhere.
func grant_sources() -> Array:
	return [ach_variant_unlocks, event_variant_unlocks, shop_variant_unlocks]

## D31: currency ledger (currency-agnostic - "gear" today; a payment
## provider can add currencies without touching this path).
func add_currency(id: String, amount: int) -> void:
	currency[id] = int(currency.get(id, 0)) + int(amount)

func currency_of(id: String) -> int:
	return int(currency.get(id, 0))

## D31: the purchase engine (cosmetic-only by schema - see
## ShopItemData). One-shot per item; false when already owned or the
## balance is short. Grants the item's cosmetic variant on success.
func buy_item(item: ShopItemData) -> bool:
	if shop_owned.has(item.id):
		return false
	if currency_of(item.currency) < item.price:
		return false
	currency[item.currency] = currency_of(item.currency) - item.price
	shop_owned[item.id] = true
	var list: Array = shop_variant_unlocks.get(item.hero_id, [])
	if not list.has(item.variant_idx):
		list.append(item.variant_idx)
		shop_variant_unlocks[item.hero_id] = list
	save()
	return true

## D22: select a cosmetic variant (index 0 = the hero's default color).
## The UI validates the unlock; the accessor clamps defensively.
func set_variant(hero_id: String, idx: int) -> void:
	variants[hero_id] = maxi(idx, 0)
	save()

func selected_variant(hero_id: String) -> int:
	return int(variants.get(hero_id, 0))

## D24: read the persisted control customization (clamped, stock defaults
## for old saves).
func control_settings() -> ControlSettings:
	return ControlSettings.from_dict(controls)

## D24: store the control customization and persist immediately (same
## pattern as set_variant - the settings panel edits are final on tap).
func set_control_settings(cs: ControlSettings) -> void:
	cs.clamp_all()
	controls = cs.to_dict()
	save()

## D22: per-hero mastery XP as a pure function of the stat seed (no
## separate store - old saves and mid-file edits can never drift).
func mastery_xp_of(cfg: ProgressionConfig, hero_id: String) -> float:
	var h: Dictionary = per_hero.get(hero_id, {})
	return float(int(h.get("plays", 0))) * cfg.mastery_match \
			+ float(int(h.get("wins", 0))) * cfg.mastery_win \
			+ float(int(h.get("kills", 0))) * cfg.mastery_kill \
			+ float(int(h.get("mvp", 0))) * cfg.mastery_mvp

## D22: mastery level + progress {level, xp_into, need} using the shared
## level curve.
func mastery_progress_of(cfg: ProgressionConfig, hero_id: String) -> Dictionary:
	var total := mastery_xp_of(cfg, hero_id)
	var lvl := 1
	while total >= cfg.xp_for_level(lvl):
		total -= cfg.xp_for_level(lvl)
		lvl += 1
	return {"level": lvl, "xp_into": total, "need": cfg.xp_for_level(lvl)}

func mastery_level_of(cfg: ProgressionConfig, hero_id: String) -> int:
	return int(mastery_progress_of(cfg, hero_id).level)
