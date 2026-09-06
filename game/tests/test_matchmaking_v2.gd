extends Node
## D28 matchmaking v2 suite (round 45): the SKILL stage is now a real
## win-probability gate (data-driven MMConfig: stage windows, fairness
## band, neutral bot rating, logistic win chance). Covers: config load +
## ordering, win_prob math, the even-split projection + fairness gate,
## grouping (a party projected as a block vs the other team + bots),
## live assignments (strict ignores skill; v1 skill-0 clients unchanged;
## win_prob on the assign), the REGION stage fair-preference, the BOTFILL
## ordering, the T_STATE ledger decay, and no stranding (an unfair far-
## region waiter is admitted in the region stage). 14 checks.
const PORT := 7801
const TOL := 5.0

var lobby: LobbyServer
var passed := 0
var failed := 0
var _mport := 5000

func _ready() -> void:
	lobby = LobbyServer.new()
	lobby.set_process(false)
	add_child(lobby)
	lobby.setup(PORT, "latam_saopaulo", 30.0)
	lobby.strict_until = 1.0
	lobby.skill_until = 3.0
	lobby.reap_after = 60.0
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

func _wait_assign(c: LobbyClient) -> Dictionary:
	var flag := [false]
	var data := [{}]
	c.assign.connect(func(i: Dictionary) -> void:
		flag[0] = true
		data[0] = i
	)
	await _wait_flag(flag, TOL)
	return data[0]

## Registers a match over real UDP (unique game port -> unique entry key)
## and returns its id. The registering client is kept alive: its pings
## keep the entry fresh against the reaper.
func _reg_match(team: int, region: String) -> int:
	_mport += 1
	var c := await _client()
	var flag := [false]
	var data := [{}]
	c.regack.connect(func(i: Dictionary) -> void:
		flag[0] = true
		data[0] = i
	)
	c.register_match("127.0.0.1", _mport, region, team, "mmv2 t" + str(_mport))
	await _wait_flag(flag, TOL)
	return int(data[0].get("match_id", 0))

## A fake waiter at a chosen queue age (drives _stage_of without real waits).
func _w(skill: int, age_s: float, region: String = "latam_saopaulo") -> Dictionary:
	return {region = region, party = 1, skill = skill, name = "T",
		joined_at = lobby.time - age_s, last_queue_sent = -1.0}

