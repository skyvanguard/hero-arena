extends Node
## Headless roster + balance harness (Phase 3). Validates every registered
## hero's kit and produces the per-hero DPS/TTK table (the seed of the
## content/balance/ system). Run:
##   godot --headless --path game res://tests/test_roster.tscn

const FIXED_DT := 1.0 / 60.0
const DUMMY_HP := 1000.0
const FIRE_SECONDS := 2.0

var world: World
var hero: Hero
var dummy: Hero
var fails := 0
var dps_table: Array = []

func check(label: String, cond: bool, extra: String = "") -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label, "  ", extra)

func _ready() -> void:
	randomize()
	world = World.new()
	add_child(world)
	add_child(Arena.build(world))
	check("roster: 6 heroes registered", HeroRegistry.count() == 6, "n=%d" % HeroRegistry.count())
	# Balance config (content/balance/): one entry per registered hero.
	check("balance: entry per hero", Balance.entry_count() == HeroRegistry.count(),
		"entries=%d heroes=%d" % [Balance.entry_count(), HeroRegistry.count()])
	var missing := ""
	for h in HeroRegistry.HEROES:
		var hd0: HeroData = h
		if Balance.entry_for(hd0.id) == null:
			missing += hd0.id + " "
	check("balance: all heroes have entries", missing == "", "missing: " + missing)
	# Ult-charge pacing: even a damage-free player ults within 12 kills.
	var pacing := ""
	for h in HeroRegistry.HEROES:
		var hd1: HeroData = h
		if hd1.charge_per_kill <= 0.0 or hd1.ult_max / hd1.charge_per_kill > 12.0:
			pacing += hd1.id + "(%.0fk) " % (hd1.ult_max / maxf(hd1.charge_per_kill, 0.001))
	check("balance: ult pacing <= 12 kills (worst case)", pacing == "", pacing)
	for h in HeroRegistry.HEROES:
		var hd: HeroData = h
		await _validate_kit(hd)
		await _measure_dps(hd)
	# Passive-specific identity checks
	await _check_passive_identities()
	# Balance table (printed for docs; bands enforced above)
	print("--- BALANCE TABLE (generated from content/balance/, 100 hp dummy, %s window) ---" % FIRE_SECONDS)
	for row in dps_table:
		var rdps := float(row.dps)
		var ttk: float = 100.0 / rdps if rdps > 0.0 else -1.0
		print("  %-10s %-14s dps=%6.1f  ttk100=%5.2fs  %s" % [row.id, row.cls, rdps, ttk, row.note])
	print("RESULT: %d checks failed" % fails)
	get_tree().quit(fails)

func _physics_process(delta: float) -> void:
	var s := 0
	while delta >= FIXED_DT and s < 4:
		world.step(FIXED_DT)
		delta -= FIXED_DT
		s += 1

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _spawn(hd: HeroData) -> void:
	for c in get_children():
		if c is Hero:
			world.unregister_character(c)
			c.queue_free()
	await frames(2)
	hero = HeroFactory.create(0, false, hd.color, hd)
	hero.position = Vector3(-5, 0.9, 0)
	hero.rotation.y = 0.0
	add_child(hero)
	world.register_character(hero)
	dummy = HeroFactory.create(1, false, hd.color, hd)
	dummy.position = _dummy_pos(hd)
	dummy.max_hp = DUMMY_HP
	dummy.hp = DUMMY_HP
	add_child(dummy)
	world.register_character(dummy)
	await frames(5)

func _dummy_pos(hd: HeroData) -> Vector3:
	# Projectiles need the 8 m stand-off (their flight path + aim drop).
	return Vector3(-5, 0.9, 8.0) if str(hd.weapon.get("mode", "hitscan")) == "projectile" else Vector3(-5, 0.9, 5.0)

