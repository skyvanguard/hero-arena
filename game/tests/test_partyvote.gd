extends Node
## Per-party vote bundles suite (Phase 6, round 37, D23, lobby protocol
## v1.5): real UDP lobby with THREE registered match servers. The vote
## tally is now WEIGHTED: a party leader's vote carries the declared party
## size (clamped 1..6) and non-leader members are acked with
## party_vote=true without adding weight; decision is a strict weighted
## majority with total >= 2, so a committed party of >= 2 self-decides and
## all-solo lobbies behave exactly like v1. 14 checks: solo hold/majority
## (regression), member rejection, leader weight, party self-decision,
## 3v2 weighted majority, 3v3 weighted hold, re-vote moving weight,
## party-size clamping, solo+party mix, party-id collision, weighted
## assign, and solo (v1-shape) votes adding exactly weight 1. 17 checks total
## (the 3v3 weighted hold uses a fourth scratch match).
const LPORT := 7965
const GPORT_A := 7966
const GPORT_B := 7967
const GPORT_C := 7968
const TOL := 4.0

var lobby: LobbyServer
var _nets := {}  # game port -> {id, net}
var id_a := 0
var id_b := 0
var id_c := 0
var passed := 0
var failed := 0

func _ready() -> void:
	lobby = LobbyServer.new()
	lobby.set_process(false)
	add_child(lobby)
	lobby.setup(LPORT, "latam_saopaulo", 60.0)
	id_a = (await _register(GPORT_A)).id
	id_b = (await _register(GPORT_B)).id
	id_c = (await _register(GPORT_C)).id
	_run()

func _make_match(gport: int) -> MatchServer:
	var world := World.new()
	world.name = "World" + str(gport)
	world.target_score = 15
	add_child(world)
	add_child(Arena.build(world))
	var net := MatchServer.new()
	add_child(net)
	net.setup(world, gport, 3)
	return net

func _register(gport: int) -> Dictionary:
	var net := _make_match(gport)
	var lob := LobbyClient.new()
	lob.set_process(false)
	add_child(lob)
	lob.setup("127.0.0.1", LPORT)
	await get_tree().physics_frame
	var rflag := [false]
	var rdata := [{}]
	lob.regack.connect(func(i: Dictionary) -> void:
		rflag[0] = true
		rdata[0] = i
	)
	lob.setmode.connect(func(i: Dictionary) -> void:
		net.set_mode_from_lobby(str(i.get("mode", "")))
	)
	lob.setmap.connect(func(i: Dictionary) -> void:
		net.set_map_from_lobby(str(i.get("map", "")))
	)
	lob.register_match("127.0.0.1", gport, "latam_saopaulo", 3, "p" + str(gport))
	var t0 := Time.get_ticks_msec()
	while not rflag[0] and Time.get_ticks_msec() - t0 < int(TOL * 1000):
		await get_tree().physics_frame
	var r := {id = int(rdata[0].get("match_id", 0)), net = net}
	_nets[gport] = r
	return r

func _physics_process(_d: float) -> void:
	lobby.tick(1.0 / 60.0)
	for c in get_children():
		if c is LobbyClient:
			c.pump(1.0 / 60.0)
	for port in _nets:
		(_nets[port].net as MatchServer).tick(1.0 / 60.0)

func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		passed += 1
		print("  ok  " + name)
	else:
		failed += 1
		printerr("  FAIL " + name + ("  [" + detail + "]" if detail != "" else ""))

