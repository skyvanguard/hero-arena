extends Node
## Results + progression suite (Phase 6, round 33, D19): 14 checks -
## server-side stat accumulation (damage/kills/deaths), World.stats_rows
## ordering, MVP selection, the M_STATS wire (roundtrip + end-to-end over
## the real ENet loopback: a human kills to the target and the client
## receives the final table), ProgressionConfig level curve, PlayerProfile
## XP rules / multi-level-up / persistence, and the hero-select level badge.
const FIXED_DT := 1.0 / 60.0
const PORT := 7996

var world: World
var client: MatchClient
var _w2: World = null
var _srv: MatchServer = null
var passes := 0
var fails := 0
var _human: CharacterEntity = null

func _physics_process(_delta: float) -> void:
	# Explicit driving, exactly like net/server.tscn and test_net: the server
	# polls ENet inside tick() and the world steps at a fixed dt (the test
	# scene owns the loop, not the World/MatchServer nodes).
	if _w2 != null:
		_w2.step(FIXED_DT)
	if _srv != null:
		_srv.tick(FIXED_DT)

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

func _char(world_: World, team: int, pos: Vector3) -> CharacterEntity:
	var c := HeroFactory.create(team, false, Color(0.5, 0.5, 1.0),
			HeroRegistry.default_hero())
	c.position = pos
	add_child(c)
	world_.register_character(c)
	return c

func _ready() -> void:
	randomize()
	world = World.new()
	world.name = "World"
	add_child(world)
	add_child(Arena.build(world))

	# 1-3: stat accumulation on the authoritative world.
	var a := _char(world, 0, Vector3(-5.0, 0.9, 0.0))
	var b := _char(world, 1, Vector3(-5.0, 0.9, 3.0))
	world.damage(b, 25.0, a, false, b.global_position)
	check("stats: damage_dealt tracks the final applied amount",
			a.damage_dealt == 25.0, "%.1f" % a.damage_dealt)
	world.kill(b, a, false)
	check("stats: kill credits the killer and the victim",
			a.kills == 1 and b.deaths == 1,
			"kills=%d deaths=%d" % [a.kills, b.deaths])
	var c := _char(world, 1, Vector3(5.0, 0.9, 0.0))
	world.kill(c, null, false)
	check("stats: a source-less kill counts the death only",
			c.deaths == 1 and a.kills == 1, "kills=%d" % a.kills)

	# 4: stats_rows order = world.characters order (snapshot convention).
	var rows: Array = world.stats_rows()
	check("stats: rows follow the character list order",
			rows.size() == world.characters.size()
			and int(rows[0][0]) == 0 and int(rows[0][1]) == 1
			and int(rows[1][2]) == 1,
			"%s" % str(rows))

	# 5-6: MVP selection (most kills, tie-break damage, -1 when no kills).
	check("mvp: most kills wins",
			World.mvp_index([[0, 2, 1, 100.0], [1, 3, 0, 50.0], [0, 3, 1, 20.0]]) == 1,
			"")
	check("mvp: tie breaks on damage",
			World.mvp_index([[0, 1, 0, 100.0], [1, 1, 0, 200.0]]) == 1, "")
	check("mvp: no kills -> -1",
			World.mvp_index([[0, 0, 2, 300.0], [1, 0, 1, 400.0]]) == -1, "")

	# 7: M_STATS wire roundtrip (damage > 255 exercises the u16 lane).
	var wire: Array = NetProtocol.unpack_stats(NetProtocol.pack_stats(
			[[0, 3, 1, 300], [1, 0, 2, 60000]]))
	check("wire: M_STATS pack/unpack roundtrip",
			wire.size() == 2 and int(wire[0][1]) == 3 and int(wire[1][3]) == 60000,
			"%s" % str(wire))

	await _progression()
	await _e2e()
	await _badge()
	print("RESULTS SUITE: %d passed, %d failed" % [passes, fails])
	get_tree().quit(fails)

