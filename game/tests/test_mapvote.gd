extends Node
## Next-match MAP voting suite (Phase 6, round 35, D21): same lobby, same
## rules, second domain. 17 checks (round 44, D27 anti-repetition added):
## reg carries the host map, bad-map votes
## ignored, one map vote per peer (last write wins), mode and map tallies
## are independent per peer, split map votes hold, strict majority flips
## the directory map + forwards setmap to the match server, the pending
## map applies at the next reset (arena rebuilt, spawn points change),
## assign carries the map vote state, and the state heartbeat keeps the
## directory map fresh.
const LPORT := 7963
const GPORT := 7964
const TOL := 4.0

var lobby: LobbyServer
var srv_lob: LobbyClient
var voter_a: LobbyClient
var voter_b: LobbyClient
var world: World
var net: MatchServer
var arena: Node = null
var match_id := 0
var passed := 0
var failed := 0

func _ready() -> void:
	lobby = LobbyServer.new()
	lobby.set_process(false)
	add_child(lobby)
	lobby.setup(LPORT, "latam_saopaulo", 60.0)
	world = World.new()
	world.name = "World"
	world.target_score = 15
	add_child(world)
	arena = Arena.build(world)
	add_child(arena)
	world.mode = ModeRegistry.get_mode("tdm")
	world.mode.setup(world)
	net = MatchServer.new()
	add_child(net)
	net.setup(world, GPORT, 3)
	srv_lob = LobbyClient.new()
	srv_lob.set_process(false)
	add_child(srv_lob)
	srv_lob.setup("127.0.0.1", LPORT)
	voter_a = await _client()
	voter_b = await _client()
	_run()

func _physics_process(_d: float) -> void:
	lobby.tick(1.0 / 60.0)
	for c in get_children():
		if c is LobbyClient:
			c.pump(1.0 / 60.0)
	if net != null:
		net.tick(1.0 / 60.0)

func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		passed += 1
		print("  ok  " + name)
	else:
		failed += 1
		printerr("  FAIL " + name + ("  [" + detail + "]" if detail != "" else ""))

func _client() -> LobbyClient:
	var c := LobbyClient.new()
	c.set_process(false)
	add_child(c)
	c.setup("127.0.0.1", LPORT)
	await get_tree().physics_frame
	return c

func _wait_flag(flag: Array, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout_s * 1000):
		if flag[0]:
			return true
		await get_tree().physics_frame
	return false

func _wait_mapvote(c: LobbyClient) -> Dictionary:
	var flag := [false]
	var data := [{}]
	c.map_vote_result.connect(func(i: Dictionary) -> void:
		flag[0] = true
		data[0] = i
	)
	await _wait_flag(flag, TOL)
	return data[0]

