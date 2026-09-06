class_name ShopBank
extends RefCounted
## D31 (monetization-ready shop): the data-driven shop catalog + the
## in-match earning rates for the "gear" currency.
##
## Gear is earned in matches (data-driven rates below) and spent in the
## shop. No real money is involved anywhere in this code path; the
## currency ledger (profile.currency) and the purchase engine are
## currency-agnostic so a payment provider can add currencies later.
const BANK_PATH := "res://content/shop/shop.tres"
const CURRENCY := "gear"
var items: Array = []
## Gear earned per match played / per win (data-driven, no magic numbers).
var gear_per_match := 25
var gear_per_win := 15

static func load_bank() -> ShopBank:
	var b := ShopBank.new()
	# Untyped on purpose: ShopBank is a RefCounted container, not a
	# Resource - a typed Resource return makes the `is` check a parse
	# error (same reason as EventBank/AchievementBank).
	var r = ResourceLoader.load(ModLoader.resolve(BANK_PATH), "", ResourceLoader.CACHE_MODE_REUSE)
	if r is ShopBank:
		b.items = r.items.duplicate(false)
		b.gear_per_match = r.gear_per_match
		b.gear_per_win = r.gear_per_win
	return b

## Gear a finished match earns (participation + win bonus).
static func gear_for(won: bool) -> int:
	var b := load_bank()
	var g := int(b.gear_per_match)
	if won:
		g += int(b.gear_per_win)
	return g

## Content-integrity pass: ids, pricing, reward resolution, the no-free-
## default rule, unique (hero, variant) pairs, known currencies.
static func validate(b: ShopBank) -> Array:
	var errs: Array = []
	var seen: Dictionary = {}
	var pairs: Dictionary = {}
	if int(b.gear_per_match) < 0 or int(b.gear_per_win) < 0:
		errs.append("negative earn rate")
	for e in b.items:
		if not (e is ShopItemData):
			errs.append("bad entry")
			continue
		var it: ShopItemData = e
		if it.id == "":
			errs.append("empty id")
		elif seen.has(it.id):
			errs.append("dup id " + it.id)
		seen[it.id] = true
		if it.price <= 0:
			errs.append(it.id + " price <= 0")
		if it.currency != CURRENCY:
			errs.append(it.id + " unknown currency " + it.currency)
		if it.variant_idx < 0 or it.variant_idx >= _palette_size(it.hero_id):
			errs.append(it.id + " variant does not resolve")
		if it.variant_idx == 0:
			errs.append(it.id + " sells the free default variant")
		var key := it.hero_id + ":" + str(it.variant_idx)
		if pairs.has(key):
			errs.append("dup pair " + key)
		pairs[key] = true
	return errs

static func _palette_size(hero_id: String) -> int:
	var vs: HeroVariantSet = HeroVariantBank.load_bank().set_for(hero_id)
	return vs.palette.size() if vs != null else 0

## View rows for the shop UI: display name, effect wording, price, state.
static func view_rows(b: ShopBank, profile: PlayerProfile) -> Array:
	var rows: Array = []
	for e in b.items:
		if not (e is ShopItemData):
			continue
		var it: ShopItemData = e
		var hero_name: String = it.hero_id.to_upper()
		for h in HeroRegistry.HEROES:
			if h is HeroData and str(h.id) == it.hero_id:
				hero_name = str(h.display_name).to_upper()
				break
		rows.append({"id": it.id, "name": it.display_name, "desc": it.desc,
				"effect": hero_name + " variant " + str(it.variant_idx + 1),
				"price": it.price, "currency": it.currency,
				"owned": profile.shop_owned.has(it.id)})
	return rows
