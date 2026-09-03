extends Node
## Net loopback suite (Phase 5 v1): MatchServer + MatchClient in ONE process
## (ENet over 127.0.0.1) - validates the whole wire path headlessly:
## hello/slot, snapshot -> interpolated view, input roundtrip, event relay,
## server survival on disconnect. CI-safe: no physical LAN needed.
##
## NOTE: the server world and the client world share the process physics
## space, so client views must be physics-invisible (match_client zeroes
## their collision) - otherwise they push server characters and block the
## bots' LOS rays (verified in the Phase 5 net debug: bots scanning for
## minutes never "saw" a 30 m enemy because a view head-sensor sat on it).
const FIXED_DT := 1.0 / 60.0
const PORT := 7999

var world: World
var server: MatchServer
var client: MatchClient
var passes := 0
var fails := 0
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
	add_child(server)
	server.setup(world, PORT, 3)
	# Pre-fill both teams with bots exactly like net/server.tscn does.
	var roster: Array = HeroRegistry.HEROES.duplicate()
	roster.shuffle()
	var rix := 0
	for team in 2:
		var pts: Array = world.spawn_points.get(team, [])
		for i in 3:
			if pts.size() <= i:
				break
			var data: HeroData = roster[rix % roster.size()]
			rix += 1
			server.spawn_bot(team, data, pts[i])
	await _frames(5)
	client = MatchClient.new()
	add_child(client)
	client.setup("127.0.0.1:%d" % PORT, HeroRegistry.default_hero())
	await _run()
	print("NET SUITE: %d passed, %d failed" % [passes, fails])
	get_tree().quit(fails)

func _run() -> void:
	# 1-3: connect, slot, hero respected, bot yield.
	await _frames(60)
	check("net: client connects and gets a slot",
			client.my_id >= 0 and server.slots.size() == 1,
			"my_id=%d slots=%d" % [client.my_id, server.slots.size()])
	var sv: Array = server.slots.values()
	_human = sv[0].ch if sv.size() > 0 else null
	check("net: hello hero id is honored on the server",
			_human != null and _human.hero_data != null
			and _human.hero_data.id == HeroRegistry.default_hero().id,
			"%s" % ("" if _human == null else str(_human.hero_data)))
	check("net: bot yield keeps the team at team_size",
			_human != null and server.team_chars[_human.team].size() == 3,
			"team0=%d team1=%d" % [server.team_chars[0].size(), server.team_chars[1].size()])
	if _human == null:
		fails += 1
		print("FAIL net: no human character, aborting remaining checks")
		get_tree().quit(fails)
		return
	# 4: snapshots build the local views (human + 5 bots; the replaced bot
	# is freed, so exactly 6 characters are in the match).
	await _frames(30)
	check("net: snapshots build interpolated views",
			client._views.size() == 6 and client._views.has(client.my_id),
			"views=%d (expect 6: human + 5 bots)" % client._views.size())
	# 5: input roundtrip - drive the local player forward for 3 sim seconds.
	var spawn_pos: Vector3 = _human.global_position
	Controls.move = Vector2(0, 1)
	Controls.fire = true
	await _frames(180)
	Controls.move = Vector2.ZERO
	Controls.fire = false
	var moved := _human.global_position.distance_to(spawn_pos)
	check("net: input roundtrip moves the server character",
			moved > 3.0, "moved=%.1f m" % moved)
	check("net: aim direction respected (faced +Z while driving)",
			absf(wrapf(_human.rotation.y - 0.0, -PI, PI)) < 0.5,
			"rot_y=%.2f" % _human.rotation.y)
	# 6: interpolated view converges on the server state.
	var view: CharacterEntity = client._views.get(client.my_id, null)
	var d := 1e9
	if view != null:
		d = view.global_position.distance_to(_human.global_position)
	check("net: interpolated view tracks server state",
			d < 1.5, "dist=%.2f" % d)
	# 7: combat + event relay - the bot squads fight while we hold position.
	await _frames(3600)  # 60 sim seconds
	var kills := int(world.score.get(0, 0)) + int(world.score.get(1, 0))
	check("net: combat runs server-side (kills registered)", kills >= 2,
			"score=%d-%d" % [int(world.score.get(0, 0)), int(world.score.get(1, 0))])
	check("net: kill events relay to client feed", client.hud != null
			and client.hud._feed_shown != "", "feed=%s" % ("" if client.hud == null else client.hud._feed_shown))
	# 8: server survives the client disconnect and keeps stepping.
	var seq_before := server._snap_seq
	client.exit()
	client.queue_free()
	await _frames(60)
	check("net: server keeps stepping after client disconnect",
			world.time > 0.0 and server._snap_seq != seq_before,
			"time=%.1f" % world.time)
	get_tree().quit(fails)

func _physics_process(_delta: float) -> void:
	if world != null:
		world.step(FIXED_DT)
	if server != null:
		server.tick(FIXED_DT)
