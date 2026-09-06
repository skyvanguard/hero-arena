extends Node
## D35 custom matches suite (round 51): private servers + lobby room
## codes. Covers: code generation/validity (unambiguous alphabet), the
## --room CLI parse, private vs public registration (regack code),
## roomjoinack (ok/unknown/case-insensitive), live room state via
## T_STATE, public-queue exclusion of private matches, code release on
## drop, same-key re-registration (new code, old released), and a
## REAL ENet end-to-end: a MatchClient joins a private MatchServer
## through the resolved room address (slot + bot-filled world). 14 checks.
const LPORT := 7971
const GPORT := 7973
const FIXED_DT := 1.0 / 60.0

var lobby: LobbyServer
var world: World
var arena: Node = null
var server: MatchServer
var passes := 0
var fails := 0

func _frames(n: int):
	for i in n:
		await get_tree().physics_frame

func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		passes += 1
		print("  ok  " + name)
	else:
		fails += 1
		printerr("  FAIL " + name + ("  [" + detail + "]" if detail != "" else ""))

func _wait_until(cond: Callable, frames_max: int = 300) -> bool:
	var n := 0
	while not cond.call() and n < frames_max:
		await _frames(4)
		n += 4
	return cond.call()

func _mk_lob() -> LobbyClient:
	var c := LobbyClient.new()
	add_child(c)
	c.setup("127.0.0.1", LPORT)
	return c

