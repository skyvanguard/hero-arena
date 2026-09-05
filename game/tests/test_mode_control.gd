extends Node
## Mode framework + Control mode suite (Phase 6, round 30, D16): 11
## deterministic checks (registry, TDM-as-mode, the full control state
## machine, win/timeout rules, in-place reset, bot CAPTURE decision) +
## one 30 s bot-integration check (6 bots in a control match start
## capturing).
const FIXED_DT := 1.0 / 60.0

var passes := 0
var fails := 0
var world: World
var mode: ControlMode
var chars: Array = []
var last_capture: Dictionary = {}
var last_over: Dictionary = {}
var bots_world: World
var bots_server: MatchServer

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

func _new_world(capture_seconds: float = 5.0) -> World:
	if world != null:
		world.queue_free()
	for c in chars:
		c.queue_free()
	chars = []
	# Let freed bodies leave the physics space BEFORE the next world spawns:
	# Godot 4.7 resolves exact capsule overlaps vertically at ~66 m/s, and a
	# queued-free body still in the space would launch a coincident newcomer
	# out of the capture circle (round-30 check-10 diagnosis).
	await frames(2)
	world = World.new()
	world.name = "World"
	world.target_score = 15
	world.match_duration = 300.0
	add_child(world)
	add_child(Arena.build(world))
	mode = ControlMode.new()
	mode.capture_seconds = capture_seconds
	world.mode = mode
	world.control_active = true
	world.control_point = Vector3.ZERO
	world.world_event.connect(_on_event)
	return world

