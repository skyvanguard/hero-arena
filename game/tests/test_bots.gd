extends Node
## Bot eval harness (Phase 4, CI): navigation, perception (vision cone /
## LOS / hearing), decision intents, difficulty ordering, and a bot-vs-bot
## 3v3 match (the "zero humans" guarantee) with a K/D difficulty band.
## The sim runs at SIM_SPEED x wall clock (main.gd's fixed loop already
## multi-steps per frame on real devices, so this mirrors production).

const FIXED_DT := 1.0 / 60.0
const SIM_SPEED := 4   # 4 sim ticks per physics frame

var world: World
var fails := 0

func check(name: String, ok: bool, detail: String = "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("  | " + detail if detail != "" and not ok else ""))
	if not ok:
		fails += 1

func _ready() -> void:
	world = World.new()  # (global RNG is unseeded in 4.7; eval margins account for variance)
	world.name = "World"
	add_child(world)
	await frames(2)
	await _test_data_ordering()
	await _test_vision()
	await _test_hearing()
	await _test_decision()
	await _test_navigation()
	await _test_match()
	print("RESULT: %d checks failed" % fails)
	get_tree().quit(1 if fails > 0 else 0)

func _physics_process(delta: float) -> void:
	# SIM_SPEED sim ticks per physics frame (main.gd's fixed loop already
	# multi-steps per OS frame on devices; this mirrors production faster).
	for i in SIM_SPEED:
		world.step(FIXED_DT)

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## Tiny per-tick firer: drives a dummy's want_fire/aim (server resets
## controller-less entities, so a real controller node is required).
class Firer extends Node:
	var ch: CharacterEntity = null
	var aim_at := Vector3.ZERO

	func setup(ch_: CharacterEntity, aim_at_: Vector3) -> void:
		ch = ch_
		aim_at = aim_at_
		ch.controller = self

	func step(world_: World, dt: float) -> void:
		if ch != null and ch.alive:
			ch.aim_target = aim_at
			ch.want_fire = true

## --- helpers -------------------------------------------------------------
func _clear_scene() -> void:
	for ch in world.characters.duplicate():
		world.unregister_character(ch)
		ch.queue_free()

func _make_bot(team: int, pos: Vector3, diff: String, hd: HeroData = null) -> Hero:
	if hd == null:
		hd = HeroRegistry.default_hero()
	var b := HeroFactory.create(team, false, hd.color, hd)
	b.position = pos
	add_child(b)
	world.register_character(b)
	var bc := BotController.new()
	b.add_child(bc)
	bc.setup(b, null, world, diff)
	return b

func _dummy(team: int, pos: Vector3) -> Hero:
	var d := HeroFactory.create(team, false, Color.GRAY, null)
	d.position = pos
	add_child(d)
	world.register_character(d)
	return d

func _ctl(b: Hero) -> BotController:
	for c in b.get_children():
		if c is BotController:
			return c
	return null

func _crat(root_pos: Vector3) -> Node3D:
	var s := StaticBody3D.new()
	s.position = root_pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 4.0, 0.5)
	col.shape = shape
	s.add_child(col)
	s.collision_layer = CharacterEntity.LAYER_WORLD
	s.collision_mask = 0
	add_child(s)
	return s

## --- tests ---------------------------------------------------------------
func _test_data_ordering() -> void:
	var ids: Array = BotDifficulties.ids()
	check("data: 4 difficulty tiers", ids.size() == 4, str(ids))
	var order := ["beginner", "normal", "advanced", "expert"]
	var prev: BotDifficulty = null
	var mono := true
	var detail := ""
	for id in order:
		var p: BotDifficulty = BotDifficulties.by_id(String(id))
		if prev != null:
			if p.vision_range <= prev.vision_range or p.reaction >= prev.reaction or p.aim_error_deg >= prev.aim_error_deg:
				mono = false
				detail += String(id) + " "
		prev = p
	check("data: tiers strictly ordered (vision up, reaction/aim error down)", mono, detail)

func _test_vision() -> void:
	_clear_scene()
	var bot := _make_bot(0, Vector3(0, 0.9, -8), "normal")
	bot.rotation.y = 0.0  # face +Z
	var in_cone := _dummy(1, Vector3(0, 0.9, 0))      # 8 m straight ahead
	var behind_wall := _dummy(1, Vector3(0, 0.9, 12)) # crate at z=4 blocks the ray
	var out_of_fov := _dummy(1, Vector3(18, 0.9, -2)) # ~72 deg off axis: outside 90 deg fov
	_crat(Vector3(0, 1.5, 4))
	await frames(3)
	var ctl: BotController = _ctl(bot)
	var perc: BotPerception = ctl.perception
	check("vision: enemy in cone + LOS seen", perc.known.has(in_cone), "")
	check("vision: enemy outside FOV not seen", not perc.known.has(out_of_fov), "")
	check("vision: enemy behind wall not seen", not perc.known.has(behind_wall), "")