func _run() -> void:
	# 1: code generation - valid, unambiguous, collision-free (fixed seed).
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 12345
	var seen: Dictionary = {}
	var gen_ok := true
	for i in 200:
		var c := LobbyProtocol.gen_room_code(rnd)
		if not LobbyProtocol.is_room_code(c) or seen.has(c):
			gen_ok = false
		seen[c] = true
	check("rooms: 200 generated codes valid + unique", gen_ok and seen.size() == 200,
			"n=%d" % seen.size())
	# 2: the code validator (ambiguous chars, length, case).
	check("rooms: code validator accepts/rejects correctly",
			LobbyProtocol.is_room_code("QZ7KF")
			and not LobbyProtocol.is_room_code("0ABCD")
			and not LobbyProtocol.is_room_code("ABC1D")
			and not LobbyProtocol.is_room_code("ABCD")
			and not LobbyProtocol.is_room_code("abcde"))
	# 3: the --room CLI parse (pure function, incl. defaults).
	var p: Dictionary = ServerMain.parse_args(["--port=8000", "--room",
			"--mode=control", "--map=foundry", "--relay=1.2.3.4:7800"])
	var pd: Dictionary = ServerMain.parse_args([])
	check("rooms: --room parses (flags + defaults)",
			int(p.port) == 8000 and bool(p.room) and str(p.mode) == "control"
			and str(p.map) == "foundry" and str(p.relay) == "1.2.3.4:7800"
			and not bool(pd.room) and int(pd.port) == MatchConfig.net_port,
			"%s" % str(p))
	# Lobby + the real (private) match server for the end-to-end checks.
	world = World.new()
	world.name = "World"
	world.target_score = 999  # the suite runs minutes of world time
	world.match_duration = 900.0
	add_child(world)
	arena = Arena.build(world)
	add_child(arena)
	server = MatchServer.new()
	add_child(server)
	server.setup(world, GPORT, 3)
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
	lobby = LobbyServer.new()
	add_child(lobby)
	lobby.setup(LPORT, "latam_saopaulo", 60.0)
	lobby.reap_after = 1.0  # fast drop for the release checks
	await _frames(10)
	# 4: private vs public registration (regack carries the code only
	#    for private+room servers).
	var got: Dictionary = {}
	var pub := _mk_lob()
	pub.regack.connect(func(i: Dictionary) -> void: got["pub"] = i)
	var priv := _mk_lob()
	priv.regack.connect(func(i: Dictionary) -> void: got["priv"] = i)
	pub.register_match("10.0.0.1", 7001, "latam_saopaulo", 3, "pub", "tdm",
			"crossdocks")
	priv.register_match("127.0.0.1", GPORT, "latam_saopaulo", 3, "priv",
			"control", "foundry", true, true)
	var regged := await _wait_until(func() -> bool:
			return got.has("pub") and got.has("priv"))
	var code := ""
	if regged:
		code = str(got["priv"].get("code", ""))
	check("rooms: private reg gets a code; public reg does not",
			regged and got["pub"].has("code") == false
			and LobbyProtocol.is_room_code(code)
			and lobby.rooms.size() == 1 and lobby.rooms[code] != null,
			"pub=%s priv_code=%s" % [str(got.get("pub", {}).has("code")), code])
	# 5-7: roomjoinack - ok / unknown / case-insensitive.
	var cli := _mk_lob()
	var acks: Array = []  # holder (lambdas capture by value: mutate, never rebind)
	cli.roomjoinack.connect(func(i: Dictionary) -> void: acks.append(i))
	cli.join_room(code)
	var got_ack := await _wait_until(func() -> bool: return acks.size() > 0)
	var ack: Dictionary = acks.pop_back() if acks.size() > 0 else {}
	check("rooms: roomjoinack resolves the private server + live state",
			got_ack and bool(ack.get("ok", false))
			and str(ack.get("host")) == "127.0.0.1" and int(ack.get("port")) == GPORT
			and str(ack.get("mode")) == "control" and str(ack.get("map")) == "foundry"
			and int(ack.get("team_size")) == 3 and int(ack.get("humans")) == 0
			and bool(ack.get("full")) == false, "%s" % str(ack))
	cli.join_room("ZZZZZ")
	await _wait_until(func() -> bool: return acks.size() > 0)
	ack = acks.pop_back() if acks.size() > 0 else {}
	check("rooms: unknown code is rejected with a readable err",
			not ack.is_empty() and bool(ack.get("ok", true)) == false
			and str(ack.get("err", "")) != "", "%s" % str(ack))
	cli.join_room(code.to_lower())
	await _wait_until(func() -> bool: return acks.size() > 0)
	ack = acks.pop_back() if acks.size() > 0 else {}
	check("rooms: codes resolve case-insensitively",
			not ack.is_empty() and bool(ack.get("ok", false)), "%s" % str(ack))
	# 8: live state - the server's T_STATE updates the room view.
	priv.send_state(2, false)
	cli.join_room(code)
	await _wait_until(func() -> bool: return (acks.size() > 0
			and int(acks[acks.size() - 1].get("humans", 0)) == 2))
	ack = acks.pop_back() if acks.size() > 0 else {}
	check("rooms: T_STATE updates the room's player count",
			int(ack.get("humans", 0)) == 2, "%s" % str(ack))
	cli.join_room(code)
	await _wait_until(func() -> bool: return (acks.size() > 0
			and int(acks[acks.size() - 1].get("humans", 0)) == 2))
	ack = acks.pop_back() if acks.size() > 0 else {}
	# verify the full flag flips at team_size
	priv.send_state(3, false)
	cli.join_room(code)
	await _wait_until(func() -> bool: return (acks.size() > 0
			and bool(acks[acks.size() - 1].get("full", false))))
	ack = acks.pop_back() if acks.size() > 0 else {}
	check("rooms: the full flag flips at team_size", bool(ack.get("full", false)),
			"%s" % str(ack))
	# 9: the public queue NEVER assigns a private match.
	var q := _mk_lob()
	var asgs: Array = []
	q.assign.connect(func(i: Dictionary) -> void: asgs.append(i))
	q.join_queue("latam_saopaulo", 1, 0, "Q")
	var assigned := await _wait_until(func() -> bool: return asgs.size() > 0,
			600)
	var asg: Dictionary = asgs.pop_back() if asgs.size() > 0 else {}
	check("rooms: public queue never assigns a private match",
			assigned and str(asg.get("host")) == "10.0.0.1",
			"%s" % str(asg))
	# 10: code release - the private server drops -> the code is unknown.
	priv.queue_free()
	var released := await _wait_until(func() -> bool:
			return lobby.rooms.size() == 0, 600)
	check("rooms: a dropped private match releases its code", released,
			"rooms=%s" % str(lobby.rooms))
	# 11: same-key re-registration - new code, exactly one room again.
	priv = _mk_lob()
	got["priv"] = {}
	priv.regack.connect(func(i: Dictionary) -> void: got["priv"] = i)
	priv.register_match("127.0.0.1", GPORT, "latam_saopaulo", 3, "priv",
			"control", "foundry", true, true)
	var re_reg := await _wait_until(func() -> bool:
			return LobbyProtocol.is_room_code(str(got["priv"].get("code", ""))))
	var code2 := str(got["priv"].get("code", ""))
	check("rooms: re-registration gets a fresh code (one room total)",
			re_reg and lobby.rooms.size() == 1 and lobby.rooms[code2] != null,
			"code2=%s rooms=%s" % [code2, str(lobby.rooms.size())])
	# 12: bot fill - the private match is full of bots before any human.
	check("rooms: the private match is bot-filled (2 x team_size)",
			world.characters.size() == 6,
			"n=%d" % world.characters.size())
	# 13-14: REAL ENet end-to-end - a MatchClient joins the private server
	#       through the room-resolved address and gets a slot.
	var mc := MatchClient.new()
	add_child(mc)
	mc.setup("127.0.0.1:%d" % GPORT, HeroRegistry.default_hero())
	var got_slot := await _wait_until(func() -> bool: return mc.my_id >= 0, 600)
	check("rooms: end-to-end join via the room address (slot)",
			got_slot and mc.my_id >= 0, "my_id=%d" % mc.my_id)
	priv.send_state(1, false)
	cli.join_room(code2)
	await _wait_until(func() -> bool: return (acks.size() > 0
			and int(acks[acks.size() - 1].get("humans", 0)) == 1))
	ack = acks.pop_back() if acks.size() > 0 else {}
	check("rooms: the human's join is visible in the room state",
			int(ack.get("humans", 0)) == 1, "%s" % str(ack))
	print("ROOMS SUITE: %d passed, %d failed" % [passes, fails])
	get_tree().quit(fails)

## The sim is host-driven (like test_net): World does not step itself and
## MatchServer only polls the transport inside tick() - without this the
## end-to-end ENet handshake never completes.
func _physics_process(_delta: float) -> void:
	if world != null:
		world.step(FIXED_DT)
	if server != null:
		server.tick(FIXED_DT)

func _ready() -> void:
	_run()