## JSON round-trips turn int tallies into floats - normalize for compare.
func _as_ints(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[str(k)] = int(d[k])
	return out

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
	var m1: Dictionary = lobby.matches.get(id_a, {})
	var m2: Dictionary = lobby.matches.get(id_b, {})
	var m3: Dictionary = lobby.matches.get(id_c, {})
	check("setup: three matches registered", id_a > 0 and id_b > 0 and id_c > 0
			and m1.has("votes") and m2.has("map_votes") and m3.has("votes"),
			"ids=%d/%d/%d" % [id_a, id_b, id_c])

	# 2-3: solo regression on match A's mode domain (v1 behavior: the tally
	# values are weights of 1 and a 2-1 strict majority decides).
	var a := await _client()
	var b := await _client()
	var c := await _client()
	a.vote(id_a, "capture")
	var r1 := await _wait_vote(a)
	b.vote(id_a, "tdm")
	var r2 := await _wait_vote(b)
	check("solo: 1-1 split holds (no decision, v1 rule)",
			not bool(r2.get("decided", false))
			and int(r2.tally.get("capture", 0)) == 1
			and int(r2.tally.get("tdm", 0)) == 1
			and str(r2.get("leading", "")) != "",
			"%s" % str(r2))
	c.vote(id_a, "capture")
	var r3 := await _wait_vote(c)
	check("solo: 2-1 strict majority decides (weighted == counts)",
			bool(r3.get("decided", false))
			and int(r3.tally.get("capture", 0)) == 2
			and str(r3.get("mode", "")) == "capture",
			"%s" % str(r3))
	var b2 := await _client()
	b2.vote(id_a, "tdm")
	var r4 := await _wait_vote(b2)
	check("sticky: a post-decision vote does not reopen the domain",
			bool(r4.get("decided", false))
			and str(lobby.matches[id_a].mode) == "capture"
			and str((_nets[GPORT_A].net)._pending_mode) == "capture",
			"mode=%s pending=%s" % [str(lobby.matches[id_a].mode),
			str((_nets[GPORT_A].net)._pending_mode)])

	# 4-6: party bundles on match A's map domain.
	var p1_member := await _client()
	var p1_leader := await _client()
	p1_member.map_vote(id_a, "foundry", "P1", 2, false)
	var rm := await _wait_mapvote(p1_member)
	check("party: a non-leader member is acked without adding weight",
			bool(rm.get("party_vote", false))
			and int(rm.tally.get("foundry", 0)) == 0,
			"%s" % str(rm))
	p1_leader.map_vote(id_a, "foundry", "P1", 2, true)
	var rl := await _wait_mapvote(p1_leader)
	check("party: the leader's vote carries the party size (2)",
			int(rl.tally.get("foundry", 0)) == 2
			and not bool(rl.get("party_vote", false)),
			"%s" % str(rl))
	check("party: a lone party of 2 adds weight 2 but cannot self-decide (1 entity)",
			int(rl.tally.get("foundry", 0)) == 2
			and not bool(rl.get("decided", false)),
			"%s" % str(rl))
	# The second entity arrives: a lone solo dissenter. The party's weight
	# (2) beats the solo (1) - 2-1 weighted, strict at total 3.
	var solo_a := await _client()
	solo_a.map_vote(id_a, "sawmill")  # D27: crossdocks is the entry map (repeat)
	var rs := await _wait_mapvote(solo_a)
	check("party: a party of 2 tips a 1-solo lobby 2-1 (setmap forwarded)",
			bool(rs.get("decided", false))
			and int(rs.tally.get("foundry", 0)) == 2
			and int(rs.tally.get("sawmill", 0)) == 1
			and str(lobby.matches[id_a].map) == "foundry"
			and str((_nets[GPORT_A].net)._pending_map) == "foundry",
			"%s" % str(rs))

	# 7: weighted 3-2 majority decides match B's mode domain.
	var p3 := await _client()
	var p2 := await _client()
	p3.vote(id_b, "capture", "P3", 3, true)
	var r7a := await _wait_vote(p3)
	p2.vote(id_b, "tdm", "P2", 2, true)
	var r7b := await _wait_vote(p2)
	check("party: weighted 3 vs 2 decides for the larger party",
			bool(r7b.get("decided", false))
			and int(r7b.tally.get("capture", 0)) == 3
			and int(r7b.tally.get("tdm", 0)) == 2
			and str((_nets[GPORT_B].net)._pending_mode) == "capture",
			"%s" % str(r7b))

	# 8-10: match B's map domain - weighted hold, re-vote moves the weight,
	# clamping + sticky decided.
	var p3b := await _client()
	p3b.map_vote(id_b, "sawmill", "P3", 3, true)  # D27: crossdocks is the entry map
	var r8a := await _wait_mapvote(p3b)
	p2.map_vote(id_b, "foundry", "P2", 2, true)
	var r8b := await _wait_mapvote(p2)
	check("party: weighted 3 vs 2 decides the map domain too (setmap forwarded)",
			bool(r8b.get("decided", false))
			and str(lobby.matches[id_b].map) == "sawmill"
			and str((_nets[GPORT_B].net)._pending_map) == "sawmill",
			"%s" % str(r8b))

	# 9: a leader re-vote moves the whole weight (match B map, now decided
	# for crossdocks - re-voting keeps decided sticky but moves the tally).
	p3b.map_vote(id_b, "foundry", "P3", 3, true)
	var r9 := await _wait_mapvote(p3b)
	check("party: a leader re-vote moves the full weight (3 sawmill -> foundry)",
			int(r9.tally.get("foundry", 0)) == 5
			and int(r9.tally.get("sawmill", 0)) == 0
			and bool(r9.get("decided", false)),
			"%s" % str(r9))

	# 10: party_size clamps to 6 and a post-decision vote updates the tally
	# without reopening the decision.
	var p9 := await _client()
	p9.map_vote(id_b, "crossdocks", "P9", 9, true)
	var r10 := await _wait_mapvote(p9)
	check("party: party_size clamps to 6; decided stays sticky",
			int(r10.tally.get("crossdocks", 0)) == 6
			and int(r10.tally.get("foundry", 0)) == 5
			and bool(r10.get("decided", false))
			and str(lobby.matches[id_b].map) == "sawmill",
			"%s" % str(r10))

	# 11: solo + party mix on match C's mode domain: one solo (1 entity)
	# cannot decide alone; the party of 2 is the second entity and its
	# weight (2) beats the solo (1) - 2-1 weighted decides.
	var d := await _client()
	var p5 := await _client()
	d.vote(id_c, "tdm")
	var r11a := await _wait_vote(d)
	check("party: a lone solo (1 entity) does not decide",
			not bool(r11a.get("decided", false))
			and int(r11a.tally.get("tdm", 0)) == 1,
			"%s" % str(r11a))
	p5.vote(id_c, "capture", "P5", 2, true)
	var r11b := await _wait_vote(p5)
	check("party: a party of 2 beats a lone solo 2-1 (weighted majority)",
			bool(r11b.get("decided", false))
			and int(r11b.tally.get("capture", 0)) == 2
			and int(r11b.tally.get("tdm", 0)) == 1
			and str(lobby.matches[id_c].mode) == "capture"
			and str((_nets[GPORT_C].net)._pending_mode) == "capture",
			"%s" % str(r11b))
	var f := await _client()
	f.vote(id_c, "tdm")
	var r11c := await _wait_vote(f)
	check("party: a post-decision solo updates the tally, decision stays",
			bool(r11c.get("decided", false))
			and int(r11c.tally.get("tdm", 0)) == 2
			and int(r11c.tally.get("capture", 0)) == 2
			and str(lobby.matches[id_c].mode) == "capture",
			"%s" % str(r11c))

	# 12: two leaders claiming the same party_id are both counted (trust-the-
	# leader model, same as the rest of the unauthenticated lobby) and the
	# 6-vs-0 weighted result decides; also the weighted HOLD case: a fresh
	# 3 vs 3 on... (match C mode is decided; use the ack math directly).
	var l1 := await _client()
	var l2 := await _client()
	l1.map_vote(id_c, "foundry", "PX", 2, true)
	var r12a := await _wait_mapvote(l1)
	l2.map_vote(id_c, "foundry", "PX", 2, true)
	var r12b := await _wait_mapvote(l2)
	check("party: two leaders of the same party_id are both counted (4 weight)",
			int(r12b.tally.get("foundry", 0)) == 4
			and bool(r12b.get("decided", false)),
			"%s" % str(r12b))
	# Weighted hold 3 vs 3: replay on a fresh domain via the lobby state -
	# match C's mode is decided, so verify the rule directly on a scratch
	# tally through a fresh match registration.
	var rd := await _register(7969)
	var id_d: int = rd.id
	var h3a := await _client()
	var h3b := await _client()
	h3a.vote(id_d, "capture", "H3A", 3, true)
	var r12c := await _wait_vote(h3a)
	h3b.vote(id_d, "tdm", "H3B", 3, true)
	var r12d := await _wait_vote(h3b)
	check("party: two equal parties of 3 tie 3-3 and hold (2 entities, no majority)",
			not bool(r12d.get("decided", false))
			and int(r12d.tally.get("capture", 0)) == 3
			and int(r12d.tally.get("tdm", 0)) == 3,
			"%s" % str(r12d))
	var h3c := await _client()
	h3c.vote(id_d, "capture")
	var r12e := await _wait_vote(h3c)
	check("party: a third solo tie-breaks the 3-3 hold 4-3 for capture",
			bool(r12e.get("decided", false))
			and int(r12e.tally.get("capture", 0)) == 4
			and int(r12e.tally.get("tdm", 0)) == 3
			and str((_nets[7969].net)._pending_mode) == "capture",
			"%s" % str(r12e))

	# 13: a queueing client's assign carries the WEIGHTED tallies + state of
	# the match it is placed in.
	var q := await _client()
	var qflag := [false]
	var qdata := [{}]
	q.assign.connect(func(i: Dictionary) -> void:
		qflag[0] = true
		qdata[0] = i
	)
	q.join_queue("latam_saopaulo", 1, 0, "q")
	var okq := await _wait_flag(qflag, TOL)
	if okq:
		var amid := int(qdata[0].get("match_id", 0))
		var am: Dictionary = lobby.matches.get(amid, {})
		check("assign: carries the weighted tallies and decision state",
				_as_ints(qdata[0].get("tally", {})) == _as_ints(am.votes)
				and _as_ints(qdata[0].get("map_tally", {})) == _as_ints(am.map_votes)
				and bool(qdata[0].get("decided", false)) == bool(am.decided)
				and bool(qdata[0].get("map_decided", false)) == bool(am.map_decided),
				"%s vs %s" % [str(qdata[0].get("tally")), str(am.votes)])
	else:
		check("assign: carries the weighted tallies and decision state", false,
				"no assign within %.0f s" % TOL)

	# 14: a v1-shape solo vote (no party keys) adds exactly weight 1.
	var s1 := await _client()
	s1.map_vote(id_d, "foundry")  # D27: crossdocks is entry D's map (repeat)
	var r14 := await _wait_mapvote(s1)
	check("compat: a v1-shape solo vote adds exactly weight 1",
			int(r14.tally.get("foundry", 0)) == 1
			and not bool(r14.get("party_vote", false)),
			"%s" % str(r14))

	print("PARTYVOTE SUITE: %d passed, %d failed" % [passed, failed])
	get_tree().quit(failed)
