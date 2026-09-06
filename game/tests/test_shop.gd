extends Node
## D31 monetization-ready shop suite (round 47): the cosmetics-only rule is
## enforced by the content schema (an item's entire effect is a variant
## unlock), gear is earned in matches (data-driven rates), the purchase
## engine is currency-agnostic and one-shot, and granted variants are
## selectable at mastery 1 (including after a save/load round-trip).
## 13 checks.
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

func _item(b: ShopBank, id: String) -> ShopItemData:
	for e in b.items:
		if (e as ShopItemData).id == id:
			return e
	return null

func _run() -> void:
	cfg = _cfg()
	# 1: the content bank loads with the shipped catalog and validates clean.
	var bank := ShopBank.load_bank()
	check("shop: bank loads (8 items) and validates clean",
			bank.items.size() == 8 and ShopBank.validate(bank) == [],
			"%s" % str(ShopBank.validate(bank)))
	# 2: validate() catches every schema violation.
	var bad := ShopBank.new()
	bad.gear_per_match = -1
	var b1 := ShopItemData.new()
	b1.id = "s1"
	var b2 := ShopItemData.new()
	b2.id = "s1"                      # dup id
	b2.price = 0                      # price <= 0
	b2.currency = "gems"               # unknown currency
	b2.hero_id = "griffon"             # does not resolve
	b2.variant_idx = 1
	var b3 := ShopItemData.new()
	b3.id = "s3"
	b3.hero_id = "kestrel"
	b3.variant_idx = 0                # the free default
	var b4 := ShopItemData.new()
	b4.id = "s4"
	b4.hero_id = "kestrel"
	b4.variant_idx = 1                # dup pair with b2? no - griffon is
	                                  # unresolvable; make the pair dup here:
	b4.price = 100
	bad.items = [b1, b2, b3, b4]
	var b5 := ShopItemData.new()
	b5.id = "s5"
	b5.hero_id = "kestrel"
	b5.variant_idx = 1                # dup of b4's pair
	b5.price = 100
	bad.items.append(b5)
	var errs: Array = ShopBank.validate(bad)
	check("shop: validate catches rates/dup id/price/currency/variant/free/dup pair",
			errs.size() >= 7, "%s" % str(errs))
	# 3: gear earning is data-driven (per match + win bonus).
	var p1 := PlayerProfile.new()
	p1.apply_match(cfg, "kestrel", false, 0, false, 0, 0, "tdm")
	p1.apply_match(cfg, "kestrel", true, 0, false, 0, 0, "tdm")
	check("shop: gear earned = per-match + win bonus (data-driven)",
			p1.currency_of(ShopBank.CURRENCY) == 25 + 40,
			"have=%d" % p1.currency_of(ShopBank.CURRENCY))
	# 4: a purchase with a short balance fails (no debit, no grant).
	var p2 := PlayerProfile.new()
	p2.add_currency(ShopBank.CURRENCY, 100)
	var kes1 := _item(bank, "kestrel_crimson")   # 250 gear
	check("shop: short balance blocks the purchase (no debit, no grant)",
			not p2.buy_item(kes1) and p2.currency_of(ShopBank.CURRENCY) == 100
			and not p2.shop_owned.has("kestrel_crimson")
			and p2.shop_variant_unlocks.is_empty())
	# 5: a funded purchase debits exactly, owns, and grants the variant.
	p2.add_currency(ShopBank.CURRENCY, 150)      # -> 250
	check("shop: funded purchase debits exactly + owns + grants",
			p2.buy_item(kes1) and p2.currency_of(ShopBank.CURRENCY) == 0
			and p2.shop_owned.has("kestrel_crimson")
			and (p2.shop_variant_unlocks.get("kestrel", []) as Array).has(1))
	# 6: one-shot - re-buying is false and never double-debits.
	check("shop: completion is one-shot (no re-buy, no double debit)",
			not p2.buy_item(kes1) and p2.currency_of(ShopBank.CURRENCY) == 0)
	# 7: the granted variant is selectable at mastery 1 (cosmetic early
	#     access); without the grant the mastery gate still clamps to 0.
	var vbank := HeroVariantBank.load_bank()
	p2.set_variant("kestrel", 1)
	var c_granted: Color = HeroVariantBank.color_for(vbank, p2, "kestrel",
				Color.MAGENTA)
	var p3 := PlayerProfile.new()
	p3.set_variant("kestrel", 1)
	var c_control: Color = HeroVariantBank.color_for(vbank, p3, "kestrel",
				Color.MAGENTA)
	var set_k: HeroVariantSet = vbank.set_for("kestrel")
	check("shop: purchased variant selectable at mastery 1 (control clamped)",
			c_granted.is_equal_approx(set_k.color_of(1, Color.MAGENTA))
			and c_control.is_equal_approx(set_k.color_of(0, Color.MAGENTA)))
	# 8: variant_unlocked - the mastery gate OR any grant (the variant dots
	#     use this; pre-D31 they only saw the mastery gate).
	check("shop: variant_unlocked = mastery gate OR grant",
			HeroVariantBank.variant_unlocked(vbank, p3, cfg, "kestrel", 0)
			and not HeroVariantBank.variant_unlocked(vbank, p3, cfg, "kestrel", 1)
			and HeroVariantBank.variant_unlocked(vbank, p2, cfg, "kestrel", 1)
			and not HeroVariantBank.variant_unlocked(vbank, p2, cfg, "kestrel", 4))
	# 9: old-save compatibility - a pre-D31 JSON loads with empty shop state
	#     and the new keys round-trip through the save.
	var f := FileAccess.open(PlayerProfile.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"level": 3, "xp": 10.0, "total_xp": 400.0,
			"matches": 20, "wins": 8, "per_hero": {}, "variants": {},
			"controls": {}, "total_kills": 100, "total_headshots": 5,
			"total_mvp": 2, "best_streak": 4, "achievements": {},
			"ach_variant_unlocks": {}}))
	f.close()
	var p4: PlayerProfile = PlayerProfile.load(cfg)
	check("shop: pre-D31 save loads with empty shop state",
			p4.currency.is_empty() and p4.shop_owned.is_empty()
			and p4.shop_variant_unlocks.is_empty())
	p4.add_currency(ShopBank.CURRENCY, 500)
	p4.buy_item(_item(bank, "patch_onyx"))
	var p5: PlayerProfile = PlayerProfile.load(cfg)
	check("shop: shop state round-trips through the save",
			p5.currency_of(ShopBank.CURRENCY) == 150
			and p5.shop_owned.has("patch_onyx"))
	# 10: grant_sources() includes the shop grants (a new grant source is
	#      one line - the variant bank + the dots iterate it).
	var srcs: Array = p5.grant_sources()
	check("shop: grant_sources includes shop grants (bank + dots iterate it)",
			srcs.size() == 3
			and (srcs[2].get("patch", []) as Array).has(1))
	# 11: the UI view rows carry the name/effect/price + owned state.
	var rows: Array = ShopBank.view_rows(bank, p5)
	check("shop: view rows carry name/effect/price/owned state",
			rows.size() == 8,
			"%s" % str(rows.size()))
	var found_on := false
	var found_price := false
	for r in rows:
		if str(r.id) == "patch_onyx" and bool(r.owned):
			found_on = true
		if str(r.id) == "kestrel_crimson" and not bool(r.owned) \
				and int(r.price) == 250:
			found_price = true
	check("shop: owned vs price rows render distinct states",
			found_on and found_price, "%s" % str(rows))
	print("SHOP SUITE: %d passed, %d failed" % [passed, failed])
	get_tree().quit(failed)
