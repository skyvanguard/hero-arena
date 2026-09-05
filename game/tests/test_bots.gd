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
## Test geometry (crates, floor): _clear_scene frees these too, so a
## leftover cover piece from one test cannot block the next test's LOS.
var _helpers: Array = []

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
	await _test_team_flank()
	await _test_team_stick()
	await _test_match_end()
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
	for h in _helpers:
		if is_instance_valid(h):
			h.queue_free()
	_helpers = []

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

## Bare ground plane (tests that stand bots for >~0.2 s: without a floor
## they fall through y=0 and the vision geometry goes stale).
func _floor() -> StaticBody3D:
	var f := StaticBody3D.new()
	f.position = Vector3(0, -0.05, 0)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(80, 0.1, 80)
	col.shape = shape
	f.add_child(col)
	f.collision_layer = CharacterEntity.LAYER_WORLD
	f.collision_mask = 0
	add_child(f)
	_helpers.append(f)
	return f

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
	_helpers.append(s)
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

func _test_team_flank() -> void:
	# Team-mates sharing a target spread laterally (no stacking on one line
	# of fire): their ATTACK goals offset by flank_spacing, and their
	# positions stay spread during the engagement. Target HP is high so the
	# squad keeps the same target for the whole window.
	_clear_scene()
	_floor()
	var dummy := _dummy(1, Vector3(0, 0.9, 8))
	dummy.rotation.y = PI  # face the bots
	dummy.max_hp = 5000.0
	dummy.hp = 5000.0
	var b1 := _make_bot(0, Vector3(0, 0.9, -6), "advanced")
	var b2 := _make_bot(0, Vector3(2, 0.9, -5), "advanced")
	var b3 := _make_bot(0, Vector3(-2, 0.9, -5), "advanced")
	for b in [b1, b2, b3]:
		b.rotation.y = 0.0
		b.max_hp = 5000.0
		b.hp = 5000.0
	await frames(30)  # 2 sim s: all three lock on (reaction 0.25 s)
	var ctls: Array = [_ctl(b1), _ctl(b2), _ctl(b3)]
	var all_attack := true
	for c in ctls:
		if c.decision.intent != BotDecision.Intent.ATTACK or c.decision.target != dummy:
			all_attack = false
	check("team: all 3 bots lock on to the shared target", all_attack, "")
	var g1: Vector3 = ctls[0].decision.goal
	var g2: Vector3 = ctls[1].decision.goal
	var g3: Vector3 = ctls[2].decision.goal
	var max_goal_pair := maxf(g1.distance_to(g2), maxf(g1.distance_to(g3), g2.distance_to(g3)))
	check("team: flank offsets spread the ATTACK goals", max_goal_pair > 4.0,
		"max_goal_pair=%.1f" % max_goal_pair)
	await frames(300)  # 20 sim s of engagement
	var p1: Vector3 = b1.global_position
	var p2: Vector3 = b2.global_position
	var p3: Vector3 = b3.global_position
	var max_pair := maxf(p1.distance_to(p2), maxf(p1.distance_to(p3), p2.distance_to(p3)))
	check("team: positions stay spread during engagement", max_pair >= 2.0, "max_pair=%.1f" % max_pair)