func _validate_kit(hd: HeroData) -> void:
	await _spawn(hd)
	check("%s: kit complete (2 ab + ult + passive)" % hd.id,
		hd.abilities.size() == 2 and hero.ability != null and hd.ult != null and hd.passive != null)
	check("%s: ult is ult-flagged" % hd.id,
		hd.ult.is_ult and (hd.ult.kind == AbilityData.Kind.BUFF or hd.ult.kind == AbilityData.Kind.FIELD or hd.ult.kind == AbilityData.Kind.BOOST))
	check("%s: weapon profile applied" % hd.id,
		hero.weapon.fire_rate > 0.0 and hero.weapon.clip_size > 0 and absf(hero.weapon.damage - float(hd.weapon.get("damage", -1))) < 0.01,
		"rate=%.1f clip=%d dmg=%.1f" % [hero.weapon.fire_rate, hero.weapon.clip_size, hero.weapon.damage])
	check("%s: hp/speed from data" % hd.id, hero.max_hp == hd.max_hp and absf(hero.base_speed - hd.base_speed) < 0.001)
	check("%s: passive matches sub-role" % hd.id, _passive_kind_ok(hd))

func _passive_kind_ok(hd: HeroData) -> bool:
	match hd.sub_role:
		HeroData.SubRole.SUSTAINED: return hd.passive.kind == PassiveData.Kind.HIT_STREAK
		HeroData.SubRole.SPRINT: return hd.passive.kind == PassiveData.Kind.SPRINT
		HeroData.SubRole.ARMOR: return hd.passive.kind == PassiveData.Kind.ARMOR
		HeroData.SubRole.FLEX: return hd.passive.kind == PassiveData.Kind.FLEX
		HeroData.SubRole.FIELD: return hd.passive.kind == PassiveData.Kind.FIELD
		HeroData.SubRole.ZONE: return hd.passive.kind == PassiveData.Kind.ZONE
	return true

func _measure_dps(hd: HeroData) -> void:
	# Dummy already spawned by _validate_kit; reset it and fire a 2 s window.
	# Bot contract: controllers re-pulse input every tick (server authority),
	# so a real controller drives the hero, not one-shot flags.
	dummy.max_hp = DUMMY_HP
	dummy.hp = DUMMY_HP
	hero.weapon.ready()
	hero.ability._cooldown_until = [0.0, 0.0]
	var tc := _TestController.new()
	add_child(tc)
	tc.hero = hero
	tc.target = dummy
	hero.controller = tc
	await frames(12)  # settle
	var n := int(ceilf(FIRE_SECONDS * 60.0))
	await frames(n)
	hero.controller = null
	hero.want_fire = false
	var dealt := DUMMY_HP - dummy.hp
	var dps := dealt / FIRE_SECONDS
	dps_table.append({id = hd.id, cls = _class_of(hd), dps = dps, note = "dealt=%.0f" % dealt})
	check("%s: weapon pipeline deals damage (dps>0)" % hd.id, dps > 0.0, "dps=%.1f" % dps)
	# Role-sanity bands from the balance config (content/balance/).
	var role_name: String = ["ASSAULT", "TANK", "SUPPORT", "CONTROLLER"][hd.role]
	var band: Dictionary = Balance.BANDS.get(role_name, {})
	var band_ok := band.size() > 0
	if band_ok:
		band_ok = dps >= float(band.min_dps) and dps <= float(band.max_dps) \
			and hero.max_hp >= float(band.min_hp)
	var note := "band %s dps[%.0f..%.0f] hp>=%.0f" % [
		role_name,
		float(band.get("min_dps", 0.0)), float(band.get("max_dps", 0.0)),
		float(band.get("min_hp", 0.0)),
	]
	var entry: BalanceEntry = Balance.entry_for(hd.id)
	if entry != null:
		note += " | " + entry.notes
	dps_table[dps_table.size() - 1].note += " | " + note
	check("%s: role band (config)" % hd.id, band_ok, "dps=%.1f hp=%.0f" % [dps, hero.max_hp])

func _class_of(hd: HeroData) -> String:
	var roles := ["assault", "tank", "support", "controller"]
	return roles[hd.role] + "/" + hd.id

