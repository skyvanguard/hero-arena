extends Node
## Server-authority property tests (Phase 5): crafted input frames go
## straight into MatchServer (sim transport, no ENet) and must be clamped /
## rejected - "client lies are rejected" (damage, ammo, movement, aim).
## Plus deterministic World-level lag-compensation geometry tests.
const FIXED_DT := 1.0 / 60.0
const PEER := 1

var world: World
var server: MatchServer
var passes := 0
var fails := 0
var _seq := 0
var _human: CharacterEntity = null

func check(name: String, cond: bool, detail := "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		fails += 1
		print("FAIL ", name, ("  [" + detail + "]" if detail != "" else ""))

func _frames(n: int):
	for i in n:
		await get_tree().physics_frame

func _slot() -> Dictionary:
	return server.slots.get(PEER, {})

func _send(move: Vector2, yaw: float, pitch: float, fire: bool, edges: int,
		time_est: float = 0.0) -> void:
	_seq += 1
	var buf := NetProtocol.pack_input(_seq % 65536, move, yaw, pitch, fire,
			edges, time_est)
	server._on_input(PEER, buf)

func _send_raw(seq: int, move: Vector2, fire: bool, edges: int) -> void:
	var buf := NetProtocol.pack_input(seq, move, 0.0, -0.18, fire, edges, 0.0)
	server._on_input(PEER, buf)

func _ready() -> void:
	randomize()
	world = World.new()
	world.name = "World"
	world.target_score = 15
	world.match_duration = 300.0
	add_child(world)
	var arena := Arena.build(world)
	add_child(arena)
	server = MatchServer.new()
	var out := SimLink.new()  # outbound sink: M_SLOT etc. queue and drain harmlessly
	out.on_packet = func(_i: int, _b: PackedByteArray) -> void: pass
	server.sim_out = out
	add_child(server)
	server.setup(world, 7777, 3)
	# Bot-fill both teams (like the real server scene).
	var roster: Array = HeroRegistry.HEROES.duplicate()
	roster.shuffle()
	var rix := 0
	for team in 2:
		var pts: Array = world.spawn_points.get(team, [])
		for i in 3:
			if pts.size() <= i:
				break
			server.spawn_bot(team, roster[rix % roster.size()], pts[i])
			rix += 1
	await _frames(5)
	# Join like a client would.
	var hello := NetProtocol.pack_hello(3, HeroRegistry.default_hero().id, 0)
	server._on_hello(PEER, NetProtocol.unpack_hello(hello))
	_human = (_slot().get("ch", null)) as CharacterEntity
	if _human == null:
		fails += 1
		print("FAIL props: human character missing, aborting")
		get_tree().quit(fails)
		return
	await _run()

func _run() -> void:
	# Quiet the bots so the human is a stable target for the geometry tests.
	for ch in world.characters:
		if ch != _human and ch.controller != null:
			ch.controller = null

	# 1: move magnitude is clamped (client lies about joystick input).
	_send(Vector2(1000.0, 1000.0), 0.0, -0.18, false, 0)

	await _frames(30)
	var p0: Vector3 = _human.global_position
	await _frames(30)
	var p1: Vector3 = _human.global_position
	var speed := p1.distance_to(p0) / (30.0 * FIXED_DT)
	check("props: move magnitude clamped to max run speed",
			speed <= _human.base_speed * 1.05 + 0.01,
			"speed=%.2f max=%.2f" % [speed, _human.base_speed])

	# 2: stale / replayed seq must not clobber state.
	var s := _seq + 1
	_seq = s
	_send_raw(s, Vector2(0.0, 1.0), true, 0)
	_send_raw(s - 1, Vector2(1.0, 0.0), false, 0)  # older seq, arrives after
	var sl := _slot()
	check("props: stale seq rejected (fire kept)",
			bool(sl.input.fire) == true, "fire=%s" % str(sl.input.fire))
	check("props: stale seq rejected (move kept)",
			(sl.input.move as Vector2).y == 1.0, "move=%s" % str(sl.input.move))

	# 3: a stale frame must not re-deliver an already-consumed edge.
	_seq = s + 1
	_send(Vector2.ZERO, 0.0, -0.18, false, 2)  # reload edge, fresh seq
	await _frames(2)  # controller consumes it
	_send_raw(s, Vector2.ZERO, false, 2)  # same edge on the OLD seq
	check("props: stale edge not re-consumed",
			int(_slot().input.edges) == 0, "edges=%d" % int(_slot().input.edges))

	# 4: aim bounds are clamped server-side.
	_send(Vector2.ZERO, 100.0, 3.0, false, 0)
	var sl2 := _slot()
	check("props: pitch clamped", float(sl2.input.pitch) <= 0.9 + 0.001,
			"pitch=%.2f" % float(sl2.input.pitch))
	_send(Vector2.ZERO, -100.0, -5.0, false, 0)
	var sl3 := _slot()
	check("props: pitch clamped low", float(sl3.input.pitch) >= -1.25 - 0.001,
			"pitch=%.2f" % float(sl3.input.pitch))
	check("props: yaw wrapped", absf(float(sl3.input.yaw)) <= PI + 0.001,
			"yaw=%.2f" % float(sl3.input.yaw))

	# 5: ammo can never go negative; shot events match the weapon's count.
	var counter := {"n": 0}
	var ammo_ok := true
	var conn := func(n: String, d: Dictionary) -> void:
		if n == "shot":
			counter.n += 1
	world.world_event.connect(conn)
	_send(Vector2.ZERO, 0.0, -0.18, true, 0)
	for i in 1200:
		await get_tree().physics_frame
		if (_human.weapon.ammo as int) < 0:
			ammo_ok = false
	check("props: ammo never negative over 20 s of fire", ammo_ok,
			"ammo=%d" % _human.weapon.ammo)
	check("props: shot events == weapon shots_fired",
			int(counter.n) == int(_human.weapon.shots_fired),
			"events=%d weapon=%d" % [int(counter.n), int(_human.weapon.shots_fired)])

	# 6-8: lag comp geometry (deterministic, World level).
	await _lag_comp_tests()

	# 9: reconnect reattach (server side).
	await _reconnect_test()

	print("NET PROPS SUITE: %d passed, %d failed" % [passes, fails])
	get_tree().quit(fails)

## Shooter aims at where the target WAS: with the measured delay the hit
## validates (rewound pose), without it the same ray misses (the target
## outran the ray). Target: 4 m/s along +X on open ground.
func _lag_comp_tests() -> void:
	var shooter := _human
	# A dedicated bot as target (bots are quieted already).
	var target := server.spawn_bot(1, HeroRegistry.default_hero(),
			Vector3(8.0, 0.9, 0.0))
	target.controller = null
	var v := Vector3(0.0, 0.0, 4.0)  # m/s along +Z (perp to line of sight)
	for i in 60:  # 1 s: target reaches (8, 0.9, 4)
		target.global_position = target.global_position + v * FIXED_DT
		world.step(FIXED_DT)
	await _frames(1)
	var now: Vector3 = target.global_position
	var D := 0.15
	var origin := Vector3(-5.0, 0.9, 0.0)
	var then: Vector3 = now - v * D  # (8, 0.9, 3.4)
	var dir: Vector3 = (then - origin).normalized()  # capsule center
	shooter.net_comp_delay = D
	var hit: Dictionary = world.hitscan(origin, dir, shooter, 120.0)
	check("lagcomp: shot at old pose validates with delay",
			hit.ch == target, "hit=%s" % str(hit.ch))
	var head_dir: Vector3 = (then + Vector3(0.0, CharacterEntity.HEAD_OFFSET, 0.0) - origin).normalized()
	var hh: Dictionary = world.hitscan(origin, head_dir, shooter, 120.0)
	check("lagcomp: rewound head is a headshot",
			hh.ch == target and bool(hh.is_head),
			"hit=%s head=%s" % [str(hh.ch), str(hh.is_head)])
	shooter.net_comp_delay = 0.0
	var miss: Dictionary = world.hitscan(origin, dir, shooter, 120.0)
	check("lagcomp: same ray misses at delay 0 (target outran it)",
			miss.ch != target, "hit=%s" % str(miss.ch))
	# Window clamp: delay far above the window still only rewinds to the
	# history cap (~window). Aim at the pose ~window ago -> hit; aim at a
	# pose older than the cap -> miss.
	shooter.net_comp_delay = 0.5
	var w_dir: Vector3 = (now - v * world.lag_comp_window - origin).normalized()
	var wh: Dictionary = world.hitscan(origin, w_dir, shooter, 120.0)
	check("lagcomp: delay clamped to window (hit at window edge)",
			wh.ch == target, "hit=%s" % str(wh.ch))
	var old_dir: Vector3 = (now - v * (world.lag_comp_window + 0.35) - origin).normalized()
	var oh: Dictionary = world.hitscan(origin, old_dir, shooter, 120.0)
	check("lagcomp: pose older than the window is not rewound",
			oh.ch != target, "hit=%s" % str(oh.ch))
	shooter.net_comp_delay = 0.0
	target.queue_free()

func _reconnect_test() -> void:
	var token := int(_slot().get("token", 0))
	check("reconnect: slot carries a session token", token > 0, "token=%d" % token)
	var old_ch := _human
	var old_id := int(server.char_ids.get(old_ch, -1))
	# The peer drops; the server freezes the slot.
	server._on_peer_disconnected(PEER)
	check("reconnect: slot frozen with token",
			server._frozen.has(token) and old_ch.controller == null,
			"frozen=%d" % server._frozen.size())
	check("reconnect: frozen char cleared (comp delay zeroed)",
			float(old_ch.net_comp_delay) == 0.0,
			"delay=%.3f" % float(old_ch.net_comp_delay))
	var hello := NetProtocol.pack_hello(3, HeroRegistry.default_hero().id, token)
	server._on_hello(2, NetProtocol.unpack_hello(hello))  # new peer id
	var s2: Dictionary = server.slots.get(2, {})
	check("reconnect: same character reattached (same instance + id)",
			s2.get("ch", null) == old_ch and int(server.char_ids.get(old_ch, -1)) == old_id
			and old_ch.controller != null,
			"ch=%s" % str(s2.get("ch", null)))
	check("reconnect: token consumed + team humans restored",
			not server._frozen.has(token)
			and int(server.team_humans[int(old_ch.team)]) == 1,
			"frozen=%d humans=%s" % [server._frozen.size(), str(server.team_humans)])
	# A hello with a dead token (slot yielded to a fresh join) falls through
	# to a normal join instead of crashing.
	server._free_character(old_ch)
	var hello2 := NetProtocol.pack_hello(3, HeroRegistry.default_hero().id, token)
	server._on_hello(3, NetProtocol.unpack_hello(hello2))
	check("reconnect: dead token falls through to fresh join",
			server.slots.has(3) and server.slots[3].get("ch", null) != old_ch,
			"slot3=%d" % server.slots.size())

func _physics_process(_delta: float) -> void:
	if world != null:
		world.step(FIXED_DT)
	if server != null:
		server.tick(FIXED_DT)
