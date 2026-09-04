extends Node
## Net-sim harness (Phase 5): a full 3v3 through SimLink transports with
## 150 ms RTT (75 ms per way) + 2% loss per packet - the loopback ENet suite
## proves the wire at 0 ms; this proves the same code under latency and loss
## (snapshot refresh, prediction + reconciliation, input roundtrip, combat,
## and the drop -> freeze -> token reattach reconnect path).
const FIXED_DT := 1.0 / 60.0
const LAT_MS := 75.0     # one way (150 ms RTT)
const LOSS := 0.02
const PEER := 1

var world: World
var server: MatchServer
var client: MatchClient
var l2c: SimLink
var c2s: SimLink
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
	world.target_score = 999  # keep the match alive through the test
	world.match_duration = 300.0
	add_child(world)
	var arena := Arena.build(world)
	add_child(arena)

	l2c = SimLink.new()
	l2c.latency_ms = LAT_MS
	l2c.loss = LOSS
	c2s = SimLink.new()
	c2s.latency_ms = LAT_MS
	c2s.loss = LOSS

	server = MatchServer.new()
	server.sim_out = l2c
	add_child(server)
	server.setup(world, 7777, 3)
	# Bot pre-fill (like the dedicated server scene).
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

	client = MatchClient.new()
	client.sim_out = c2s
	add_child(client)
	client.setup("sim:0", HeroRegistry.default_hero())
	l2c.on_packet = func(_id: int, buf: PackedByteArray) -> void:
		client._on_peer_packet(0, buf)
	c2s.on_packet = func(_id: int, buf: PackedByteArray) -> void:
		server._on_peer_packet(PEER, buf)
	server.sim_in = c2s
	client.sim_in = l2c
	client._on_connected()  # sim mode: no ENet, the test drives the hello
	await _run()
	print("NET SIM SUITE: %d passed, %d failed" % [passes, fails])
	get_tree().quit(fails)

func _run() -> void:
	# 1: connect + slot through the lossy link (reliable channel + 150 ms RTT).
	await _frames(90)  # 1.5 s
	check("sim: client connects and gets a slot (150 ms RTT)",
			client.my_id >= 0 and server.slots.size() == 1,
			"my_id=%d slots=%d" % [client.my_id, server.slots.size()])
	if client.my_id < 0:
		print("NET SIM SUITE: %d passed, %d failed (aborted: no slot)" % [passes, fails])
		get_tree().quit(fails)
		return
	var sv: Array = server.slots.values()
	var _human: CharacterEntity = sv[0].ch if sv.size() > 0 else null
	# 2: input roundtrip under latency - drive forward 3 s.
	var start_pos: Vector3 = _human.global_position
	Controls.move = Vector2(0, 1)
	Controls.fire = true
	await _frames(180)
	Controls.move = Vector2.ZERO
	Controls.fire = false
	var moved := _human.global_position.distance_to(start_pos)
	check("sim: input moves the server character under 150 ms RTT",
			moved > 3.0, "moved=%.1f m" % moved)
	await _frames(30)

	# 3: prediction tracks the server state (local view = prediction).
	var view: CharacterEntity = client._views.get(client.my_id, null)
	var err := 1e9
	if view != null:
		err = view.global_position.distance_to(_human.global_position)
	check("sim: predicted view tracks server state under latency",
			client._pch != null and err < 1.5,
			"pch=%s err=%.2f" % [str(client._pch != null), err])
	await _frames(30)

	# 4: combat still runs (bots server-side; snapshots + events flow).
	await _frames(3000)  # 50 sim seconds
	var kills := int(world.score.get(0, 0)) + int(world.score.get(1, 0))
	check("sim: combat runs with 150 ms RTT + 2% loss", kills >= 2,
			"score=%d-%d" % [int(world.score.get(0, 0)), int(world.score.get(1, 0))])
	check("sim: kill feed relayed under loss", client.hud != null
			and client.hud._feed_shown != "",
			"feed=%s" % ("" if client.hud == null else client.hud._feed_shown))

	# 5: reconnect - drop the link, freeze, re-hello with the token.
	var old_ch: CharacterEntity = _human
	var old_id := int(server.char_ids.get(old_ch, -1))
	var token := client._token
	check("sim: session token issued", token > 0, "token=%d" % token)
	c2s.drop_all()
	l2c.drop_all()
	server._on_peer_disconnected(PEER)  # what ENet would report
	check("sim: server froze the slot on drop",
			server._frozen.size() == 1 and old_ch.controller == null,
			"frozen=%d" % server._frozen.size())
	# Retire the dead client (it would otherwise poll the same inbound link
	# and steal client2's packets) - like a real app replacing the session.
	client.exit()
	client.sim_in = null
	client.queue_free()
	var client2 := MatchClient.new()
	client2.sim_out = c2s
	add_child(client2)
	client2.setup("sim:0", HeroRegistry.default_hero())
	client2._token = token
	client2.sim_in = l2c
	l2c.on_packet = func(_id: int, buf: PackedByteArray) -> void:
		client2._on_peer_packet(0, buf)
	client2._on_connected()
	await _frames(90)
	var s2: Dictionary = server.slots.get(PEER, {})
	check("sim: reattach reuses the same character",
			client2.my_id == old_id and s2.get("ch", null) == old_ch
			and old_ch.controller != null,
			"my_id=%d old=%d" % [client2.my_id, old_id])
	check("sim: token consumed after reattach",
			not server._frozen.has(token), "frozen=%d" % server._frozen.size())
	# 6: the match kept running through the drop.
	await _frames(60)
	check("sim: server kept stepping through the drop",
			world.time > 55.0, "time=%.1f" % world.time)
	client2.exit()

func _physics_process(_delta: float) -> void:
	if world != null:
		world.step(FIXED_DT)
	if server != null:
		server.tick(FIXED_DT)
