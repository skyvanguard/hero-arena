extends Node
## Headless projectile weapon tests (Phase 3 weapon framework).
## Run: godot --headless --path game res://tests/test_projectile.tscn

const FIXED_DT := 1.0 / 60.0

var world: World
var player: Hero
var target: Hero
var ally: Hero
var fails := 0

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
	player = HeroFactory.create(0, true)
	player.position = Vector3(-5, 0.9, 0)
	player.rotation.y = 0.0
	add_child(player)
	world.register_character(player)
	player.weapon.mode = "projectile"
	player.weapon.damage = 9.0
	player.weapon.headshot_mult = 1.5
	player.weapon.fire_rate = 5.0
	player.weapon.projectile_speed = 22.0
	player.weapon.projectile_range = 40.0
	player.weapon.spread_deg = 0.0
	player.weapon.ready()
	target = HeroFactory.create(1, false)
	target.position = Vector3(-5, 0.9, 8)
	add_child(target)
	world.register_character(target)
	ally = HeroFactory.create(0, false)
	ally.position = Vector3(-5, 0.9, 4)
	add_child(ally)
	world.register_character(ally)
	await frames(10)
	await _test_spawn_and_travel()
	await _test_range_exhaustion()
	await _test_friendly_passthrough()
	await _test_slow_on_hit()
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

func _fire_once() -> void:
	# Aim like the player camera: 10 deg down (hero.gd _cam_pitch -0.18) —
	# a perfectly horizontal ray from the muzzle threads the body/head gap.
	var dir := Vector3(0, -0.18, 1.0).normalized()
	player.want_fire = true
	player.weapon.update(world, FIXED_DT, true, dir)
	player.want_fire = false

func _test_spawn_and_travel() -> void:
	var hp0 := target.hp
	_fire_once()
	check("proj: registered in world", world.projectiles.size() == 1)
	await frames(3)  # ~0.05s: still in flight at 8m @ 22 m/s (~0.36s)
	check("proj: in flight early", world.projectiles.size() == 1 and target.hp == hp0)
	await frames(25)  # total ~0.5s: should have hit by now
	check("proj: hit target for damage", target.hp < hp0, "hp0=%.0f hp=%.0f" % [hp0, target.hp])
	check("proj: removed after hit", world.projectiles.size() == 0)

func _test_range_exhaustion() -> void:
	target.hp = target.max_hp
	ally.hp = ally.max_hp
	target.position = Vector3(-5, 0.9, 45)  # beyond projectile_range 40
	_ally_reset()
	var p0 := player.position
	_fire_once()
	check("proj: spawned for far target", world.projectiles.size() == 1)
	await frames(120)  # 2s: max travel 88m > 40m range
	check("proj: exhausted at range", world.projectiles.size() == 0)
	check("proj: far target unharmed", target.hp == target.max_hp)
	target.position = p0 + Vector3(0, 0, 8)

func _ally_reset() -> void:
	ally.position = Vector3(-5, 0.9, 4)

func _test_friendly_passthrough() -> void:
	ally.hp = ally.max_hp
	_ally_reset()
	var hp0 := ally.hp
	_fire_once()  # flies through ally (same team) toward target
	await frames(40)
	check("proj: ally unharmed (team filter)", ally.hp == hp0, "hp0=%.0f hp=%.0f" % [hp0, ally.hp])

func _test_slow_on_hit() -> void:
	target.hp = target.max_hp
	target.position = Vector3(-5, 0.9, 8)
	player.weapon.projectile_slow_ratio = 0.3
	player.weapon.projectile_slow_duration = 2.0
	_fire_once()
	await frames(25)
	check("proj: slow applied on hit", target.slow_ratio >= 0.29, "slow=%.2f" % target.slow_ratio)
	await frames(140)  # >2s at 1x: slow expires
	check("proj: slow expires", target.slow_ratio == 0.0)