func _test_hearing() -> void:
	_clear_scene()
	var bot := _make_bot(0, Vector3(0, 0.9, -10), "normal")  # hearing 18 m
	bot.rotation.y = 0.0
	var shooter := _dummy(1, Vector3(0, 0.9, 8))
	shooter.rotation.y = deg_to_rad(180.0)  # face the bot
	var firer := Firer.new()
	shooter.add_child(firer)
	firer.setup(shooter, bot.head_pos())
	_crat(Vector3(0, 1.5, -1))  # blocks vision from bot to shooter
	await frames(20)  # let the shooter fire a few rounds (0.5 sim s)
	firer.queue_free()  # stop firing (controller-less -> want_fire resets)
	await frames(2)
	var ctl: BotController = _ctl(bot)
	var perc: BotPerception = ctl.perception
	check("hearing: enemy shot within range heard", perc.heard_until > world.time - 3.0,
		"heard_until=%.1f time=%.1f" % [perc.heard_until, world.time])
	var d: float = perc.heard_pos.distance_to(shooter.global_position)
	check("hearing: heard position near shooter", d < 2.0, "d=%.1f" % d)

func _test_decision() -> void:
	_clear_scene()
	var bot := _make_bot(0, Vector3(0, 0.9, 0), "normal")
	var enemy := _dummy(1, Vector3(2, 0.9, 6))  # ~18 deg off axis: inside cone
	bot.rotation.y = 0.0
	await frames(3)
	var dec: BotDecision = _ctl(bot).decision
	check("decision: fresh enemy -> ATTACK", dec.intent == BotDecision.Intent.ATTACK, "intent=%d" % dec.intent)
	# Wounded bot with enemy on it -> RETREAT. Seed the low-HP timer: the
	# decision only commits after retreat_confirm (0.5 s) below the line,
	# which is the point (a single wounded tick must not make bots
	# unkillable). 1.0 s well past the window.
	bot.hp = bot.max_hp * 0.1
	dec._low_hp_since = world.time - 1.0
	await frames(3)
	check("decision: wounded + enemy -> RETREAT", dec.intent == BotDecision.Intent.RETREAT, "intent=%d" % dec.intent)
	# Clear, then a wounded ally -> REGROUP.
	_clear_scene()
	var bot2 := _make_bot(0, Vector3(0, 0.9, 0), "normal")
	var ally := _dummy(0, Vector3(24, 0.9, 0))
	ally.hp = ally.max_hp * 0.2
	await frames(3)
	var dec2: BotDecision = _ctl(bot2).decision
	check("decision: wounded ally -> REGROUP", dec2.intent == BotDecision.Intent.REGROUP, "intent=%d" % dec2.intent)

func _test_navigation() -> void:
	# Navigation success: a bot on REGROUP actually moves toward the ally.
	_clear_scene()
	var bot := _make_bot(0, Vector3(0, 0.9, 0), "normal")
	var ally := _dummy(0, Vector3(30, 0.9, 0))
	ally.hp = ally.max_hp * 0.2
	await frames(3)
	var start: float = bot.global_position.distance_to(ally.global_position)
	await frames(180)  # 3 sim seconds
	var end: float = bot.global_position.distance_to(ally.global_position)
	check("navigation: bot closes distance to regroup point", end < start - 4.0,
		"start=%.1f end=%.1f" % [start, end])

func _test_match() -> void:
	# 3v3 bot-vs-bot (zero humans): a normal match produces kills, and an
	# expert squad out-K/Ds a beginner squad (difficulty band).
	var t0: float = world.time
	_spawn_match(0, ["normal", "normal", "normal"], 1, ["normal", "normal", "normal"])
	await frames(9000 / SIM_SPEED)  # 150 sim seconds at SIM_SPEED
	var s0: int = world.score[0]
	var s1: int = world.score[1]
	check("match: 3v3 normal bots fight (kills happen)", s0 + s1 >= 3, "score %d-%d" % [s0, s1])
	world.score = {0: 0, 1: 0}
	_clear_scene()
	_spawn_match(0, ["expert", "expert", "expert"], 1, ["beginner", "beginner", "beginner"])
	await frames(9000 / SIM_SPEED)
	var e: int = world.score[0]
	var b: int = world.score[1]
	check("match: expert squad out-K/Ds beginner squad", e > b, "expert=%d beginner=%d" % [e, b])

func _spawn_match(team_a: int, diffs_a: Array, team_b: int, diffs_b: Array) -> void:
	var arena := Arena.build(world)
	add_child(arena)
	var pa: Array = world.spawn_points.get(team_a, [])
	var pb: Array = world.spawn_points.get(team_b, [])
	var roster: Array = HeroRegistry.HEROES.duplicate()
	for i in diffs_a.size():
		var d: String = diffs_a[i]
		var hd: HeroData = roster[i % roster.size()]
		var bch := HeroFactory.create(team_a, false, hd.color, hd)
		bch.position = pa[i % pa.size()]
		bch.rotation.y = PI * 0.5  # face the enemy side (+X)
		add_child(bch)
		world.register_character(bch)
		var bc := BotController.new()
		bch.add_child(bc)
		bc.setup(bch, null, world, d)
	for i in diffs_b.size():
		var d2: String = diffs_b[i]
		var hd2: HeroData = roster[(i + 3) % roster.size()]
		var bch2 := HeroFactory.create(team_b, false, hd2.color, hd2)
		bch2.position = pb[i % pb.size()]
		bch2.rotation.y = -PI * 0.5  # face the enemy side (-X)
		add_child(bch2)
		world.register_character(bch2)
		var bc2 := BotController.new()
		bch2.add_child(bc2)
		bc2.setup(bch2, null, world, d2)
