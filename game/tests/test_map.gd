extends Node
## Map framework suite (Phase 6, round 32, D18; map pool round 42): 17
## checks over the data-driven maps (registry, all four .tres layouts with
## integrity + bounds validation, legacy fallback, mode + bot integration
## on The Foundry and on the new maps) + the hero-select mode/map picker.
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
	# 1) Registry: all four maps resolve, unknown/empty -> default.
	var cd: Map = MapRegistry.get_map("crossdocks")
	var fo: Map = MapRegistry.get_map("foundry")
	var unk: Map = MapRegistry.get_map("nonexistent")
	check("registry: ids + all four maps + unknown->default",
			MapRegistry.ids().size() == 4
			and MapRegistry.ids().has("crossdocks") and MapRegistry.ids().has("foundry")
			and MapRegistry.ids().has("sawmill") and MapRegistry.ids().has("saltline")
			and cd != null and cd.map_id == "crossdocks"
			and fo != null and fo.map_id == "foundry"
			and unk == cd, str(MapRegistry.ids()))
	# 2b) Map pool integrity: every registered map is complete and in-bounds
	#      (spawns 3 per team on the central lane, every asset inside the
	#      play area, positive box sizes, ramps with lengths, >= 2 potions).
	var bad := ""
	var seen_sigs: Array = []
	for mid in MapRegistry.ids():
		var mp: Map = MapRegistry.get_map(str(mid))
		var half: float = mp.size / 2.0 - 0.5
		var probe: Array = mp.spawn_team0 + mp.spawn_team1 + mp.boxes + mp.crates + mp.ramps + mp.potions
		var sig := str(mp.size) + ":" + str(mp.boxes.size()) + ":" + str(mp.crates.size()) + ":" + str(mp.ramps.size())
		if mp.spawn_team0.size() != 3 or mp.spawn_team1.size() != 3 or mp.potions.size() < 2 \
				 or mp.boxes.size() != mp.box_sizes.size() or mp.ramps.size() != mp.ramp_lengths.size():
			bad += str(mid) + "(counts) "
			continue
		if absf(mp.spawn_team0[1].z) > 0.01 or absf(mp.spawn_team1[1].z) > 0.01:
			bad += str(mid) + "(lane) "
			continue
		for i in mp.boxes.size():
			if mp.box_sizes[i].x <= 0.0 or mp.box_sizes[i].y <= 0.0 or mp.box_sizes[i].z <= 0.0:
				bad += str(mid) + "(boxsize) "
				break
		for v in probe:
			var pv: Vector3 = v
			if absf(pv.x) > half or absf(pv.z) > half or pv.y < 0.0 or pv.y > 3.0:
				bad += str(mid) + "(oob:" + str(pv) + ") "
				break
		if seen_sigs.has(sig):
			bad += str(mid) + "(dup-layout) "
		seen_sigs.append(sig)
	check("pool: all four maps are complete, in-bounds, and distinct", bad == "", bad)
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
	# 8b) The new maps: sawmill spawns reach the world and the modes follow
	#     them (same D17 contract as the foundry checks above).
	world = await _new_world()
	var sm: Map = MapRegistry.get_map("sawmill")
	add_child(Arena.build(world, sm))
	check("sawmill: spawns applied, capture bases + escort lane follow",
			world.spawn_points[0][1] == Vector3(-17, 0.9, 0)
			and world.spawn_points[1][1] == Vector3(17, 0.9, 0),
			str(world.spawn_points))
	var cap2 := CaptureMode.new()
	world.mode = cap2
	cap2.setup(world)
	check("sawmill: capture bases = central spawns",
			world.flag_bases[0] == Vector3(-17, 0.9, 0)
			and world.flag_bases[1] == Vector3(17, 0.9, 0),
			str(world.flag_bases))
	world.reset()
	var esc2 := EscortMode.new()
	world.mode = esc2
	esc2.setup(world)
	check("sawmill: escort lane runs between the spawn x's",
			world.payload_start_x == -17.0 and world.payload_goal_x == 17.0,
			"start=%s goal=%s" % [world.payload_start_x, world.payload_goal_x])
	# 8c) Bots fight on Saltline (the 56 m open map), full bot stack.
	world = await _new_world()
	var sl: Map = MapRegistry.get_map("saltline")
	add_child(Arena.build(world, sl))
	var botsrv2 := MatchServer.new()
	add_child(botsrv2)
	botsrv2.setup(world, 7801, 3)
	var roster2: Array = HeroRegistry.HEROES.duplicate()
	roster2.shuffle()
	var rix2 := 0
	for team in 2:
		var pts2: Array = world.spawn_points.get(team, [])
		for i in 3:
			if pts2.size() <= i:
				break
			botsrv2.spawn_bot(team, roster2[rix2 % roster2.size()], pts2[i])
			rix2 += 1
	var okb2 := true
	for s in 8:
		var n2 := int(1.0 / FIXED_DT)
		for i in n2:
			world.step(FIXED_DT)
			botsrv2.tick(FIXED_DT)
		for c in world.characters:
			if absf(c.global_position.x) > 27.5 or absf(c.global_position.z) > 27.5:
				okb2 = false
	check("bots: 6 bots fight on saltline, within the 56 m bounds",
			okb2 and world.characters.size() == 6 and not world.match_over,
			"bounds=%s n=%d" % [okb2, world.characters.size()])
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
