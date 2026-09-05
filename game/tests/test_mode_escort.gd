extends Node
## Escort mode suite (Phase 6, round 31, D17): 9 deterministic checks over
## the payload state machine (setup, idle, solo push, push-vs-brake,
## clamp, delivery win, defender timeout win, in-place reset) + a bot
## decision check.
const FIXED_DT := 1.0 / 60.0

var passes := 0
var fails := 0
var world: World
var mode: EscortMode
var chars: Array = []

func check(name: String, cond: bool, detail := "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		fails += 1
		print("FAIL ", name, ("  [" + detail + "]" if detail != "" else ""))

func frames(n: int):
	for i in n:
		await get_tree().physics_frame

func _new_world() -> World:
	if world != null:
		world.queue_free()
	for c in chars:
		c.queue_free()
	chars = []
	await frames(2)
	world = World.new()
	world.name = "World"
	world.target_score = 999
	world.match_duration = 300.0
	add_child(world)
	add_child(Arena.build(world))
	mode = EscortMode.new()
	world.mode = mode
	mode.setup(world)
	return world

func _char(team: int, pos: Vector3) -> Hero:
	var h := HeroFactory.create(team, false)
	h.position = pos
	add_child(h)
	world.register_character(h)
	chars.append(h)
	return h

func _step(seconds: float) -> void:
	var n := int(ceilf(seconds / FIXED_DT))
	for i in n:
		world.step(FIXED_DT)

func _ready() -> void:
	randomize()
	# 1) Registry (covered with capture in that suite; re-assert the type).
	check("registry: escort resolves to EscortMode",
			ModeRegistry.get_mode("escort") is EscortMode, "")
	# 2) Setup: lane endpoints from the CENTRAL spawn x's, payload at start.
	await _new_world()
	var start_x: float = world.spawn_points[0][1].x
	var goal_x: float = world.spawn_points[1][1].x
	check("escort: setup pins the lane from the spawns",
			world.payload_start_x == start_x and world.payload_goal_x == goal_x
			and world.payload_pos == start_x,
			"start=%.1f goal=%.1f pos=%.1f" % [world.payload_start_x, world.payload_goal_x, world.payload_pos])
	# 3) Idle: nobody near the payload -> no movement.
	var before := world.payload_pos
	_step(2.0)
	check("escort: payload is idle with no pushers",
			is_equal_approx(world.payload_pos, before) and world.payload_speed == 0.0,
			"pos=%.2f speed=%.2f" % [world.payload_pos, world.payload_speed])
	# 4) A single attacker in the push radius -> full speed, real progress.
	var pusher := _char(0, Vector3(world.payload_pos + 1.0, 0.9, 0.0))
	var b2 := world.payload_pos
	_step(2.0)
	var moved: float = world.payload_pos - b2
	var dir := signf(goal_x - start_x)
	check("escort: one attacker pushes at max speed",
			world.payload_speed == mode.max_speed
			and absf(moved - mode.max_speed * 2.0 * dir) < 0.2,
			"speed=%.2f moved=%.2f expect=%.2f" % [world.payload_speed, moved, mode.max_speed * 2.0 * dir])
	# 5) One attacker + one defender -> net zero power, the payload stops.
	var braker := _char(1, Vector3(world.payload_pos - 1.0, 0.9, 0.0))
	var b3 := world.payload_pos
	_step(1.0)
	check("escort: equal heads fully stop the payload",
			is_equal_approx(world.payload_pos, b3) and world.payload_speed == 0.0,
			"pos=%.2f speed=%.2f" % [world.payload_pos, world.payload_speed])
	# 6) Two attackers + one defender -> clamped to full speed again.
	var pusher2 := _char(0, Vector3(world.payload_pos + 0.5, 0.9, 1.0))
	var b4 := world.payload_pos
	_step(1.0)
	check("escort: 2v1 power clamps to full speed",
			world.payload_speed == mode.max_speed
			and absf((world.payload_pos - b4) * dir) > mode.max_speed * 0.9,
			"speed=%.2f" % world.payload_speed)
	# 7) Delivery: attackers keep pushing -> the payload reaches the goal
	#    and team 0 wins.
	var guard := 0.0
	while not world.match_over and guard < 40.0:
		pusher.position = Vector3(world.payload_pos + dir * 1.0, 0.9, 0.0)
		pusher2.position = Vector3(world.payload_pos + dir * 0.5, 0.9, 1.0)
		_step(0.5)
		guard += 0.5
	check("escort: payload delivery wins for the attackers",
			world.match_over and world.winner == 0,
			"over=%s w=%d pos=%.2f" % [world.match_over, world.winner, world.payload_pos])
	# 8) Timeout with no delivery -> the defenders win.
	await _new_world()
	world.time = 299.5
	_step(0.6)
	check("escort: timeout is a defender win",
			world.match_over and world.winner == 1, "w=%d" % world.winner)
	# 9) In-place reset (D14) restores the payload to the start.
	await _new_world()
	var p5 := _char(0, Vector3(world.payload_pos + 1.0, 0.9, 0.0))
	_step(3.0)
	check("escort: pre-reset the payload moved",
			absf((world.payload_pos - world.payload_start_x) * dir) > 1.0,
			"pos=%.2f" % world.payload_pos)
	world.reset()
	check("escort: reset parks the payload at the start",
			is_equal_approx(world.payload_pos, world.payload_start_x)
			and world.payload_speed == 0.0 and not world.match_over,
			"pos=%.2f" % world.payload_pos)
	# 10) Bot: an unengaged attacker's CAPTURE goal orbits the payload
	#     (ahead on the goal side), a defender's sits behind it.
	await _new_world()
	var att := _char(0, Vector3(world.payload_pos + 8.0, 0.9, 0.0))
	var perc := BotPerception.new()
	add_child(perc)
	perc.setup(att, world, BotDifficulties.by_id("normal"))
	var dec := BotDecision.new()
	add_child(dec)
	dec.setup(BotDifficulties.by_id("normal"), 0)
	dec.decide(world, perc, att)
	var gx: float = dec.goal.x - world.payload_pos
	check("bot: attacker CAPTURE goal is on the payload, goal side",
			dec.intent == BotDecision.Intent.CAPTURE and gx * dir > 0.5 and absf(gx) < 4.0,
			"intent=%d dx=%.2f" % [dec.intent, gx])
	_done()

func _done() -> void:
	print("MODE-ESCORT SUITE: %d passed, %d failed" % [passes, fails])
	get_tree().quit(fails)