func _test_team_stick() -> void:
	# An idle bot out of formation drifts back to an in-combat ally.
	# The ally is a BOT attacking a static dummy (deterministic in-combat).
	# Geometry: while the stray walks toward the ally, the target stays
	# outside its 45 deg half-FOV and its 5.2 s scan sweep, and beyond its
	# 18 m hearing range.
	_clear_scene()
	_floor()
	var target := _dummy(1, Vector3(8, 0.9, 28))  # static, no firer
	target.max_hp = 5000.0
	target.hp = 5000.0
	var ally := _make_bot(0, Vector3(0, 0.9, 0), "normal")  # sees target: ATTACK
	ally.rotation.y = 0.0
	ally.max_hp = 5000.0
	ally.hp = 5000.0
	var stray := _make_bot(0, Vector3(35, 0.9, 15), "normal")
	stray.rotation.y = 0.0
	stray.max_hp = 5000.0
	stray.hp = 5000.0
	await frames(30)  # 2 sim s
	var ctl: BotController = _ctl(stray)
	check("team: out-of-formation bot REGROUPs to in-combat ally",
		ctl.decision.intent == BotDecision.Intent.REGROUP, "intent=%d" % ctl.decision.intent)
	check("team: stick goal is the in-combat ally",
		ctl.decision.goal.distance_to(ally.global_position) < 1.0,
		"goal=%s ally=%s" % [str(ctl.decision.goal), str(ally.global_position)])
	# Measure the STRAY's walk toward the squad while it is still in REGROUP.
	# Two confounds made the old "closes live distance" check flaky (~40% of
	# runs): (1) the ally is in combat and drifts toward the dummy while the
	# stray approaches, so the closing distance is confounded by the ally's
	# own movement; (2) the stray's scan sweep is stochastic and can find the
	# target earlier than the assumed ~5.2 s, flipping the intent to ATTACK
	# mid-window (observed: the stray walking at full speed toward the
	# target). The REGROUP intent + goal checks above pin the decision; this
	# pins the locomotion, tolerating an engagement flip that happens AFTER
	# the stray has already walked 4 m toward the squad.
	var stray_start: Vector3 = stray.global_position
	var ally_cap: Vector3 = ally.global_position
	var to_squad := (ally_cap - stray_start).normalized()
	var max_close := 0.0  # max toward-squad progress while intent == REGROUP
	var waited := 0
	while waited < 240 and max_close < 4.0:
		await frames(5)  # 0.083 sim s steps, up to 4 sim s
		waited += 5
		if ctl.decision.intent != BotDecision.Intent.REGROUP:
			break
		var prog: float = (stray.global_position - stray_start).dot(to_squad)
		if prog > max_close:
			max_close = prog
	check("team: stick walks toward the squad (while REGROUP)", max_close > 4.0,
			"close=%.1f m (intent left REGROUP at %d frames)" % [max_close, waited])
func _test_match_end() -> void:
	# TDM end condition (directive: 3-8 min matches): score cap and time cap.
	# (No lambda listeners: GDScript captures local vars by value.)
	_clear_scene()
	_floor()
	var a := _dummy(0, Vector3(0, 0.9, 0))
	var b := _dummy(1, Vector3(4, 0.9, 0))
	var c := _dummy(1, Vector3(8, 0.9, 0))
	world.score = {0: 0, 1: 0}
	world.match_over = false
	world.winner = -1
	world.target_score = 2
	world.match_duration = 9999.0
	world.kill(b, a, false)
	world.kill(c, a, false)
	await frames(2)
	check("match: score cap ends the match", world.match_over, "score=%s" % str(world.score))
	check("match: score-cap winner is the scoring team", world.winner == 0, "winner=%d" % world.winner)
	world.score = {0: 0, 1: 2}
	world.match_over = false
	world.winner = -1
	world.target_score = 999
	world.match_duration = world.time + 0.5
	await frames(40)
	check("match: time cap ends the match", world.match_over, "time=%.1f" % world.time)
	check("match: time-cap winner is the higher score", world.winner == 1, "winner=%d" % world.winner)
	world.target_score = 15
	world.match_duration = 300.0
	world.score = {0: 0, 1: 0}
	world.match_over = false
	world.winner = -1

func _test_match() -> void:
	# 3v3 bot-vs-bot (zero humans): a normal match produces kills, and an
	# expert squad out-K/Ds a beginner squad (difficulty band). End conditions
	# are disabled: the test world's clock is already past 300 s (the sim
	# freezes on match_over) and a real 15-kill cap could trip mid-test.
	world.target_score = 999
	world.match_duration = 9999.0
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
