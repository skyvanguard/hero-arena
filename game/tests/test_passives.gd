extends Node

# Phase 7 (item 2): role/sub-role PASSIVE behavior suite. Every one of the
# six passives is exercised through the real pipeline (not just getters),
# plus the stacking rules (passive x perk x ult are multiplicative) and the
# identity-coverage rule (one passive per sub-role, no two heroes share an
# identity). Run: godot --headless --path game res://tests/test_passives.tscn

const FIXED_DT := 1.0 / 60.0

var ok := 0
var fail := 0
var world: World

func check(label: String, cond: bool, extra: String = "") -> void:
	if cond:
		ok += 1
		print("  ok  " + label)
	else:
		fail += 1
		print("  FAIL " + label + ("  [" + extra + "]" if extra != "" else ""))

func _ready() -> void:
	world = World.new()
	world.name = "World"
	add_child(world)
	add_child(Arena.build(world))

	# ---- identity coverage: 6 heroes, 6 distinct passive kinds/ids ----
	var ids: Array = []
	var kinds: Array = []
	var missing := ""
	for h in HeroRegistry.HEROES:
		var hd: HeroData = h
		if hd.passive == null:
			missing += hd.id + " "
		else:
			ids.append(hd.passive.id)
			kinds.append(hd.passive.kind)
	check("identity: every hero has a named passive", missing == "", "missing: " + missing)
	var uid: Array = []
	for v in ids:
		if not uid.has(v):
			uid.append(v)
	var uki: Array = []
	for v in kinds:
		if not uki.has(v):
			uki.append(v)
	check("identity: 6 unique passive ids", ids.size() == 6 and uid.size() == 6, str(ids))
	check("identity: 6 unique passive kinds (one per sub-role)",
		kinds.size() == 6 and uki.size() == 6, str(kinds))

	# ---- SPRINT (Blitz): constant +12% move speed, verified in physics ----
	var b := _hero(world, 0, "blitz", Vector3(0, 0.9, 0))
	var k := _hero(world, 1, "kestrel", Vector3(-10, 0.9, 0))
	# Drive movement through the shared Controls contract, exactly like a
	# human: the player path binds move_input from Controls each step.
	b.is_player = true
	k.is_player = true
	Controls.move = Vector2(1, 0)
	await frames(30)  # ground blend converges at 12/s: 30 frames = 99.8%
	Controls.move = Vector2.ZERO
	var b_exp: float = b.hero_data.base_speed * b.ability.passive_speed_mult()
	var k_exp: float = k.hero_data.base_speed * k.ability.passive_speed_mult()
	check("sprint: Blitz's passive mult is the declared 1.12",
		absf(b.ability.passive_speed_mult() - 1.12) < 0.001,
		"%.3f" % b.ability.passive_speed_mult())
	check("sprint: Blitz actually moves at base_speed x 1.12",
		absf(b.velocity.x - b_exp) < 0.06 * b_exp, "v=%.2f want %.2f" % [b.velocity.x, b_exp])
	check("sprint: a non-sprint hero moves at its own base (no cross-leak)",
		absf(k.velocity.x - k_exp) < 0.06 * k_exp, "v=%.2f want %.2f" % [k.velocity.x, k_exp])

	# ---- ARMOR (Bastion): 20% of incoming damage negated, pipeline level ----
	var bs := _hero(world, 0, "bastion", Vector3(0, 20, 0))
	var bs2 := _hero(world, 0, "bastion", Vector3(2, 20, 0))
	bs.hp = 100.0
	world.damage(bs, 20.0, k, false, bs.global_position)
	check("armor: 20 raw damage lands as 16 on Bastion", absf(bs.hp - 84.0) < 0.01,
		"hp=%.2f" % bs.hp)
	# (headshot_mult is applied in the weapon pipeline; direct world.damage
	#  passes a flat amount - mitigation must apply to any incoming damage)
	world.damage(bs, 20.0, k, true, bs.global_position)
	check("armor: mitigation applies to any incoming damage (2nd 20 -> 16)",
		absf(bs.hp - 68.0) < 0.01, "hp=%.2f" % bs.hp)
	var k2 := _hero(world, 1, "kestrel", Vector3(4, 20, 0))
	k2.hp = 100.0
	world.damage(k2, 20.0, bs2, false, k2.global_position)
	check("armor: a non-armor hero takes the full 20 (control)", absf(k2.hp - 80.0) < 0.01,
		"hp=%.2f" % k2.hp)

	# ---- FLEX (Patch): ability cooldowns x0.8, measured in the real loop ----
	var p := _hero(world, 0, "patch", Vector3(0, 40, 0))
	var p_cd: float = float(p.hero_data.abilities[0].cooldown)
	check("flex: Toolkit declares cd_mult 0.8", absf(p.ability.passive_cd_mult() - 0.8) < 0.001,
		"%.2f" % p.ability.passive_cd_mult())
	check("flex: cast succeeds while off cooldown", p.ability.cast(0))
	var elapsed := 0.0
	while not p.ability.can_cast(0) and elapsed < p_cd:
		world.step(FIXED_DT)
		elapsed += FIXED_DT
	check("flex: ability 0 re-readies in cooldown x 0.8 (%.2fs of %.2fs)" % [p_cd * 0.8, p_cd],
		absf(elapsed - p_cd * 0.8) < FIXED_DT + 0.001, "elapsed=%.3f" % elapsed)

	# ---- ZONE (Nimbus): fire-rate aura, only for live ENEMIES in radius ----
	var n := _hero(world, 0, "nimbus", Vector3(0, 60, 0))
	var ne := _hero(world, 1, "mira", Vector3(0, 60, 5))  # enemy, 5 m away
	await frames(2)
	check("zone: aura activates for an enemy in radius", n.ability._zone_active
		and absf(n.ability.passive_rate_mult() - 1.08) < 0.001,
		"rate=%.2f" % n.ability.passive_rate_mult())
	ne.position = Vector3(0, 60, 25)
	await frames(2)
	check("zone: aura drops when the enemy leaves the radius",
		not n.ability._zone_active and n.ability.passive_rate_mult() == 1.0,
		"rate=%.2f" % n.ability.passive_rate_mult())
	var na := _hero(world, 0, "kestrel", Vector3(0, 60, 5))  # ALLY in radius
	ne.position = Vector3(0, 60, 25)  # enemy back out of radius
	await frames(2)
	check("zone: an ally in radius does NOT trigger the aura", not n.ability._zone_active,
		"rate=%.2f" % n.ability.passive_rate_mult())

	# ---- FIELD (Mira): 5 HP/s tick-heal to in-radius allies (differenced) ----
	var mw := World.new()
	mw.name = "World"
	add_child(mw)
	var cw := World.new()  # control world: identical layout, no Mira
	cw.name = "World"
	add_child(cw)
	var m := _hero(mw, 0, "mira", Vector3(0, 0, 0))
	var ally := _hero(mw, 0, "patch", Vector3(3, 0, 0))
	var ally_c := _hero(cw, 0, "patch", Vector3(3, 0, 0))
	var far := _hero(mw, 0, "kestrel", Vector3(25, 0, 0))
	var enemy := _hero(mw, 1, "nimbus", Vector3(10, 0, 0))
	# zero the out-of-combat regen on the probes (a confound: it fills to
	# the 50% cap while the field is healing) and measure the field alone
	ally.regen_rate = 0.0
	ally_c.regen_rate = 0.0
	far.regen_rate = 0.0
	enemy.regen_rate = 0.0
	ally.hp = 50.0
	ally_c.hp = 50.0
	far.hp = 50.0
	enemy.hp = 50.0
	for i in 60:  # 1 s of sim in both worlds (regen cancels in the diff)
		mw.step(FIXED_DT)
		cw.step(FIXED_DT)
	var gained: float = ally.hp - ally_c.hp
	check("field: in-radius ally gains ~5 HP/s (diff vs control)"
		, absf(gained - 5.0) < 0.15, "+%.2f" % gained)
	check("field: the far ally gains nothing", absf(far.hp - 50.0) < 0.05,
		"hp=%.2f" % far.hp)
	check("field: the enemy is not healed by the field", absf(enemy.hp - 50.0) < 0.05,
		"hp=%.2f" % enemy.hp)

	# ---- HIT_STREAK (Kestrel): hit streak -> tiered speed/spread ----
	var kk := _hero(world, 0, "kestrel", Vector3(0, 80, 0))
	var tgt := _hero(world, 1, "blitz", Vector3(2, 80, 0))
	for i in 5:
		tgt.hp = 150.0
		world.damage(tgt, 10.0, kk, false, tgt.global_position)
		kk.ability.on_hit_landed()
	check("streak: 5 landed hits -> tier 1 (1.05 speed / 0.9 spread)",
		absf(kk.ability.passive_speed_mult() - 1.05) < 0.001
		and absf(kk.ability.passive_spread_mult() - 0.9) < 0.001,
		"%.2f/%.2f" % [kk.ability.passive_speed_mult(), kk.ability.passive_spread_mult()])
	for i in 135:  # 2.25 s > the 2.0 s window
		world.step(FIXED_DT)
	check("streak: the streak decays after the window", kk.ability.passive_speed_mult() == 1.0)

	# ---- stacking rules: passive x perk x ult are multiplicative ----
	b.perk_mults["speed"] = 1.08  # the perk table (D25) is a separate multiplier
	check("stack: passive x perk multiplies (1.12 x 1.08 = 1.2096)",
		absf(b.ability.speed_mult() - 1.12 * 1.08) < 0.001,
		"%.4f" % b.ability.speed_mult())
	b.perk_mults.erase("speed")
	# Blitz's Overclock ult: 1.5x speed for 6 s
	for i in 7:
		b.ability.on_kill()
	check("stack: charge fills from kills", b.ability.can_activate_ult(),
		"charge=%.0f" % b.ability.charge)
	check("stack: the ult activates and resets the charge",
		b.ability.activate_ult() and b.ability.charge == 0.0)
	var want: float = 1.12 * float(b.hero_data.ult.params.get("speed_mult", 1.5))
	check("stack: passive x ult multiplies while active (1.12 x 1.5 = 1.68)",
		b.ability.is_ult_active() and absf(b.ability.speed_mult() - want) < 0.001,
		"%.4f want %.4f" % [b.ability.speed_mult(), want])
	b.perk_mults["speed"] = 1.08
	check("stack: all three multiply together (1.12 x 1.5 x 1.08)",
		absf(b.ability.speed_mult() - want * 1.08) < 0.002,
		"%.4f want %.4f" % [b.ability.speed_mult(), want * 1.08])

	mw.free()
	cw.free()
	print("PASSIVES SUITE: %d passed, %d failed" % [ok, fail])
	get_tree().quit(fail)

func _physics_process(delta: float) -> void:
	if world != null and is_instance_valid(world):
		world.step(minf(delta, FIXED_DT))

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _hero(w: World, team: int, hid: String, pos: Vector3) -> Hero:
	var hd: HeroData = null
	for h in HeroRegistry.HEROES:
		if (h as HeroData).id == hid:
			hd = h
	var ch := HeroFactory.create(team, false, hd.color, hd)
	ch.position = pos
	ch.protected_until = -1.0
	w.add_child(ch)
	w.register_character(ch)
	return ch

func _on_floor(pos: Vector3) -> Vector3:
	return Vector3(pos.x, 0.9, pos.z)  # capsule origin above the arena floor
