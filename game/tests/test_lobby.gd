extends Node
## Headless lobby / matchmaking suite (Phase 5 v1): real UDP on 127.0.0.1,
## fast stage timing (strict 1 s / skill 2 s / fill 4 s) to exercise the
## 4-stage queue without long real-time waits. 10 checks.
const PORT := 7795
const TOL := 5.0

var lobby: LobbyServer
var passed := 0
var failed := 0

func _ready() -> void:
	lobby = LobbyServer.new()
	lobby.set_process(false)
	add_child(lobby)
	lobby.setup(PORT, "latam_saopaulo", 4.0)
	lobby.strict_until = 1.0
	lobby.skill_until = 2.0
	lobby.reap_after = 1.5  # fast reap for check 10 (clients ping 1/s)
	_run()

func _physics_process(_d: float) -> void:
	lobby.tick(1.0 / 60.0)
	for c in get_children():
		if c is LobbyClient:
			c.pump(1.0 / 60.0)

func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		passed += 1
		print("  ok  " + name)
	else:
		failed += 1
		printerr("  FAIL " + name + ("  [" + detail + "]" if detail != "" else ""))

## Blocks (real time, via physics frames) until flag[0] or timeout.
func _wait_flag(flag: Array, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout_s * 1000):
		if flag[0]:
			return true
		await get_tree().physics_frame
	return false

func _client() -> LobbyClient:
	var c := LobbyClient.new()
	c.set_process(false)
	add_child(c)
	c.setup("127.0.0.1", PORT)
	await get_tree().physics_frame
	return c

func _wait_hello(c: LobbyClient) -> Dictionary:
	var flag := [false]
	var data := [{}]
	c.hello.connect(func(i: Dictionary) -> void:
		flag[0] = true
		data[0] = i
	)
	await _wait_flag(flag, TOL)
	return data[0]

func _wait_assign(c: LobbyClient) -> Dictionary:
	var flag := [false]
	var data := [{}]
	c.assign.connect(func(i: Dictionary) -> void:
		flag[0] = true
		data[0] = i
	)
	await _wait_flag(flag, TOL)
	return data[0]

func _wait_regack(c: LobbyClient) -> Dictionary:
	var flag := [false]
	var data := [{}]
	c.regack.connect(func(i: Dictionary) -> void:
		flag[0] = true
		data[0] = i
	)
	await _wait_flag(flag, TOL)
	return data[0]

func _wait_pong(c: LobbyClient) -> float:
	var flag := [false]
	var data := [-1.0]
	c.pong.connect(func(r: float) -> void:
		flag[0] = true
		data[0] = r
	)
	await _wait_flag(flag, TOL)
	return data[0]

func _wait_queue(c: LobbyClient) -> Dictionary:
	var flag := [false]
	var data := [{}]
	c.queue.connect(func(i: Dictionary) -> void:
		flag[0] = true
		data[0] = i
	)
	await _wait_flag(flag, TOL)
	return data[0]

func _sleep(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(s * 1000):
		await get_tree().physics_frame

func _run() -> void:
	print("SUITE: test_lobby")
	var c1 := await _client()
	var hello := await _wait_hello(c1)
	check("1 hello on connect (region + counts)",
			hello.get("region") == "latam_saopaulo" and int(hello.get("matches", -1)) == 0
			and int(hello.get("waiters", -1)) == 0, str(hello))
	c1.ping()
	var rtt := await _wait_pong(c1)
	check("2 ping/pong RTT measured", rtt >= 0.0, "rtt=%s" % rtt)
	var m1 := await _client()
	m1.register_match("127.0.0.1", 7777, "latam_bogota", 3, "BOG", "capture")
	var regack := await _wait_regack(m1)
	check("3 match reg -> regack", int(regack.get("match_id", 0)) >= 1, str(regack))
	await _sleep(0.2)
	var w1 := await _client()
	await _wait_hello(w1)
	w1.join_queue("latam_bogota", 1, 0, "W1")
	var a1 := await _wait_assign(w1)
	check("4 strict same-region assign (stage 1, mode forwarded)",
			float(a1.get("stage", -1)) == 1.0 and str(a1.get("host")) == "127.0.0.1"
			and int(a1.get("port", 0)) == 7777 and str(a1.get("mode", "")) == "capture",
			str(a1))
	var m2 := await _client()
	m2.register_match("127.0.0.1", 7778, "europe", 3, "BER")
	await _wait_regack(m2)
	await _sleep(0.2)
	var w2 := await _client()
	await _wait_hello(w2)
	w2.join_queue("asia", 1, 0, "W2")
	var a2 := await _wait_assign(w2)
	check("5 widen: asia waiter -> LATAM match before europe (stage 3)",
			float(a2.get("stage", -1)) == 3.0 and int(a2.get("port", 0)) == 7777
			and float(a2.get("waited", 0.0)) >= 1.9, str(a2))
	m1.send_state(3, false)
	await _sleep(0.2)
	var w3 := await _client()
	await _wait_hello(w3)
	w3.join_queue("latam_bogota", 1, 0, "W3")
	var a3 := await _wait_assign(w3)
	check("6 full match skipped -> europe match via widen",
			int(a3.get("port", 0)) == 7778, str(a3))
	m2.send_state(3, false)
	await _sleep(0.2)
	var w4 := await _client()
	await _wait_hello(w4)
	w4.join_queue("latam_mexico", 1, 0, "W4")
	await _sleep(4.5)   # crosses strict/skill/region windows, all matches full
	m1.send_state(0, false)   # room reopens at t >= fill_after -> stage 4
	var a4 := await _wait_assign(w4)
	check("7 botfill: assign once room reopens at/after fill",
			float(a4.get("stage", -1)) == 4.0 and int(a4.get("port", 0)) == 7777, str(a4))
	m1.send_state(3, true)
	m2.send_state(2, true)
	await _sleep(0.2)
	var w5 := await _client()
	await _wait_hello(w5)
	w5.join_queue("europe", 1, 0, "W5")
	var q5 := await _wait_queue(w5)
	check("8 over matches excluded (queue, open=0)",
			int(q5.get("open", -1)) == 0, str(q5))
	var a5 := await _wait_assign(w5)
	check("8b still no assignment with only over matches", a5.size() == 0, str(a5))
	var m3 := await _client()
	m3.register_match("127.0.0.1", 7779, "europe", 3, "PAR")
	await _wait_regack(m3)
	m3.send_state(2, false)
	await _sleep(0.2)
	var w6 := await _client()
	await _wait_hello(w6)
	w6.join_queue("europe", 2, 0, "W6")
	await _sleep(2.5)
	var a6 := await _wait_assign(w6)
	check("9 party=2 not fitted into room=1", a6.size() == 0, str(a6))
	var w7 := await _client()
	await _wait_hello(w7)
	w7.join_queue("europe", 1, 0, "W7")
	var a7 := await _wait_assign(w7)
	check("9b party=1 fits room=1", int(a7.get("port", 0)) == 7779, str(a7))
	var w8 := await _client()
	await _wait_hello(w8)
	w8.join_queue("asia", 1, 0, "W8")
	await _sleep(0.3)
	var before: int = lobby.waiters.size()
	w8.exit_tree_cleanup()
	await _sleep(2.2)   # > reap_after (1.5)
	check("10 dropped waiter reaped", before >= 1 and lobby.waiters.size() == before - 1,
			"before=%d after=%d" % [before, lobby.waiters.size()])
	print("SUITE: %d passed, %d failed" % [passed, failed])
	if failed > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)