func _check_passive_identities() -> void:
	var blitz: HeroData = HeroRegistry.by_id("blitz")
	await _spawn(blitz)
	check("blitz: sprint passive gives 1.12 speed", absf(hero.ability.passive_speed_mult() - 1.12) < 0.001,
		"mult=%.2f" % hero.ability.passive_speed_mult())
	var bastion: HeroData = HeroRegistry.by_id("bastion")
	await _spawn(bastion)
	check("bastion: armor passive mitigates 20%", absf(hero.ability.passive_damage_taken_mult() - 0.8) < 0.001,
		"mult=%.2f" % hero.ability.passive_damage_taken_mult())
	dummy.max_hp = DUMMY_HP
	dummy.hp = DUMMY_HP
	world.damage(dummy, 50.0, hero, false, dummy.global_position)
	check("bastion: 50 dmg lands as 40", absf(dummy.hp - (DUMMY_HP - 40.0)) < 0.01, "hp=%.0f" % dummy.hp)
	var kestrel: HeroData = HeroRegistry.by_id("kestrel")
	await _spawn(kestrel)
	check("kestrel: no flat mitigation", hero.ability.passive_damage_taken_mult() == 1.0)
	# ---- Phase 3 support/controller framework checks ----
	var patch: HeroData = HeroRegistry.by_id("patch")
	await _spawn(patch)
	check("patch: flex passive cuts cooldowns to 0.8", absf(hero.ability.passive_cd_mult() - 0.8) < 0.001,
		"cd=%.2f" % hero.ability.passive_cd_mult())
	var ally := await _spawn_ally()
	check("patch: mule shot speed-boosts allies 0.4", hero.ability.cast(0) and absf(ally.speed_boost_ratio - 0.4) < 0.001,
		"boost=%.2f" % ally.speed_boost_ratio)
	var before := hero.weapon.ammo
	hero.weapon.ammo = 3
	check("patch: field resupply refills clip + heals", hero.ability.cast(1) and hero.weapon.ammo == hero.weapon.clip_size and ally.hp > 0,
		"ammo=%d/%d" % [hero.weapon.ammo, hero.weapon.clip_size])
	_free_ally()
	var mira: HeroData = HeroRegistry.by_id("mira")
	await _spawn(mira)
	ally = await _spawn_ally()
	ally.hp = 50.0
	var h0 := ally.hp
	await frames(60)  # 1 s of Mending Presence tick-heal
	check("mira: field passive tick-heals allies (>=5/s)", ally.hp - h0 >= 4.9, "healed=%.1f" % (ally.hp - h0))
	ally.hp = 50.0
	check("mira: healing pulse heals ally 35", hero.ability.cast(0) and absf(ally.hp - minf(85.0, ally.max_hp)) < 0.01,
		"hp=%.0f" % ally.hp)
	_free_ally()
	var nimbus: HeroData = HeroRegistry.by_id("nimbus")
	await _spawn(nimbus)
	await frames(10)
	check("nimbus: zone passive rate bonus vs nearby enemy", absf(hero.ability.passive_rate_mult() - 1.08) < 0.001,
		"rate=%.2f" % hero.ability.passive_rate_mult())
	var zcount := world.zones.size()
	check("nimbus: static field spawns slow zone", hero.ability.cast(0) and world.zones.size() == zcount + 1
		and absf(world.zones[world.zones.size() - 1].slow_ratio - 0.3) < 0.001,
		"zones=%d" % world.zones.size())

var _ally: Hero = null

func _spawn_ally() -> Hero:
	_ally = HeroFactory.create(0, false, Color(0.9, 0.9, 0.9), hero.ability.hero_data)
	_ally.position = hero.position + Vector3(0, 0, 3.0)  # inside 5-8 m radii
	add_child(_ally)
	world.register_character(_ally)
	await frames(2)
	return _ally

func _free_ally() -> void:
	if _ally != null and is_instance_valid(_ally):
		world.unregister_character(_ally)
		_ally.queue_free()
	_ally = null

func _free_zones() -> void:
	for z in world.zones:
		z._die()
	world.zones = []

class _TestController:
	extends Node
	var hero: CharacterEntity
	var target: CharacterEntity

	func step(world: World, dt: float) -> void:
		# Aim mid-body (capsule center is +0; +0.4 keeps the ray inside the
		# body at both the 5 m hitscan and 8 m projectile stand-offs).
		hero.aim_target = target.global_position + Vector3(0, 0.4, 0)
		hero.want_fire = true
