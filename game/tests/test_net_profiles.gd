extends Node
## Net-sim latency/loss PROFILE suite (Phase 5, round 28): the same battery as
## test_net_sim.gd (connect + slot, input roundtrip, prediction tracking,
## 50 s combat + kill feed, drop -> freeze -> token reattach, server keeps
## stepping) driven through SimLink transports at three profiles:
##   50 ms RTT + 10% loss  |  150 ms RTT + 2% loss (the shipped baseline)
##   300 ms RTT + 10% loss
## One scene run proves all profiles; each profile gets a fresh world/server/
## client and is torn down before the next. Keep the battery in sync with
## test_net_sim.gd (deliberate duplication to leave the baseline suite alone).
const FIXED_DT := 1.0 / 60.0
const PEER := 1
const PROFILES: Array = [
	{"name": "50msRTT/10%loss", "lat": 25.0, "loss": 0.10},
	{"name": "150msRTT/2%loss", "lat": 75.0, "loss": 0.02},
	{"name": "300msRTT/10%loss", "lat": 150.0, "loss": 0.10},
]

var world: World
var arena: Node
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
	for p in PROFILES:
		await _run_profile(p)
		await _teardown()
	print("NET PROFILES SUITE: %d passed, %d failed" % [passes, fails])
	get_tree().quit(fails)

func _run_profile(p: Dictionary) -> void:
	var nm: String = str(p["name"])
	world = World.new()
	world.name = "World"
	world.target_score = 999  # keep the match alive through the test
	world.match_duration = 300.0
	add_child(world)
	arena = Arena.build(world)
	add_child(arena)
	l2c = SimLink.new()
	l2c.latency_ms = float(p["lat"])
	l2c.loss = float(p["loss"])
	c2s = SimLink.new()
	c2s.latency_ms = float(p["lat"])
	c2s.loss = float(p["loss"])
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
	client._on_connected()
	# 1: connect + slot through the lossy link.
	await _frames(90)
	check("profiles[" + nm + "]: client connects and gets a slot",
			client.my_id >= 0 and server.slots.size() == 1,
			"my_id=%d slots=%d" % [client.my_id, server.slots.size()])
	if client.my_id < 0:
		print("profiles[%s]: aborted (no slot)" % nm)
		return
	var sv: Array = server.slots.values()
	var human: CharacterEntity = sv[0].ch if sv.size() > 0 else null
	# 2: input roundtrip under latency - drive forward 3 s.
	var start_pos: Vector3 = human.global_position
	Controls.move = Vector2(0, 1)
	Controls.fire = true
	await _frames(180)
	Controls.move = Vector2.ZERO
	Controls.fire = false
	var moved := human.global_position.distance_to(start_pos)
	check("profiles[" + nm + "]: input moves the server character",
			moved > 3.0, "moved=%.1f m" % moved)
	await _frames(30)
	# 3: prediction tracks the server state. Error budget grows with RTT
	# (the unreconciled window is ~RTT/2 + interpolation): 1.5 m at the
	# 150 ms baseline, scaled linearly beyond it.
	var pred_budget := 1.5 * (1.0 + maxf(0.0, (float(p["lat"]) * 2.0 - 150.0) / 150.0))
	var view: CharacterEntity = client._views.get(client.my_id, null)
	var err := 1e9
	if view != null:
		err = view.global_position.distance_to(human.global_position)
	check("profiles[" + nm + "]: predicted view tracks server state (budget %.1f m)" % pred_budget,
			client._pch != null and err < pred_budget,
			"pch=%s err=%.2f" % [str(client._pch != null), err])
	await _frames(30)
	# 4: combat still runs (bots server-side; snapshots + events flow).
	await _frames(3000)  # 50 sim seconds
	var kills := int(world.score.get(0, 0)) + int(world.score.get(1, 0))
	check("profiles[" + nm + "]: combat runs", kills >= 2,
			"score=%d-%d" % [int(world.score.get(0, 0)), int(world.score.get(1, 0))])
	check("profiles[" + nm + "]: kill feed relayed", client.hud != null
			and client.hud._feed_shown != "",
			"feed=%s" % ("" if client.hud == null else client.hud._feed_shown))
	# 5: reconnect - drop the link, freeze, re-hello with the token.
	var old_ch: CharacterEntity = human
	var old_id := int(server.char_ids.get(old_ch, -1))
	var token := client._token
	check("profiles[" + nm + "]: session token issued", token > 0, "token=%d" % token)
	c2s.drop_all()
	l2c.drop_all()
	server._on_peer_disconnected(PEER)
	check("profiles[" + nm + "]: server froze the slot on drop",
			server._frozen.size() == 1 and old_ch.controller == null,
			"frozen=%d" % server._frozen.size())
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
	check("profiles[" + nm + "]: reattach reuses the same character",
			client2.my_id == old_id and s2.get("ch", null) == old_ch
			and old_ch.controller != null,
			"my_id=%d old=%d" % [client2.my_id, old_id])
	check("profiles[" + nm + "]: token consumed after reattach",
			not server._frozen.has(token), "frozen=%d" % server._frozen.size())
	# 6: the match kept running through the drop.
	await _frames(60)
	check("profiles[" + nm + "]: server kept stepping through the drop",
			world.time > 55.0, "time=%.1f" % world.time)
	client2.exit()
	client2.sim_in = null
	client2.queue_free()
	client = null

func _teardown() -> void:
	# Break the closure holds (link.on_packet -> endpoint) before freeing.
	if l2c != null:
		l2c.on_packet = Callable()
	if c2s != null:
		c2s.on_packet = Callable()
	if server != null:
		server.exit()
		server.sim_out = null
		server.sim_in = null
		server.queue_free()
		server = null
	if arena != null:
		arena.queue_free()
		arena = null
	if world != null:
		world.queue_free()
		world = null
	await _frames(3)

func _physics_process(_delta: float) -> void:
	if world != null:
		world.step(FIXED_DT)
	if server != null:
		server.tick(FIXED_DT)
