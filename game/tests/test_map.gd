extends Node
## Map framework suite (Phase 6, round 32, D18): 12 checks over the data-
## driven maps (registry, both .tres layouts, legacy fallback, mode + bot
## integration on the second map) + the hero-select mode/map picker logic.
const FIXED_DT := 1.0 / 60.0

var passes := 0
var fails := 0
var world: World
var chars: Array = []

func check(name: String, cond: bool, detail := "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		fails += 1
		print("FAIL ", name, ("  [" + detail + "]" if detail != "" else ""))

func frames(n: int):
	for i in n:
		await get_tree().physics_frame

func _new_world() -> World:
	if world != null:
		world.queue_free()
	for c in chars:
		c.queue_free()
	chars = []
	await frames(2)
	world = World.new()
	world.name = "World"
	world.target_score = 999
	world.match_duration = 300.0
	add_child(world)
	return world

func _ready() -> void:
	randomize()
	# 1) Registry: both maps resolve, unknown/empty -> default.
	var cd: Map = MapRegistry.get_map("crossdocks")
	var fo: Map = MapRegistry.get_map("foundry")
	var unk: Map = MapRegistry.get_map("nonexistent")
	check("registry: ids + both maps + unknown->default",
			MapRegistry.ids().has("crossdocks") and MapRegistry.ids().has("foundry")
			and cd != null and cd.map_id == "crossdocks"
			and fo != null and fo.map_id == "foundry"
			and unk == cd, str(MapRegistry.ids()))
	# 2) Crossdocks data = the legacy placeholder geometry (44 m, ±16 spawns).
	check("crossdocks: legacy layout data",
			cd.size == 44.0 and cd.spawn_team0.size() == 3
			and cd.spawn_team0[1] == Vector3(-16, 0.9, 0)
			and cd.spawn_team1[1] == Vector3(16, 0.9, 0)
			and cd.boxes.size() == 4 and cd.crates.size() == 8
			and cd.ramps.size() == 2 and cd.potions.size() == 4,
			"size=%s spawns=%s" % [cd.size, str(cd.spawn_team0)])
	# 3) Foundry: the second original map (52 m, ±18 spawns, center ring).
	check("foundry: second original layout",
			fo.size == 52.0 and fo.spawn_team0[1] == Vector3(-18, 0.9, 0)
			and fo.spawn_team1[1] == Vector3(18, 0.9, 0)
			and fo.boxes.size() == 8 and fo.crates.size() == 6
			and fo.boxes.size() != cd.boxes.size(),
			"size=%s boxes=%d" % [fo.size, fo.boxes.size()])
	# 4) Building from the map: spawns land on the world (D17 bases follow).
	world = await _new_world()
	add_child(Arena.build(world, fo))
	check("arena: foundry spawns applied to the world",
			world.spawn_points[0][1] == Vector3(-18, 0.9, 0)
			and world.spawn_points[1][1] == Vector3(18, 0.9, 0),
			str(world.spawn_points))
	# 5) Capture on foundry: bases = the central spawns of the NEW map.
	var capm := CaptureMode.new()
	world.mode = capm
	capm.setup(world)
	check("modes: capture bases follow the foundry spawns",
			world.flag_bases[0] == Vector3(-18, 0.9, 0)
			and world.flag_bases[1] == Vector3(18, 0.9, 0),
			str(world.flag_bases))
	# 6) Escort on foundry: the lane runs between the foundry spawn x's.
	world.reset()
	var escm := EscortMode.new()
	world.mode = escm
	escm.setup(world)
	check("modes: escort lane uses the foundry spawn x's",
			world.payload_start_x == -18.0 and world.payload_goal_x == 18.0
			and world.payload_pos == -18.0,
			"start=%s goal=%s" % [world.payload_start_x, world.payload_goal_x])
	# 7) Legacy fallback: a Map with empty arrays builds the classic layout.
	await _new_world()
	var empty := Map.new()
	add_child(Arena.build(world, empty))
	check("arena: empty map falls back to the legacy layout",
			world.spawn_points[0][1] == Vector3(-16, 0.9, 0)
			and world.spawn_points[1][1] == Vector3(16, 0.9, 0),
			str(world.spawn_points))
	# 8) Bots fight on foundry: 6 bots (the full MatchServer bot stack, same
	# pattern as test_mode_control), 8 s, nobody escapes the 52 m box.
	world = await _new_world()
	add_child(Arena.build(world, fo))
	var botsrv := MatchServer.new()
	add_child(botsrv)
	botsrv.setup(world, 7799, 3)
	var roster: Array = HeroRegistry.HEROES.duplicate()
	roster.shuffle()
	var rix := 0
	for team in 2:
		var pts: Array = world.spawn_points.get(team, [])
		for i in 3:
			if pts.size() <= i:
				break
			botsrv.spawn_bot(team, roster[rix % roster.size()], pts[i])
			rix += 1
	var ok_bounds := true
	for s in 8:
		var n := int(1.0 / FIXED_DT)
		for i in n:
			world.step(FIXED_DT)
			botsrv.tick(FIXED_DT)
		for c in world.characters:
			if absf(c.global_position.x) > 26.5 or absf(c.global_position.z) > 26.5:
				ok_bounds = false
	var ci := 0
	var moved := false
	for team in 2:
		var pts: Array = world.spawn_points.get(team, [])
		for i in 3:
			var c: CharacterEntity = world.characters[ci]
			if c.global_position.distance_to(pts[i]) > 1.0:
				moved = true
			ci += 1
	check("bots: 6 bots fight on foundry, within bounds, they moved",
			ok_bounds and moved and not world.match_over,
			"bounds=%s moved=%s over=%s" % [ok_bounds, moved, world.match_over])
	# 9) MatchConfig map selection drives the host path.
	var saved: String = MatchConfig.map_id
	MatchConfig.map_id = "foundry"
	var picked: Map = MapRegistry.get_map(MatchConfig.map_id)
	check("config: MatchConfig.map_id selects the host map",
			picked.map_id == "foundry", picked.map_id)
	MatchConfig.map_id = saved
	# 10) Hero-select picker logic (headless): the named handlers write
	#     MatchConfig; unknown ids are rejected.
	var hs := HeroSelect.new()
	add_child(hs)
	await frames(2)
	hs._pick_mode("capture")
	check("picker: mode pick writes MatchConfig.mode_id",
			MatchConfig.mode_id == "capture", MatchConfig.mode_id)
	hs._pick_map("foundry")
	check("picker: map pick writes MatchConfig.map_id",
			MatchConfig.map_id == "foundry", MatchConfig.map_id)
	hs._pick_mode("not_a_mode")
	hs._pick_map("not_a_map")
	check("picker: unknown ids are rejected",
			MatchConfig.mode_id == "capture" and MatchConfig.map_id == "foundry",
			"%s/%s" % [MatchConfig.mode_id, MatchConfig.map_id])
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = saved
	hs.queue_free()
	_done()

func _done() -> void:
	print("MAP SUITE: %d passed, %d failed" % [passes, fails])
	get_tree().quit(fails)