func _run() -> void:
	# The server-side wiring server_main.gd uses: a decided map vote
	# arrives as setmap and the MatchServer stores it for the next reset.
	var sflag := [false]
	var sdata := [{}]
	srv_lob.setmap.connect(func(i: Dictionary) -> void:
		sflag[0] = true
		sdata[0] = i
		net.set_map_from_lobby(str(i.get("map", "")))
	)
	# 1: registration carries the host map.
	var rflag := [false]
	var rdata := [{}]
	srv_lob.regack.connect(func(i: Dictionary) -> void:
		rflag[0] = true
		rdata[0] = i
	)
	srv_lob.register_match("127.0.0.1", GPORT, "latam_saopaulo", 3, "mapvote test", "tdm", "crossdocks")
	await _wait_flag(rflag, TOL)
	match_id = int(rdata[0].get("match_id", 0))
	var m: Dictionary = lobby.matches.get(match_id, {})
	check("mapvote: match registered with host map",
			match_id > 0 and not m.is_empty() and str(m.map) == "crossdocks",
			"mid=%d map=%s" % [match_id, str(m.get("map", ""))])
	if match_id == 0:
		_finish()
		return

	# 2: a bad map id is ignored (validated against MapRegistry.ids()).
	voter_a.map_vote(match_id, "moonbase")
	await _wait_flag([false], 0.4)
	check("mapvote: bad map id ignored",
			int(lobby.matches[match_id].map_votes.get("moonbase", 0)) == 0,
			"%s" % str(lobby.matches[match_id].map_votes))

	# 3: a valid map vote tallies and acks with the running tally.
	voter_a.map_vote(match_id, "foundry")
	var r3 := await _wait_mapvote(voter_a)
	check("mapvote: valid vote tallies + acks",
			int(lobby.matches[match_id].map_votes.get("foundry", 0)) == 1
			and int(r3.get("tally", {}).get("foundry", -1)) == 1
			and bool(r3.get("decided", true)) == false
			and str(r3.get("leading", "")) == "foundry",
			"%s" % str(r3))
	voter_a.map_vote(match_id, "foundry")  # 4: re-tap is idempotent
	await _wait_flag([false], 0.4)
	check("mapvote: re-tap never inflates the tally",
			int(lobby.matches[match_id].map_votes.get("foundry", 0)) == 1,
			"%s" % str(lobby.matches[match_id].map_votes))

	# 5: mode and map are independent tallies for the same peer.
	var ghost := [0]
	voter_a.vote_result.connect(func(_i: Dictionary) -> void:
		ghost[0] += 1
	)
	voter_a.vote(match_id, "capture")
	await _wait_flag([false], 0.4)
	check("mapvote: mode and map tallies are independent",
			int(lobby.matches[match_id].votes.get("capture", 0)) == 1
			and int(lobby.matches[match_id].map_votes.get("foundry", 0)) == 1,
			"mode=%s map=%s" % [str(lobby.matches[match_id].votes), str(lobby.matches[match_id].map_votes)])
	voter_a.map_vote(match_id, "crossdocks")  # 6a: D27 - the current map is a repeat
	await _wait_flag([false], 0.4)
	check("mapvote D27: the current map cannot be re-voted (anti-repeat)",
			int(lobby.matches[match_id].map_votes.get("crossdocks", 0)) == 0
			and int(lobby.matches[match_id].map_votes.get("foundry", 0)) == 1,
			"%s" % str(lobby.matches[match_id].map_votes))
	voter_a.map_vote(match_id, "sawmill")  # 6: switch map vote
	var r6 := await _wait_mapvote(voter_a)
	check("mapvote: switching votes moves the count",
			int(lobby.matches[match_id].map_votes.get("sawmill", 0)) == 1
			and int(lobby.matches[match_id].map_votes.get("foundry", 0)) == 0
			and str(r6.get("leading", "")) == "sawmill",
			"%s" % str(r6))
	voter_b.map_vote(match_id, "foundry")  # 7: 1-1 split -> no decision
	var r7 := await _wait_mapvote(voter_b)
	check("mapvote: split votes hold (no decision)",
			bool(r7.get("decided", true)) == false and bool(lobby.matches[match_id].map_decided) == false,
			"%s" % str(r7))

	# 8: strict majority decides - directory flips, the MODE domain is
	# untouched (the single capture vote never decided), setmap reaches
	# the server.
	voter_a.map_vote(match_id, "foundry")
	var r8 := await _wait_mapvote(voter_a)
	await _wait_flag(sflag, TOL)
	check("mapvote: strict majority decides + setmap forwarded",
			bool(r8.get("decided", false)) == true and str(lobby.matches[match_id].map) == "foundry"
			and sflag[0] and str(sdata[0].get("map", "")) == "foundry"
			and str(lobby.matches[match_id].mode) == "tdm"
			and bool(lobby.matches[match_id].decided) == false,
			"decided=%s dir=%s setmap=%s" % [str(r8.get("decided")), str(lobby.matches[match_id].map), str(sdata[0])])
	check("mapvote: server stored the pending map",
			net._pending_map == "foundry", net._pending_map)

	# 9: the next in-place reset applies the voted map: arena rebuilt,
	# spawn points move, pending slot cleared.
	var sp_before: Vector3 = world.spawn_points.get(0, [Vector3.ZERO])[0]
	var old_arena: Node = arena
	net.reset_match()
	var pm: String = net.take_pending_map()
	if pm != "" and pm != net.map_id:
		old_arena.free()
		var md: Map = MapRegistry.get_map(pm)
		arena = Arena.build(world, md)
		add_child(arena)
		net.map_id = pm
	var sp_after: Vector3 = world.spawn_points.get(0, [Vector3.ONE])[0]
	check("mapvote: reset applies the voted map (arena rebuilt)",
			pm == "foundry" and net.map_id == "foundry" and net._pending_map == ""
			and not is_instance_valid(old_arena) and is_instance_valid(arena)
			and sp_before != sp_after,
			"pm=%s sp_before=%s sp_after=%s" % [pm, str(sp_before), str(sp_after)])

	# 10: a queueing client's assign carries the map vote state.
	var d = await _client()
	var aflag := [false]
	var adata := [{}]
	d.assign.connect(func(i: Dictionary) -> void:
		aflag[0] = true
		adata[0] = i
	)
	d.join_queue("latam_saopaulo", 1, 0, "P9")
	await _wait_flag(aflag, TOL)
	check("mapvote: assign carries map + map vote state",
			aflag[0] and str(adata[0].get("map", "")) == "foundry"
			and bool(adata[0].get("map_decided", false)) == true
			and str(adata[0].get("map_leading", "")) == "foundry"
			and int(adata[0].get("map_tally", {}).get("foundry", 0)) == 2,
			"%s" % str(adata[0]))

	# 11: the state heartbeat keeps the directory map fresh.
	srv_lob.send_state(3, true, "capture", "foundry")
	await _wait_flag([false], 0.4)
	check("mapvote: state heartbeat updates the directory map",
			str(lobby.matches[match_id].map) == "foundry",
			str(lobby.matches[match_id].map))
	# 12: D27 anti-repetition continues after the decision: foundry is now
	#     the entry map (just played / about to play) and is excluded.
	voter_b.map_vote(match_id, "foundry")
	await _wait_flag([false], 0.4)
	check("mapvote D27: voting for the just-played map is rejected after a decision",
			int(lobby.matches[match_id].map_votes.get("foundry", 0)) == 2,
			"%s" % str(lobby.matches[match_id].map_votes))
	# 13: D27 rotation: the previously played map (crossdocks) becomes
	#     votable again; the ack carries the repeat marker.
	voter_b.map_vote(match_id, "crossdocks")
	var r13 := await _wait_mapvote(voter_b)
	check("mapvote D27: the older map becomes votable again (rotation)",
			int(lobby.matches[match_id].map_votes.get("crossdocks", 0)) == 1
			and int(lobby.matches[match_id].map_votes.get("foundry", 0)) == 1
			and str(r13.get("repeat", "")) == "foundry",
			"%s" % str(r13))
	# 14: D27: the repeat gate applies to weighted party votes too.
	voter_b.map_vote(match_id, "foundry", "p9", 3, true)
	await _wait_flag([false], 0.4)
	check("mapvote D27: a party leader's repeat vote is rejected too",
			int(lobby.matches[match_id].map_votes.get("foundry", 0)) == 1,
			"%s" % str(lobby.matches[match_id].map_votes))
	# 15: D27: the rotation_pool helper (exclude + single-map fallback).
	var pool: Array = MapRegistry.rotation_pool("crossdocks")
	var pool0: Array = MapRegistry.rotation_pool("")
	var solo: Array = MapRegistry.rotation_pool("solo", ["solo"])
	check("mapvote D27: rotation_pool excludes the map, falls back when solo",
			pool.size() == 3 and not pool.has("crossdocks")
			and pool0.size() == MapRegistry.ids().size() and solo == ["solo"],
			"%s" % str([pool, pool0, solo]))
	_finish()

func _finish() -> void:
	print("MAPVOTE SUITE: %d passed, %d failed" % [passed, failed])
	get_tree().quit(failed)