func _run() -> void:
	# 1: MMConfig loads from content with a sane stage ladder.
	var cfg := MMConfig.load_config()
	check("mm2: MMConfig loads from content (MMConfig instance)", cfg is MMConfig)
	check("mm2: stage windows strictly increasing, band positive",
			cfg.strict_until > 0.0 and cfg.skill_until > cfg.strict_until
			and cfg.region_until > cfg.skill_until and cfg.max_team_delta > 0.0
			and cfg.bot_skill > 0.0 and cfg.skill_k > 0.0,
			"%s/%s/%s delta=%s" % [cfg.strict_until, cfg.skill_until,
				cfg.region_until, cfg.max_team_delta])
	# 2: the win-probability model is a proper logistic on the avg delta.
	var p0: float = MMConfig.win_prob(cfg.skill_k, 0.0)
	var ppos: float = MMConfig.win_prob(cfg.skill_k, 100.0)
	var pneg: float = MMConfig.win_prob(cfg.skill_k, -100.0)
	check("mm2: win_prob 0.5 at parity, monotone, symmetric",
			absf(p0 - 0.5) < 0.0001 and ppos > 0.5 and pneg < 0.5
			and absf(ppos + pneg - 1.0) < 0.0001,
			"p0=%s p+=%s p-=%s" % [p0, ppos, pneg])
	check("mm2: win_prob saturates for large deltas",
			MMConfig.win_prob(cfg.skill_k, 1000.0) > 0.95
			and MMConfig.win_prob(cfg.skill_k, -1000.0) < 0.05)
	# 3: the even-split projection + fairness gate (team 6, 3 humans @1000:
	#    a party-1 join has delta = (party - 1000)/6, so 2700 -> 283 > band).
	check("mm2: parity join is fair, a 1700-point edge is not (band 250)",
			MMConfig.fair_join(cfg, 3000, 3, 1, 1000, 6)
			and not MMConfig.fair_join(cfg, 3000, 3, 1, 2700, 6))
	check("mm2: unknown skill = neutral (v1 behavior) both directions",
			MMConfig.fair_join(cfg, 0, 0, 1, 2700, 6)
			and MMConfig.fair_join(cfg, 3000, 3, 1, 0, 6))
	# 4: grouping - a 3-player party is projected as a BLOCK against the
	#    other team + neutral bots (3 humans @900, team 6): fair at 1200
	#    avg, rejected at 1800 avg.
	check("mm2: grouping - the party block is balanced, not stacked",
			MMConfig.fair_join(cfg, 2700, 3, 3, 3600, 6)
			and not MMConfig.fair_join(cfg, 2700, 3, 3, 5400, 6))
	# 5: live - a match with 3 humans @1000 (ledger seeded directly).
	var m1 := await _reg_match(6, "latam_saopaulo")
	lobby.matches[m1].humans = 3
	lobby.matches[m1].ledger_humans = 3
	lobby.matches[m1].skill_sum = 3000
	# 6: the STRICT stage ignores skill (v1 first-fill) but the assign
	#    carries the win-probability estimate (delta 150 -> well above 0.5).
	var c1 := await _client()
	c1.join_queue("latam_saopaulo", 1, 1900, "hi")
	var a1 := await _wait_assign(c1)
	check("mm2: strict joins any skill + assign carries win_prob",
			int(a1.get("stage", -1)) == LobbyProtocol.QUEUE_STAGE_STRICT
			and int(a1.get("match_id", -1)) == m1
			and float(a1.get("win_prob", -1.0)) > 0.55,
			"stage=%s wp=%s" % [a1.get("stage"), a1.get("win_prob")])
	# 7: the SKILL stage (forced age) excludes the 2700 join, admits 1000.
	var cands_hi: Array = lobby._candidates(_w(2700, 2.0))
	var cands_lo: Array = lobby._candidates(_w(1000, 2.0))
	check("mm2: skill stage - unfair join excluded, parity join admitted",
			cands_hi.size() == 0 and cands_lo.size() == 1
			and int(cands_lo[0].id) == m1,
			"hi=%d lo=%d" % [cands_hi.size(), cands_lo.size()])
	# 8: v1 compatibility - a skill-0 client joins with win_prob -1 (the
	#    lower-human match wins the (rank, humans) sort).
	var m2 := await _reg_match(6, "latam_saopaulo")
	lobby.matches[m2].humans = 4
	lobby.matches[m2].ledger_humans = 4
	lobby.matches[m2].skill_sum = 4000
	var c2 := await _client()
	c2.join_queue("latam_saopaulo", 1, 0, "v1")
	var a2 := await _wait_assign(c2)
	check("mm2: skill-0 (v1) client: joins, win_prob unknown (-1)",
			int(a2.get("match_id", -1)) == m1
			and float(a2.get("win_prob", 0.5)) < 0.0,
			"mid=%s wp=%s" % [a2.get("match_id"), a2.get("win_prob")])
	# 9: the REGION stage prefers FAIR matches inside the widen order: the
	#    unfair match (better region rank) sorts LAST.
	var mf := await _reg_match(6, "north_america")      # rank 3, fair for 1900
	var mu := await _reg_match(6, "latam_bogota")       # rank 1, unfair for 1900
	lobby.matches[mf].humans = 3
	lobby.matches[mf].ledger_humans = 3
	lobby.matches[mf].skill_sum = 3000
	lobby.matches[mu].humans = 3
	lobby.matches[mu].ledger_humans = 3
	lobby.matches[mu].skill_sum = 300
	var creg: Array = lobby._candidates(_w(1900, 10.0))
	check("mm2: region stage - fair matches before the better-rank unfair one",
			creg.size() == 4 and int(creg[0].id) == m1
			and int(creg[2].id) == mf and int(creg[3].id) == mu,
			"%s" % str(creg))
	# 10: the BOTFILL stage keeps the v1 emptiest-first ordering.
	var e1 := await _reg_match(6, "latam_saopaulo")
	var e2 := await _reg_match(6, "latam_saopaulo")
	lobby.matches[e1].humans = 1
	lobby.matches[e2].humans = 2
	var cbot: Array = lobby._candidates(_w(1000, 200.0))
	check("mm2: botfill stage - emptiest match first (v1 ordering)",
			cbot.size() >= 2 and int(cbot[0].id) == e1,
			"%s" % str(cbot))
	# 11: ledger decay - T_STATE reporting fewer humans scales the ledger.
	var m3 := await _reg_match(6, "latam_saopaulo")
	lobby.matches[m3].humans = 3
	lobby.matches[m3].ledger_humans = 3
	lobby.matches[m3].skill_sum = 3000
	lobby._dispatch(str(lobby.matches[m3].key),
			{t = LobbyProtocol.T_STATE, humans = 2, over = false})
	check("mm2: T_STATE decay - the ledger scales with the human count",
			int(lobby.matches[m3].ledger_humans) == 2
			and int(lobby.matches[m3].skill_sum) == 2000,
			"h=%s s=%s" % [lobby.matches[m3].ledger_humans, lobby.matches[m3].skill_sum])
	# 12: no stranding - a far-region waiter finds nothing in strict/skill
	#     (no local matches) and is admitted in the REGION stage (the
	#     emptiest fair match wins the sort).
	var c3 := await _client()
	c3.join_queue("europe", 1, 1900, "late")
	var a3 := await _wait_assign(c3)
	check("mm2: an unfair-skill far-region waiter is not stranded",
			int(a3.get("stage", -1)) == LobbyProtocol.QUEUE_STAGE_REGION
			and int(a3.get("match_id", -1)) == e1,
			"stage=%s mid=%s" % [a3.get("stage"), a3.get("match_id")])
	print("MATCHMAKING-V2 SUITE: %d passed, %d failed" % [passed, failed])
	get_tree().quit(failed)
