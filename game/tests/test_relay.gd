extends Node
## Relay suite (Phase 5, round 29): NAT traversal v1 end-to-end on loopback.
## Two match servers register in one relay over outbound UDP and get virtual
## ports; two ENet clients connect to <relay_ip>:<vport> (as real NAT'd
## clients would) and play through the transparent datagram pump. Checks:
## distinct virtual ports, slot assign per match, 10 s snapshot pacing per
## client, and NO cross-talk (killing client A's connection freezes its
## stream while client B's keeps flowing).
const FIXED_DT := 1.0 / 60.0
const RELAY_PORT := 7801
const PID := 1

var relay: Relay
var sa: MatchServer
var sb: MatchServer
var ca: MatchClient
var cb: MatchClient
var rca: RelayClient
var rcb: RelayClient
var wa: World
var wb: World
var arena_a: Node
var arena_b: Node
var snaps_a := 0
var snaps_b := 0
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

func _make_match(port: int, world: World) -> MatchServer:
	var s := MatchServer.new()
	add_child(s)
	s.setup(world, port, 3)
	var roster: Array = HeroRegistry.HEROES.duplicate()
	roster.shuffle()
	var rix := 0
	for team in 2:
		var pts: Array = world.spawn_points.get(team, [])
		for i in 3:
			if pts.size() <= i:
				break
			s.spawn_bot(team, roster[rix % roster.size()], pts[i])
			rix += 1
	return s

func _make_world() -> World:
	var w := World.new()
	w.name = "World"
	w.target_score = 999
	w.match_duration = 300.0
	add_child(w)
	var ar := Arena.build(w)
	add_child(ar)
	return w

func _count(c: MatchClient, dst: String) -> void:
	c.mp.peer_packet.connect(func(_id: int, data: PackedByteArray) -> void:
		if data.size() > 0 and data[0] == NetProtocol.M_SNAPSHOT:
			if dst == "a":
				snaps_a += 1
			elif dst == "b":
				snaps_b += 1)

func _wait_vport(rc: RelayClient, ms: int) -> bool:
	if rc.vport > 0:
		return true
	var t0 := Time.get_ticks_msec()
	while rc.vport <= 0 and Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame
	return rc.vport > 0

func _ready() -> void:
	randomize()
	relay = Relay.new()
	add_child(relay)
	relay.setup(RELAY_PORT)
	wa = _make_world()
	wb = _make_world()
	sa = _make_match(7777, wa)
	sb = _make_match(7778, wb)
	rca = RelayClient.new()
	add_child(rca)
	rca.setup("127.0.0.1", RELAY_PORT, 7777)
	rcb = RelayClient.new()
	add_child(rcb)
	rcb.setup("127.0.0.1", RELAY_PORT, 7778)
	await _wait_vport(rca, 5000)
	await _wait_vport(rcb, 5000)
	check("relay: both servers registered, distinct virtual ports",
			rca.vport > 0 and rcb.vport > 0 and rca.vport != rcb.vport,
			"va=%d vb=%d" % [rca.vport, rcb.vport])
	if fails > 0:
		_done()
		return
	ca = MatchClient.new()
	add_child(ca)
	ca.setup("127.0.0.1:%d" % rca.vport, HeroRegistry.default_hero())
	_count(ca, "a")
	cb = MatchClient.new()
	add_child(cb)
	cb.setup("127.0.0.1:%d" % rcb.vport, HeroRegistry.default_hero())
	_count(cb, "b")
	await _frames(120)  # 2 s: ENet handshake + hello + slot, through the relay
	check("relay: client A got a slot in match A (via relay)",
			ca.my_id >= 0 and sa.slots.size() == 1,
			"ca.my_id=%d sa.slots=%d" % [ca.my_id, sa.slots.size()])
	check("relay: client B got a slot in match B (via relay)",
			cb.my_id >= 0 and sb.slots.size() == 1,
			"cb.my_id=%d sb.slots=%d" % [cb.my_id, sb.slots.size()])
	if fails > 0:
		_done()
		return
	# 10 s of snapshot pacing through the relay (both matches in parallel).
	await _frames(600)
	check("relay: 10 s snapshot pacing, client A (~20 Hz)", snaps_a > 150,
			"snaps_a=%d" % snaps_a)
	check("relay: 10 s snapshot pacing, client B (~20 Hz)", snaps_b > 150,
			"snaps_b=%d" % snaps_b)
	# Cross-talk: kill client A's ENet peer (reconnect disabled so the stream
	# truly stops); A's stream must freeze while B keeps receiving from the
	# other match - the vport separation keeps the two relayed matches apart.
	var a_base := snaps_a
	var b_base := snaps_b
	ca._reconnects = 99  # exceed MAX_RECONNECTS: no auto-retry
	ca.mp.multiplayer_peer.close()
	await _frames(180)  # 3 s
	check("relay: no cross-talk (A frozen, B flowing)",
			snaps_a == a_base and snaps_b > b_base + 20,
			"a=%d (base %d) b=%d (base %d)" % [snaps_a, a_base, snaps_b, b_base])
	# Bonus (D15 evidence): with reconnect ENABLED, a dropped client re-joins
	# its own match through the relay (new ENet id, token reattach).
	var b2_base := snaps_b
	cb.mp.multiplayer_peer.close()  # cb's _reconnects is 0 -> auto-retry
	await _frames(120)  # 2 s: one 0.5 s retry cycle + re-hello
	check("relay: dropped client re-joins its match via relay",
			sb.slots.size() == 1 and snaps_b > b2_base,
			"sb.slots=%d snaps_b=%d (base %d)" % [sb.slots.size(), snaps_b, b2_base])
	_done()

func _done() -> void:
	print("RELAY SUITE: %d passed, %d failed" % [passes, fails])
	get_tree().quit(fails)

func _physics_process(_delta: float) -> void:
	if wa != null:
		wa.step(FIXED_DT)
	if wb != null:
		wb.step(FIXED_DT)
	if sa != null:
		sa.tick(FIXED_DT)
	if sb != null:
		sb.tick(FIXED_DT)
