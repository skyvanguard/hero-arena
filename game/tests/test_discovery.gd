extends Node
## LAN discovery tests (Phase 5): UDP ping/reply over loopback (no ENet).
## Covers the open / humans-counted / full / over states, an empty scan, and
## the scanner's finished contract.
const FIXED_DT := 1.0 / 60.0
const GAME_PORT := 7997
const DISC_PORT := 7998
const DEAD_PORT := 7990

var world: World
var server: MatchServer
var disc: Discovery
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

## This dev box answers the broadcast from its LAN IP as well as the
## unicast from loopback (same server, two interfaces) - prefer 127.0.0.1.
func _pick(r: Array) -> Dictionary:
	for d in r:
		if d.ip == "127.0.0.1":
			return d
	return r[0] if r.size() > 0 else {}

## Run a scan against the (possibly changed) discovery port until finished.
func _scan(unicast: String, port: int) -> Array:
	MatchConfig.net_discovery_port = port
	var sc := DiscoveryScanner.new()
	sc.timeout_s = 1.2
	var out: Array = []
	sc.found.connect(func(d: Dictionary) -> void: out.append(d))
	var t0 := Time.get_ticks_msec()
	sc.start(unicast)
	while not sc.finished and Time.get_ticks_msec() - t0 < 2500:
		sc.pump()
		await get_tree().process_frame
	return out

func _ready() -> void:
	randomize()
	world = World.new()
	world.name = "World"
	world.target_score = 999
	world.match_duration = 300.0
	add_child(world)
	var arena := Arena.build(world)
	add_child(arena)
	server = MatchServer.new()
	var out_link := SimLink.new()
	out_link.on_packet = func(_i: int, _b: PackedByteArray) -> void: pass
	server.sim_out = out_link
	add_child(server)
	server.setup(world, GAME_PORT, 3)
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
	disc = Discovery.new()
	disc.game_port = GAME_PORT
	var net_ref := server
	var world_ref := world
	disc.state_provider = func() -> Dictionary:
		var state := NetProtocol.DISC_OPEN
		if world_ref.match_over:
			state = NetProtocol.DISC_OVER
		else:
			var full := true
			for t in 2:
				if int(net_ref.team_humans[t]) < 3:
					full = false
			if full:
				state = NetProtocol.DISC_FULL
		return {"state": state, "team_size": 3,
				"humans": int(net_ref.team_humans[0]) + int(net_ref.team_humans[1]),
				"target_score": world_ref.target_score, "time": world_ref.time}
	add_child(disc)
	disc.setup(DISC_PORT)
	await _frames(10)
	# 1: open server advertises itself with the game port.
	var r1: Array = await _scan("127.0.0.1", DISC_PORT)
	var d1: Dictionary = _pick(r1)
	check("disc: open server answers a ping",
			not d1.is_empty() and int(d1.game_port) == GAME_PORT,
			"n=%d" % r1.size())
	if not d1.is_empty():
		check("disc: reply carries game port + state open + humans 0",
				int(d1.state) == NetProtocol.DISC_OPEN
				and int(d1.humans) == 0 and int(d1.team_size) == 3,
				"port=%d state=%d humans=%d" % [int(d1.game_port),
						int(d1.state), int(d1.humans)])
	# 2: a human join updates the advertised headcount.
	var hello := NetProtocol.pack_hello(3, HeroRegistry.default_hero().id, 0)
	server._on_hello(1, NetProtocol.unpack_hello(hello))
	await _frames(5)
	var r2: Array = await _scan("127.0.0.1", DISC_PORT)
	var d2: Dictionary = _pick(r2)
	check("disc: join is reflected in the headcount",
			not d2.is_empty() and int(d2.humans) == 1,
			"n=%d humans=%s" % [r2.size(), str(d2.get("humans", "-"))])
	# 3: full teams advertise full (no fresh join possible).
	server.team_humans = [3, 3]
	var r3: Array = await _scan("127.0.0.1", DISC_PORT)
	var d3: Dictionary = _pick(r3)
	check("disc: full server advertises full",
			not d3.is_empty() and int(d3.state) == NetProtocol.DISC_FULL,
			"state=%s" % str(d3.get("state", "-")))
	server.team_humans = [1, 0]
	# 4: match over advertises over (and wins over full).
	world.match_over = true
	server.team_humans = [3, 3]
	var r4: Array = await _scan("127.0.0.1", DISC_PORT)
	var d4: Dictionary = _pick(r4)
	check("disc: finished match advertises over",
			not d4.is_empty() and int(d4.state) == NetProtocol.DISC_OVER,
			"state=%s" % str(d4.get("state", "-")))
	world.match_over = false
	server.team_humans = [1, 0]
	# 5: scanning a dead port finishes with zero results, no crash.
	var r5: Array = await _scan("127.0.0.1", DEAD_PORT)
	check("disc: dead port scan finishes empty",
			r5.size() == 0, "n=%d" % r5.size())
	print("DISCOVERY SUITE: %d passed, %d failed" % [passes, fails])
	get_tree().quit(fails)

func _physics_process(_delta: float) -> void:
	if world != null:
		world.step(FIXED_DT)
	if server != null:
		server.tick(FIXED_DT)
