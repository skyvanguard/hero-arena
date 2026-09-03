extends Node
## Headless hero-kit tests (Phase 2): data-driven kit load, dash, cooldowns,
## burst + slow, combat-driven ult charge, ult buff pipeline, hit-streak passive.
## Run: godot --headless --path game res://tests/test_hero.tscn
## Exit code = number of failed fails.

const FIXED_DT := 1.0 / 60.0
const KESTREL: HeroData = preload("res://content/heroes/kestrel.tres")

var world: World
var player: Hero
var target: Hero
var fails := 0
var _accum := 0.0
var ult_ready_hits := 0

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
	player = HeroFactory.create(0, true, KESTREL.color, KESTREL)
	player.position = Vector3(-5, 0.9, 0)
	add_child(player)
	world.register_character(player)
	target = HeroFactory.create(1, false, KESTREL.color, KESTREL)
	target.position = Vector3(-5, 0.9, 5)
	add_child(target)
	world.register_character(target)
	player.ability.ult_ready.connect(func() -> void: ult_ready_hits += 1)
	await frames(10)
	await _test_kit_data()
	await _test_dash()
	await _test_cooldowns()
	await _test_burst_slow()
	await _test_ult_charge()
	await _test_ult_activation()
	await _test_ult_damage_pipeline()
	await _test_passive_streak()
	print("RESULT: %d checks failed" % fails)
	get_tree().quit(fails)

func _physics_process(delta: float) -> void:
	_accum += delta
	var s := 0
	while _accum >= FIXED_DT and s < 4:
		world.step(FIXED_DT)
		_accum -= FIXED_DT
		s += 1

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func seconds(s: float, time_scale: float = 1.0) -> void:
	Engine.time_scale = time_scale
	var n := int(ceilf(s * 60.0))
	await frames(n)
	Engine.time_scale = 1.0

func _reset_positions() -> void:
	player.position = Vector3(-5, 0.9, 0)
	player.rotation.y = 0.0  # faces +Z (project FWD convention)
	target.position = Vector3(-5, 0.9, 3.5)
	target.rotation.y = 0.0
	target.hp = target.max_hp
	player.hp = player.max_hp
	# Test-only: clear cooldowns + passive streak between tests.
	player.ability._cooldown_until = [0.0, 0.0]
	player.ability._streak_hits = 0

func _test_kit_data() -> void:
	check("kit: kestrel.tres loads with id", KESTREL.id == "kestrel", KESTREL.id)
	check("kit: role is assault", KESTREL.role == HeroData.Role.ASSAULT)
	check("kit: two abilities + ult defined", KESTREL.abilities.size() == 2 and KESTREL.ult != null)
	check("kit: ult flagged is_ult", KESTREL.ult.is_ult)
	check("kit: passive defined", KESTREL.passive != null and KESTREL.passive.kind == PassiveData.Kind.HIT_STREAK)
	check("kit: weapon profile applied to built hero",
		player.weapon.fire_rate == 11.0 and player.weapon.clip_size == 35 and player.max_hp == 120.0,
		"rate=%.0f clip=%d hp=%.0f" % [player.weapon.fire_rate, player.weapon.clip_size, player.max_hp])
	check("kit: ability component attached", player.ability != null and target.ability != null)

func _test_dash() -> void:
	_reset_positions()
	var p0 := player.global_position
	check("dash: cast accepted", player.ability.cast(0))
	await seconds(0.5)
	var moved := player.global_position.distance_to(p0)
	check("dash: double dash moves forward", moved >= 2.5 and moved <= 9.0,
		"moved=%.2f" % moved)
	check("dash: movement is along facing (+Z)",
		player.global_position.z > p0.z + 2.0 and absf(player.global_position.x - p0.x) < 0.5,
		"d=(%.2f, %.2f)" % [player.global_position.x - p0.x, player.global_position.z - p0.z])

func _test_cooldowns() -> void:
	_reset_positions()
	check("cooldown: cast ok at t0", player.ability.cast(0))
	check("cooldown: cannot re-cast immediately", not player.ability.cast(0))
	await seconds(6.2, 10.0)
	check("cooldown: cast ready after cooldown (6s)", player.ability.can_cast(0))
	player.ability.cast(1)
	check("cooldown: ability 2 independent", player.ability.can_cast(0), "a0 should still be ready")