func _progression() -> void:
	var sp := ProjectSettings.globalize_path("user://profile.save")
	if FileAccess.file_exists(sp):
		DirAccess.remove_absolute(sp)
	var cfg = load("res://content/progression.tres")
	check("progression: config resource loads from content/",
			cfg is ProgressionConfig, "%s" % str(cfg))
	var curve_ok := true
	for l in range(2, 6):
		if cfg.xp_for_level(l) <= cfg.xp_for_level(l - 1):
			curve_ok = false
	check("progression: level curve is strictly increasing", curve_ok, "")
	var prof := PlayerProfile.load(cfg)
	var r1 := prof.apply_match(cfg, "kestrel", true, 3, true)
	# 120 (win) + 3*25 (kills) + 60 (mvp) = 255 -> L1 (100) + L2 (125) = 225,
	# so level 3 with 30 leftover.
	check("progression: win+kills+mvp XP and multi-level-up",
			float(r1.xp_gained) == 255.0 and int(r1.level_after) == 3
			and is_equal_approx(prof.xp, 30.0),
			"xp=%.0f lv=%d rem=%.0f" % [r1.xp_gained, r1.level_after, prof.xp])
	var r2 := prof.apply_match(cfg, "kestrel", false, 0, false)
	check("progression: losing match pays participation XP",
			float(r2.xp_gained) == 40.0 and prof.matches == 2 and prof.wins == 1
			and int(prof.per_hero["kestrel"]["kills"]) == 3,
			"m=%d w=%d xp=%.0f" % [prof.matches, prof.wins, prof.xp])
	var prof2 := PlayerProfile.load(cfg)
	check("progression: save/load roundtrip",
			prof2.level == prof.level and is_equal_approx(prof2.xp, prof.xp)
			and prof2.matches == 2 and prof2.wins == 1
			and int(prof2.per_hero["kestrel"]["plays"]) == 2,
			"lv=%d xp=%.0f" % [prof2.level, prof2.xp])

func _e2e() -> void:
	_w2 = World.new()
	_w2.name = "World2"
	_w2.target_score = 2
	_w2.match_duration = 300.0
	add_child(_w2)
	add_child(Arena.build(_w2))
	_srv = MatchServer.new()
	add_child(_srv)
	_srv.setup(_w2, PORT, 2)
	var roster: Array = HeroRegistry.HEROES.duplicate()
	roster.shuffle()
	for team in 2:
		var pts: Array = _w2.spawn_points.get(team, [])
		for i in 2:
			if pts.size() <= i:
				break
			_srv.spawn_bot(team, roster[(team * 2 + i) % roster.size()], pts[i])
	await _frames(10)
	client = MatchClient.new()
	add_child(client)
	client.setup("127.0.0.1:%d" % PORT, HeroRegistry.default_hero())
	await _frames(120)
	if client.my_id < 0:
		fails += 1
		print("FAIL e2e: client got no slot, aborting")
		return
	_human = null
	for ch in _w2.characters:
		var s: Dictionary = _srv.slots.values()[0]
		if ch == s.ch:
			_human = ch
			break
	check("e2e: human slotted, bot-filled teams",
			_human != null and _w2.characters.size() == 4,
			"my_id=%d chars=%d" % [client.my_id, _w2.characters.size()])
	if _human == null:
		return
	# Kill two enemies directly: TDM target 2 -> match_over.
	var foes: Array = []
	for ch in _w2.characters:
		if ch != _human and ch.team != _human.team:
			foes.append(ch)
	for f in foes:
		_w2.kill(f, _human, false)
		await _frames(5)
	await _frames(60)
	var my_idx: int = _w2.characters.find(_human)
	# The match character id is monotonic (bot fill took 0..3, the human got
	# id 4) and is NOT a row index - the client must map it through the
	# snapshot character order (round 36 regression: the net results screen
	# never applied XP / marked "(you)" because of this off-by-one).
	check("e2e: client maps my_id to the stats row index (snapshot order)",
			client.stats_index_of(client.my_id) == my_idx,
			"my_id=%d mapped=%d truth=%d" % [client.my_id,
			client.stats_index_of(client.my_id), my_idx])
	check("e2e: M_STATS arrived before match_over with the final table",
			client._stats_rows.size() == _w2.characters.size()
			and int(client._stats_rows[my_idx][1]) == 2
			and int(client._stats_rows[my_idx][0]) == int(_human.team),
			"%s" % str(client._stats_rows))
	check("e2e: the client finished the match (ended signal path)",
			client._ended, "ended=%s" % str(client._ended))

func _badge() -> void:
	var cfg = load("res://content/progression.tres")
	var prof := PlayerProfile.load(cfg)
	var hs := HeroSelect.new()
	hs.profile = prof
	hs.progression = cfg
	add_child(hs)  # _ready builds the UI with the profile already set
	await _frames(3)
	var found := false
	for c in hs.get_children():
		if c is Label and (c as Label).text.begins_with("LV "):
			found = true
			break
	check("ui: hero-select shows the progression badge", found, "")
	hs.queue_free()
