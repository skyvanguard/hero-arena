extends Node
## Match lifecycle suite (Phase 5, round 28): a finished match accepts a
## fresh join only when no human is left connected - that join starts a new
## match IN PLACE (World.reset + bot re-fill via match_reset) with frozen
## tokens invalidated; joins into an over match that still has humans
## connected are rejected with the over code. Sim transport (no ENet),
## target_score = 1 so a bot kill ends the match quickly.
const FIXED_DT := 1.0 / 60.0
const PID1 := 1
const PID2 := 2

class In2:
	## Composite inbound sim link: polls several client-side links.
	extends SimLink
	var _links: Array
	func _init(l: Array) -> void:
		_links = l
	func poll() -> void:
		for l in _links:
			l.poll()

var world: World
var arena: Node
var server: MatchServer
var c1: MatchClient
var c2: MatchClient
var l2c: SimLink
var c2s1: SimLink
var c2s2: SimLink
var client_by_pid: Dictionary = {}
var token1 := 0
var snaps_total := 0
var passes := 0
var fails := 0

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

func _ready() -> void:
	randomize()
	world = World.new()
	world.name = "World"
	world.target_score = 1  # first bot kill ends the match (fast lifecycle)
	world.match_duration = 300.0
	add_child(world)
	arena = Arena.build(world)
	add_child(arena)
	l2c = SimLink.new()
	l2c.latency_ms = 20.0
	l2c.loss = 0.01
	c2s1 = SimLink.new()
	c2s1.latency_ms = 20.0
	c2s1.loss = 0.01
	c2s2 = SimLink.new()
	c2s2.latency_ms = 20.0
	c2s2.loss = 0.01
	server = MatchServer.new()
	server.sim_out = l2c
	add_child(server)
	server.setup(world, 7777, 3)
	# Same bot pre-fill as the dedicated server scene.
	_refill_bots()
	# Scene-side bot re-fill on in-place reset (mirrors server_main).
	server.match_reset.connect(_refill_bots)
	l2c.on_packet = func(pid: int, buf: PackedByteArray) -> void:
		# pid 0 = broadcast (snapshots/events, mirroring the ENet behavior of
		# server send id 0 -> all clients); any other pid is a per-peer
		# reliable message (slot) addressed to that client.
		if buf.size() > 0 and buf[0] == NetProtocol.M_SNAPSHOT:
			if pid == 0:
				snaps_total += 1
		if pid == 0:
			for c in [c1, c2]:
				if c != null and is_instance_valid(c):
					c._on_peer_packet(0, buf)
		else:
			var cc = client_by_pid.get(pid, null)
			if cc != null and is_instance_valid(cc):
				cc._on_peer_packet(0, buf)
	c2s1.on_packet = func(_id: int, buf: PackedByteArray) -> void:
		server._on_peer_packet(PID1, buf)
	c2s2.on_packet = func(_id: int, buf: PackedByteArray) -> void:
		server._on_peer_packet(PID2, buf)
	server.sim_in = In2.new([c2s1, c2s2])
	# Phase A: one human in a live 3v3 (bot-filled) match; wait for the
	# first bot kill to end it (target 1).
	c1 = _new_client(c2s1, PID1)
	await _frames(90)
	check("lifecycle: client joins live match", c1.my_id >= 0 and server.slots.size() == 1,
			"my_id=%d slots=%d" % [c1.my_id, server.slots.size()])
	token1 = c1._token
	var waited := 0
	while not world.match_over and waited < 1800:
		await _frames(10)
		waited += 10
	check("lifecycle: bot match finished (over)", world.match_over,
			"score=%d-%d time=%.1f waited=%d frames" % [
			int(world.score.get(0, 0)), int(world.score.get(1, 0)), world.time, waited])
	if fails > 0:
		_done()
		return
	# Phase B: a fresh joiner into the over match while a human is still
	# connected is rejected with the over code (no mid-observation reset).
	c2 = _new_client(c2s2, PID2)
	await _frames(60)
	check("lifecycle: join into over match rejected (human connected)",
			server.slots.size() == 1 and not server.slots.has(PID2) and c2.my_id < 0,
			"slots=%d c2.my_id=%d" % [server.slots.size(), c2.my_id])
	_retire(c2)
	# Phase C: the last human leaves (slot freezes, character stays).
	server._on_peer_disconnected(PID1)
	_retire(c1)
	await _frames(10)
	check("lifecycle: last human left, slot frozen",
			server.slots.is_empty() and server._frozen.size() == 1,
			"slots=%d frozen=%d" % [server.slots.size(), server._frozen.size()])
	# Phase D: a fresh join into the over match with no humans left starts a
	# new match in place (reset + bot re-fill).
	var snap_base := snaps_total
	c2 = _new_client(c2s2, PID2)
	await _frames(15)
	check("lifecycle: fresh join resets the match in place",
			not world.match_over and int(world.score.get(0, 0)) == 0
			and int(world.score.get(1, 0)) == 0 and world.time < 2.0,
			"over=%s score=%d-%d time=%.2f" % [str(world.match_over),
			int(world.score.get(0, 0)), int(world.score.get(1, 0)), world.time])
	check("lifecycle: fresh match has full bot roster + joiner",
			world.characters.size() == 6 and server.slots.size() == 1 and c2.my_id >= 0,
			"chars=%d slots=%d c2.my_id=%d" % [world.characters.size(),
			server.slots.size(), c2.my_id])
	# Phase E: the old human returns with its pre-reset token: the token was
	# invalidated by the reset, so it fresh-joins the new match (no stale
	# reattach to a freed character).
	c1 = _new_client(c2s1, PID1)
	c1._token = token1
	await _frames(30)
	check("lifecycle: pre-reset token fresh-joins (not reattach)",
			server.slots.size() == 2 and c1.my_id >= 0 and c1.my_id != c2.my_id
			and server._frozen.is_empty(),
			"slots=%d c1=%d c2=%d frozen=%d" % [server.slots.size(), c1.my_id,
			c2.my_id, server._frozen.size()])
	# Phase F: the fresh match steps and streams snapshots to both humans.
	var t_base := world.time
	await _frames(90)
	check("lifecycle: fresh match steps + streams snapshots (broadcast)",
			world.time > t_base + 0.4 and (snaps_total - snap_base) > 5,
			"time=%.2f (base %.2f) snaps=%d" % [world.time, t_base,
			snaps_total - snap_base])
	_done()

func _done() -> void:
	print("LIFECYCLE SUITE: %d passed, %d failed" % [passes, fails])
	get_tree().quit(fails)

func _refill_bots() -> void:
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

func _new_client(sim: SimLink, pid: int) -> MatchClient:
	var c := MatchClient.new()
	c.sim_out = sim
	add_child(c)
	c.setup("sim:%d" % pid, HeroRegistry.default_hero())
	client_by_pid[pid] = c
	c.sim_in = l2c
	c._on_connected()
	return c

func _retire(c: MatchClient) -> void:
	if c == null:
		return
	c.exit()
	c.sim_in = null
	c.queue_free()

func _physics_process(_delta: float) -> void:
	if world != null:
		world.step(FIXED_DT)
	if server != null:
		server.tick(FIXED_DT)
