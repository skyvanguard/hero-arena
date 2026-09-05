class_name Arena
extends RefCounted
## Data-driven arena (Phase 6, D18): geometry comes from a Map Resource
## (content/maps/*.tres) — lanes, cover, verticality, potions, spawns are
## all @exports, so a new map is a data file, not a code change. Two maps
## ship: Crossdocks (44 m, the Phase 1 placeholder layout, renamed) and
## The Foundry (52 m, center core ring). Original geometry only.
## build(world) with no map uses the default map (regression-safe).

const SIZE := 44.0  # legacy fallback size (pre-D18 hardcoded layout)

static func build(world: World, map: Map = null) -> Node3D:
	if map == null:
		map = MapRegistry.get_map(MapRegistry.DEFAULT_ID)
	var size := map.size
	var root := Node3D.new()
	root.name = "Arena"

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.1, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.55
	env_node.environment = env
	root.add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	root.add_child(sun)

	_box(root, Vector3(0, -0.25, 0), Vector3(size, 0.5, size), _mat(Color(0.16, 0.18, 0.22)))
	# Team floor tints (readability).
	_box(root, Vector3(-size * 0.25, 0.01, 0), Vector3(size * 0.5 - 1.0, 0.02, size - 2.0), _mat(Color(0.2, 0.3, 0.42), 0.35), true)
	_box(root, Vector3(size * 0.25, 0.01, 0), Vector3(size * 0.5 - 1.0, 0.02, size - 2.0), _mat(Color(0.42, 0.24, 0.2), 0.35), true)

	_build_bounds(root, size)
	_build_cover(root, map)
	_build_potions(root, world, map)

	# Spawns from the map (y = capsule center height). The CENTRAL spawn
	# (index 1) doubles as the CTF base / escort lane endpoint (D17), so
	# maps keep it on the central lane.
	if map.spawn_team0.size() > 0 and map.spawn_team1.size() > 0:
		world.setup_spawn(0, map.spawn_team0)
		world.setup_spawn(1, map.spawn_team1)
	else:
		var sy := 0.9
		world.setup_spawn(0, [
			Vector3(-16, sy, -6), Vector3(-16, sy, 0), Vector3(-16, sy, 6),
		])
		world.setup_spawn(1, [
			Vector3(16, sy, -6), Vector3(16, sy, 0), Vector3(16, sy, 6),
		])
	return root

static func _build_bounds(root: Node3D, size: float) -> void:
	var h := 3.0
	var wall_mat := _mat(Color(0.3, 0.34, 0.4))
	_box(root, Vector3(0, h / 2.0, -size / 2.0), Vector3(size + 1.0, h, 0.5), wall_mat)
	_box(root, Vector3(0, h / 2.0, size / 2.0), Vector3(size + 1.0, h, 0.5), wall_mat)
	_box(root, Vector3(-size / 2.0, h / 2.0, 0), Vector3(0.5, h, size + 1.0), wall_mat)
	_box(root, Vector3(size / 2.0, h / 2.0, 0), Vector3(0.5, h, size + 1.0), wall_mat)

## Cover from the map data (boxes + crates + ramps). An empty section falls
## back to the legacy layout so a bare build(world) never renders nothing.
static func _build_cover(root: Node3D, map: Map) -> void:
	var cover_mat := _mat(Color(0.42, 0.45, 0.5))
	var crate_mat := _mat(Color(0.5, 0.4, 0.3))
	var boxes: Array = map.boxes
	var box_sizes: Array = map.box_sizes
	var crates: Array = map.crates
	var ramps: Array = map.ramps
	var ramp_lengths: Array = map.ramp_lengths
	if boxes.is_empty():
		# Legacy placeholder layout (Crossdocks pre-D18).
		boxes = [Vector3(0, 0.6, -3.0), Vector3(0, 0.6, 3.0),
			Vector3(-14, 1.5, 12), Vector3(14, 1.5, -12)]
		box_sizes = [Vector3(8.0, 1.2, 0.5), Vector3(8.0, 1.2, 0.5),
			Vector3(6.0, 0.3, 6.0), Vector3(6.0, 0.3, 6.0)]
		crates = [Vector3(-8, 0.5, -8), Vector3(8, 0.5, 8), Vector3(-8, 0.5, 8),
			Vector3(8, 0.5, -8), Vector3(0, 0.5, 10), Vector3(0, 0.5, -10),
			Vector3(-12, 0.5, 0), Vector3(12, 0.5, 0)]
		ramps = [Vector3(-14, 0.75, 7.5), Vector3(14, 0.75, -7.5)]
		ramp_lengths = [3.5, 3.5]
	for i in boxes.size():
		_box(root, boxes[i], box_sizes[i], cover_mat)
	for p in crates:
		_box(root, p, Vector3(1.0, 1.0, 1.0), crate_mat)
	for i in ramps.size():
		_ramp(root, ramps[i], float(ramp_lengths[i]) if i < ramp_lengths.size() else 3.5)

static func _build_potions(root: Node3D, world: World, map: Map) -> void:
	var spots: Array = map.potions
	if spots.is_empty():
		spots = [Vector3(-4, 0.4, 0), Vector3(4, 0.4, 0),
			Vector3(-14, 0.4, 12), Vector3(14, 0.4, -12)]
	for p in spots:
		var pk := HealthPickup.new()
		root.add_child(pk)
		pk.setup(world, p)

static func _ramp(root: Node3D, pos: Vector3, length: float) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	sb.rotation.x = -deg_to_rad(12.0)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.0, 0.25, length)
	bm.material = _mat(Color(0.36, 0.4, 0.46))
	mi.mesh = bm
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(3.0, 0.25, length)
	cs.shape = bs
	sb.add_child(cs)
	root.add_child(sb)

static func _mat(col: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	return m

static func _box(root: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D, visual_only := false) -> void:
	if visual_only:
		var mi := MeshInstance3D.new()
		mi.position = pos
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		mi.mesh = bm
		root.add_child(mi)
		return
	var sb := StaticBody3D.new()
	sb.position = pos
	sb.collision_layer = 1
	sb.collision_mask = 0
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	root.add_child(sb)