func _on_event(name: String, data: Dictionary) -> void:
	if name == "control_capture":
		last_capture = data
	elif name == "match_over":
		last_over = data

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
	# 1) Registry.
	var tdm := ModeRegistry.get_mode("tdm")
	var ctl := ModeRegistry.get_mode("control")
	var unk := ModeRegistry.get_mode("nope")
	check("framework: registry returns TDM/Control, unknown -> TDM",
			tdm is TDMMode and ctl is ControlMode and unk is TDMMode,
			"ids=%s" % str(ModeRegistry.ids()))
	# 2) TDM as a Mode (win through the framework, not the legacy path).
	var w2 := World.new()
	add_child(w2)
	w2.target_score = 15
	w2.mode = TDMMode.new()
	w2.score = {0: 15, 1: 3}
	w2.mode.check_over(w2)
	check("framework: TDMMode wins at target_score",
			w2.match_over and w2.winner == 0, "over=%s w=%d" % [w2.match_over, w2.winner])
	w2.queue_free()
	# 3) Neutral point: team 0 alone in the circle -> progress starts.
	await _new_world(5.0)
	last_capture = {}
	_char(0, Vector3(1.0, 0.9, 0.0))
	_char(1, Vector3(14.0, 0.9, 0.0))
	_step(2.0)
	check("control: solo occupant starts capture",
			world.control_progress > 0.3 and world.control_progress < 0.5
			and world.control_progress_team == 0 and world.control_owner == -1,
			"p=%.2f team=%d owner=%d" % [world.control_progress, world.control_progress_team, world.control_owner])
	# 4) Both teams inside -> contested (progress freezes).
	var before := world.control_progress
	_char(1, Vector3(-1.0, 0.9, 0.0))
	_step(2.0)
	check("control: contested point freezes progress",
			is_equal_approx(world.control_progress, before),
			"before=%.3f after=%.3f" % [before, world.control_progress])
	# 5) Enemy leaves -> progress completes to a capture.
	chars[2].position = Vector3(14.0, 0.9, 8.0)  # the 2nd team-1 bot
	last_capture = {}
	_step(4.0)
	check("control: capture scores + owns the point",
			world.control_owner == 0 and int(world.control_score[0]) == 1
			and is_equal_approx(world.control_progress, 1.0)
			and int(last_capture.get("team", -1)) == 0,
			"owner=%d score=%s p=%.2f ev=%s" % [world.control_owner, str(world.control_score), world.control_progress, str(last_capture)])
	# 6) Holding: the capturer leaves, the point stays with team 0.
	chars[0].position = Vector3(-14.0, 0.9, 0.0)
	_step(2.0)
	check("control: captured point is held without occupancy",
			world.control_owner == 0 and int(world.control_score[0]) == 1,
			"owner=%d" % world.control_owner)
	# 7) Enemy re-occupation restarts progress toward team 1.
	chars[2].position = Vector3(1.5, 0.9, 0.0)  # bring a team-1 bot back in
	_step(1.5)
	check("control: re-capture progress runs toward the enemy",
			world.control_progress_team == 1 and world.control_progress > 0.2
			and world.control_owner == 0,
			"team=%d p=%.2f owner=%d" % [world.control_progress_team, world.control_progress, world.control_owner])
	# 8a) The re-capture lands 1-1: no target reached, the match continues.
	_step(5.0)
	check("control: re-capture to 1-1 does not end the match",
			not world.match_over and world.control_owner == 1
			and int(world.control_score[0]) == 1 and int(world.control_score[1]) == 1,
			"over=%s owner=%d score=%s" % [world.match_over, world.control_owner, str(world.control_score)])
	# 8b) The NEXT capture (a team's 2nd) ends the match for that team: the
	# t1 capturer leaves the point, the t0 bot steps in and re-captures.
	chars[2].position = Vector3(14.0, 0.9, 8.0)
	chars[0].position = Vector3(1.0, 0.9, 0.0)
	last_over = {}
	_step(5.5)
	check("control: 2nd team capture wins the match",
			world.match_over and world.winner == 0
			and int(last_over.get("score", [0, 0])[0]) == 2,
			"over=%s w=%d score=%s" % [world.match_over, world.winner, str(last_over.get("score"))])
	# 9) Timeout tiebreaks.
	await _new_world(5.0)
	world.control_score = {0: 1, 1: 1}
	world.control_owner = 0
	world.time = 299.5
	_step(1.0)
	check("control: tied timeout goes to the holding team",
			world.match_over and world.winner == 0, "w=%d" % world.winner)
	await _new_world(5.0)
	world.time = 299.5
	_step(1.0)
	check("control: 0-0 timeout with no holder is a draw",
			world.match_over and world.winner == -1, "w=%d" % world.winner)
	# 10) In-place reset (D14) clears control state.
	await _new_world(5.0)
	_char(0, Vector3(1.0, 0.9, 0.0))
	_step(2.0)
	_step(3.5)
	check("control: pre-reset capture happened", int(world.control_score[0]) == 1,
			"score=%s" % str(world.control_score))
	world.reset()
	check("control: reset clears owner/progress/score",
			world.control_owner == -1 and is_equal_approx(world.control_progress, 0.0)
			and world.control_progress_team == -1
			and int(world.control_score[0]) == 0 and int(world.control_score[1]) == 0
			and not world.match_over,
			"o=%d p=%.2f t=%d s=%s" % [world.control_owner, world.control_progress, world.control_progress_team, str(world.control_score)])
	# 11) Bot decision: unengaged bot in a neutral control -> CAPTURE inside
	# the circle.
	await _new_world(15.0)
	var bot := _char(0, Vector3(-6.0, 0.9, 0.0))
	var perc := BotPerception.new()
	add_child(perc)
	perc.setup(bot, world, BotDifficulties.by_id("normal"))
	var dec := BotDecision.new()
	add_child(dec)
	dec.setup(BotDifficulties.by_id("normal"), 0)
	dec.decide(world, perc, bot)
	var dg: Vector3 = dec.goal - world.control_point
	dg.y = 0.0
	check("bot: unengaged bot takes a neutral point (CAPTURE inside circle)",
			dec.intent == BotDecision.Intent.CAPTURE and dg.length() <= mode.capture_radius + 0.01,
			"intent=%d goal_dist=%.2f" % [dec.intent, dg.length()])
	# 12) Bot integration: 6 bots in a control match start capturing within
	# 30 s (stochastic by design - combat keeps interrupting the point).
	await _bots_setup()
	var t0 := Time.get_ticks_msec()
	var start := 0
	while Time.get_ticks_msec() - t0 < 30000 and fails < 99:
		start += 1
		await get_tree().physics_frame
		if bots_world.control_progress > 0.0 or bots_world.control_owner != -1:
			break
	check("bots: control match starts capturing within 30 s",
			bots_world.control_progress > 0.0 or bots_world.control_owner != -1,
			"p=%.2f owner=%d t=%.1f" % [bots_world.control_progress, bots_world.control_owner, (Time.get_ticks_msec() - t0) / 1000.0])
	_done()

func _bots_setup() -> void:
	if world != null:
		world.queue_free()
	for c in chars:
		c.queue_free()
	chars = []
	await frames(2)  # same physics-settle rule as _new_world
	bots_world = World.new()
	bots_world.name = "BotsWorld"
	bots_world.target_score = 999
	bots_world.match_duration = 300.0
	add_child(bots_world)
	add_child(Arena.build(bots_world))
	var cm := ControlMode.new()
	bots_world.mode = cm
	bots_world.control_active = true
	bots_world.control_point = Vector3.ZERO
	bots_server = MatchServer.new()
	add_child(bots_server)
	bots_server.setup(bots_world, 7788, 3)
	var roster: Array = HeroRegistry.HEROES.duplicate()
	roster.shuffle()
	var rix := 0
	for team in 2:
		var pts: Array = bots_world.spawn_points.get(team, [])
		for i in 3:
			if pts.size() <= i:
				break
			bots_server.spawn_bot(team, roster[rix % roster.size()], pts[i])
			rix += 1

func _physics_process(_delta: float) -> void:
	if is_instance_valid(world):
		world.step(FIXED_DT)
	if is_instance_valid(bots_world):
		bots_world.step(FIXED_DT)
		if is_instance_valid(bots_server):
			bots_server.tick(FIXED_DT)

func _done() -> void:
	print("MODE-CONTROL SUITE: %d passed, %d failed" % [passes, fails])
	get_tree().quit(fails)