func _test_burst_slow() -> void:
	_reset_positions()
	var hp0 := target.hp
	check("burst: cast accepted", player.ability.cast(1))
	await frames(5)
	var dealt := hp0 - target.hp
	check("burst: inner pellets hit (>= 2 of 4 x 8 dmg)", dealt >= 15.0,
		"dealt=%.1f" % dealt)
	check("burst: slow applied to target", target.slow_ratio >= 0.24,
		"slow=%.2f" % target.slow_ratio)
	var slow_before := target.slow_ratio
	await seconds(3.2, 10.0)
	check("burst: slow expires after duration", target.slow_ratio == 0.0,
		"slow=%.2f" % target.slow_ratio)

func _test_ult_charge() -> void:
	_reset_positions()
	player.ability.charge = 0.0
	ult_ready_hits = 0
	player.ability.on_damage_dealt(200.0)
	check("ult: charge from damage dealt (200 x 0.35 = 70)",
		absf(player.ability.charge - 70.0) < 0.01, "charge=%.1f" % player.ability.charge)
	player.ability.on_damage_dealt(150.0)
	check("ult: charge caps at max (100)", player.ability.charge == 100.0,
		"charge=%.1f" % player.ability.charge)
	check("ult: ult_ready fired exactly once", ult_ready_hits == 1, "hits=%d" % ult_ready_hits)
	check("ult: canActivate at full", player.ability.can_activate_ult())
	player.ability.on_kill()
	check("ult: kill charge does not exceed cap", player.ability.charge == 100.0)
	player.ability.on_damage_taken(50.0)
	check("ult: taken charge also capped", player.ability.charge == 100.0)

func _test_ult_activation() -> void:
	_reset_positions()
	player.ability.charge = 0.0
	check("ult: cannot activate at 0 charge", not player.ability.activate_ult())
	player.ability.charge = KESTREL.ult_max
	check("ult: activate at full charge", player.ability.activate_ult())
	check("ult: charge consumed", player.ability.charge == 0.0)
	check("ult: fire rate x2 while active", player.ability.fire_rate_mult() == 2.0,
		"mult=%.1f" % player.ability.fire_rate_mult())
	check("ult: speed x1.4 while active", absf(player.ability.speed_mult() - 1.4) < 0.01)
	await seconds(5.2, 10.0)
	check("ult: buff expires after 5s", player.ability.fire_rate_mult() == 1.0 and not player.ability.is_ult_active())
	check("ult: not re-activatable after expiry (charge 0)", not player.ability.can_activate_ult())

func _test_ult_damage_pipeline() -> void:
	_reset_positions()
	player.ability.charge = KESTREL.ult_max
	player.ability.activate_ult()
	target.hp = target.max_hp
	var hp0 := target.hp
	Controls.fire = true
	await seconds(0.2)
	Controls.fire = false
	var dealt := hp0 - target.hp
	check("ult: weapon damage buffed in pipeline (>= 50 dmg in 0.2s)", dealt >= 50.0,
		"dealt=%.1f shots=%d dmg_mult=%.1f" % [dealt, player.weapon.shots_fired, player.ability.damage_mult()])
	# (Target may or may not survive: headshots from the muzzle line can crit.
	#  The pipeline check above is what matters.)

func _test_passive_streak() -> void:
	_reset_positions()
	await seconds(2.1, 10.0)  # ensure any prior streak has decayed
	for i in 5:
		player.ability.on_hit_landed()
	check("passive: 5 hits -> tier 1 speed/spread",
		absf(player.ability.passive_speed_mult() - 1.05) < 0.001 and absf(player.ability.passive_spread_mult() - 0.9) < 0.001,
		"speed=%.2f spread=%.2f" % [player.ability.passive_speed_mult(), player.ability.passive_spread_mult()])
	for i in 5:
		player.ability.on_hit_landed()
	check("passive: 10 hits -> tier 2", absf(player.ability.passive_speed_mult() - 1.1) < 0.001,
		"speed=%.2f" % player.ability.passive_speed_mult())
	await seconds(2.1, 10.0)  # window is 2.0s
	check("passive: streak decays after window", player.ability.passive_speed_mult() == 1.0)
