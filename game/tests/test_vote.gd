extends Node
## Next-match mode voting suite (Phase 6, round 34, D20): real UDP lobby on
## 127.0.0.1 with a registered match server + two voters + a queueing
## observer. 12 checks: unknown-match and bad-mode votes are ignored, one
## vote per peer (last write wins, re-taps never inflate), split votes hold
## (no decision), strict majority decides (directory mode flips, setmode
## reaches the match server), the server applies the voted mode at the next
## in-place reset, and the queue assign carries the tally/leading/decided.
const LPORT := 7961
const GPORT := 7962
const TOL := 4.0

var lobby: LobbyServer
var srv_lob: LobbyClient
var voter_a: LobbyClient
var voter_b: LobbyClient
var world: World
var net: MatchServer
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
	add_child(Arena.build(world))
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

func _wait_vote(c: LobbyClient) -> Dictionary:
	var flag := [false]
	var data := [{}]
	c.vote_result.connect(func(i: Dictionary) -> void:
		flag[0] = true
		data[0] = i
	)
	await _wait_flag(flag, TOL)
	return data[0]

func _run() -> void:
	# 1: registration - the directory entry exists with the host's mode.
	var rflag := [false]
	var rdata := [{}]
	srv_lob.regack.connect(func(i: Dictionary) -> void:
		rflag[0] = true
		rdata[0] = i
	)
	# The server-side wiring server_main.gd uses: a decided vote arrives as
	# setmode and the MatchServer stores it for the next reset.
	srv_lob.setmode.connect(func(i: Dictionary) -> void:
		net.set_mode_from_lobby(str(i.get("mode", "")))
	)
	# Watch setmode from the start (it can arrive on the deciding vote, at
	# any time).
	var sflag := [false]
	var sdata := [{}]
	srv_lob.setmode.connect(func(i: Dictionary) -> void:
		sflag[0] = true
		sdata[0] = i
	)
	srv_lob.register_match("127.0.0.1", GPORT, "latam_saopaulo", 3, "vote test", "tdm")
	await _wait_flag(rflag, TOL)
	match_id = int(rdata[0].get("match_id", 0))
	var m: Dictionary = lobby.matches.get(match_id, {})
	check("vote: match registered with host mode",
			match_id > 0 and not m.is_empty() and str(m.mode) == "tdm",
			"mid=%d mode=%s" % [match_id, str(m.get("mode", ""))])
	if match_id == 0:
		_finish()
		return

	# 2: voting an unknown match gets no voteresult (the lobby replies err).
	var ghost := [0]
	voter_a.vote_result.connect(func(_i: Dictionary) -> void:
		ghost[0] += 1
	)
	voter_a.vote(999, "tdm")
	await _wait_flag([false], 0.4)
	check("vote: unknown match -> no voteresult", ghost[0] == 0, "n=%d" % ghost[0])

	# 3: bad mode id is ignored (validated against ModeRegistry.ids()).
	voter_a.vote(match_id, "rocketball")
	await _wait_flag([false], 0.4)
	check("vote: bad mode id ignored",
			int(lobby.matches[match_id].votes.get("rocketball", 0)) == 0,
			"%s" % str(lobby.matches[match_id].votes))

	# 4: a valid vote tallies and acks with the running tally.
	voter_a.vote(match_id, "capture")
	var r4 := await _wait_vote(voter_a)
	check("vote: valid vote tallies + acks",
			int(lobby.matches[match_id].votes.get("capture", 0)) == 1
			and int(r4.get("tally", {}).get("capture", -1)) == 1
			and bool(r4.get("decided", true)) == false
			and str(r4.get("leading", "")) == "capture",
			"%s" % str(r4))
	voter_a.vote(match_id, "capture")  # 5: re-tap the same mode
	await _wait_flag([false], 0.4)
	check("vote: re-tap never inflates the tally",
			int(lobby.matches[match_id].votes.get("capture", 0)) == 1,
			"%s" % str(lobby.matches[match_id].votes))
	voter_a.vote(match_id, "control")  # 6: switch vote (last write wins)
	var r6 := await _wait_vote(voter_a)
	check("vote: switching votes moves the count",
			int(lobby.matches[match_id].votes.get("control", 0)) == 1
			and int(lobby.matches[match_id].votes.get("capture", 0)) == 0
			and str(r6.get("leading", "")) == "control",
			"%s" % str(r6))
	voter_b.vote(match_id, "capture")  # 7: 1-1 split -> no decision
	var r7 := await _wait_vote(voter_b)
	check("vote: split votes hold (no decision)",
			bool(r7.get("decided", true)) == false and bool(lobby.matches[match_id].decided) == false,
			"%s" % str(r7))
	# 8: strict majority decides - directory flips, setmode reaches the server.
	voter_a.vote(match_id, "capture")
	var r8 := await _wait_vote(voter_a)
	await _wait_flag(sflag, TOL)
	check("vote: strict majority decides + setmode forwarded",
			bool(r8.get("decided", false)) == true and str(lobby.matches[match_id].mode) == "capture"
			and sflag[0] and str(sdata[0].get("mode", "")) == "capture",
			"decided=%s dir=%s setmode=%s" % [str(r8.get("decided")), str(lobby.matches[match_id].mode), str(sdata[0])])
	check("vote: server stored the pending mode",
			net._pending_mode == "capture", net._pending_mode)
	# 9: the next in-place reset applies the voted mode.
	net.reset_match()
	check("vote: reset_match applies the voted mode",
			world.mode != null and str(world.mode.mode_id) == "capture"
			and net._pending_mode == "",
			"mode=%s pending=%s" % [str(world.mode.mode_id if world.mode != null else "null"), net._pending_mode])
	# 10: a queueing client's assign carries the vote state.
	var d := await _client()
	var aflag := [false]
	var adata := [{}]
	d.assign.connect(func(i: Dictionary) -> void:
		aflag[0] = true
		adata[0] = i
	)
	d.join_queue("latam_saopaulo", 1, 0, "P9")
	await _wait_flag(aflag, TOL)
	check("vote: assign carries tally/leading/decided",
			aflag[0] and str(adata[0].get("mode", "")) == "capture"
			and bool(adata[0].get("decided", false)) == true
			and str(adata[0].get("leading", "")) == "capture"
			and int(adata[0].get("tally", {}).get("capture", 0)) == 2,
			"%s" % str(adata[0]))
	# 11: results-screen flow - the match is over, the directory mode
	# follows the server's state heartbeat, and over matches are votable
	# (the vote targets the next in-place match; decisions stay sticky).
	srv_lob.send_state(3, true, "capture")
	await _wait_flag([false], 0.4)
	check("vote: state heartbeat updates the directory mode",
			str(lobby.matches[match_id].mode) == "capture",
			str(lobby.matches[match_id].mode))
	voter_b.vote(match_id, "escort")
	var r11 := await _wait_vote(voter_b)
	check("vote: over matches accept votes (next-match cycle)",
			int(lobby.matches[match_id].votes.get("escort", 0)) == 1
			and bool(r11.get("decided", false)) == true,
			"%s" % str(r11))
	_finish()

func _finish() -> void:
	print("VOTE SUITE: %d passed, %d failed" % [passed, failed])
	get_tree().quit(failed)
