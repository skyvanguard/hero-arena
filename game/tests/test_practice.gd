extends Node
## Headless practice-range test (Phase 3): dummies take authoritative
## damage, the manager tracks session stats, and damaged dummies reset
## after the grace window. Run:
##   godot --headless --path game res://tests/test_practice.tscn

const FIXED_DT := 1.0 / 60.0

var world: World
var player: Hero
var manager: PracticeManager
var dummies: Array = []
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
	add_child(PracticeRange.build(world))
	var hd: HeroData = HeroRegistry.by_id("kestrel")
	# Non-player rig: aim_target-driven (no camera input in the test sim).
	player = HeroFactory.create(0, false, hd.color, hd)
	player.position = PracticeRange.PLAYER_SPAWN
	add_child(player)
	world.register_character(player)
	manager = PracticeManager.new()
	manager.name = "PracticeManager"
	add_child(manager)
	manager.setup(world)
	var positions := PracticeRange.dummy_positions()
	check("practice: 3 dummy stations", positions.size() == 3, "n=%d" % positions.size())
	for i in 3:
		var d := HeroFactory.create(1, false, Color.WHITE, null)
		d.position = positions[i]
		add_child(d)
		world.register_character(d)
		manager.add_dummy(d)
		dummies.append(d)
	await frames(5)
	# Distances from the shooter: 14 / 22 / 30 m.
	var dz := [0.0, 0.0, 0.0]
	for i in 3:
		var dist: float = dummies[i].global_position.distance_to(player.global_position)
		dz[i] = dist
	check("practice: dummy 14 m", absf(dz[0] - 14.0) < 0.2, "d=%.1f" % dz[0])
	check("practice: dummy 22 m", absf(dz[1] - 22.0) < 0.2, "d=%.1f" % dz[1])
	check("practice: dummy 30 m", absf(dz[2] - 30.0) < 0.2, "d=%.1f" % dz[2])
	# Fire at the first dummy for 1.0 s.
	var tc := _TestController.new()
	add_child(tc)
	tc.hero = player
	tc.target = dummies[0]
	player.controller = tc
	await frames(60)
	player.controller = null
	player.want_fire = false
	check("practice: damage landed on target dummy", dummies[0].hp < dummies[0].max_hp, "hp=%.0f" % dummies[0].hp)
	check("practice: manager tracked dummy damage", manager.total_damage_to_dummy(dummies[0]) > 0.0,
		"dmg=%.0f" % manager.total_damage_to_dummy(dummies[0]))
	check("practice: other dummies untouched", dummies[1].hp == dummies[1].max_hp and dummies[2].hp == dummies[2].max_hp)
	# Grace window: no more hits; the damaged dummy should reset to full HP.
	await frames(int(PracticeManager.RESET_GRACE * 60.0) + 30)
	check("practice: damaged dummy resets after grace", dummies[0].hp == dummies[0].max_hp, "hp=%.0f" % dummies[0].hp)
	check("practice: session timer advanced", manager.elapsed > 1.5, "t=%.1f" % manager.elapsed)
	check("practice: session damage counted", manager.session_damage() > 0.0, "dmg=%.0f" % manager.session_damage())
	# Player-rig path: camera aim + the range pitch must hit the 14 m dummy
	# (exactly what a human does — Controls.fire, camera forward). The first
	# test hero stands at the same spawn, so free it first (its body would
	# intercept the rays at this point).
	world.unregister_character(player)
	player.queue_free()
	await frames(2)
	var p2 := HeroFactory.create(0, true, hd.color, hd)
	p2.position = PracticeRange.PLAYER_SPAWN
	p2.rotation.y = 0.0
	p2.set_aim_pitch(PracticeRange.initial_aim_pitch())
	add_child(p2)
	world.register_character(p2)
	Controls.fire = true
	await frames(60)
	Controls.fire = false
	var dealt2: float = dummies[0].max_hp - dummies[0].hp
	check("practice: player camera-aim path deals damage", dealt2 > 0.0, "dmg=%.0f" % dealt2)
	world.unregister_character(p2)
	p2.queue_free()
	print("RESULT: %d checks failed" % fails)
	get_tree().quit(fails)

func _physics_process(delta: float) -> void:
	var s := 0
	while delta >= FIXED_DT and s < 4:
		world.step(FIXED_DT)
		manager.tick(FIXED_DT)
		delta -= FIXED_DT
		s += 1

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

class _TestController:
	extends Node
	var hero: CharacterEntity
	var target: CharacterEntity

	func step(world: World, dt: float) -> void:
		hero.aim_target = target.global_position + Vector3(0, 0.4, 0)
		hero.want_fire = true
