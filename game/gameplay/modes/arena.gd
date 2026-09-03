class_name Arena
extends RefCounted
## Placeholder arena (Phase 1): compact 44x44 m — lanes, cover, verticality,
## health potions, team spawns. Phase 6 ships the two real maps; this one
## exists to validate scale/feel on device. Original geometry only.

const SIZE := 44.0

static func build(world: World) -> Node3D:
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

	_box(root, Vector3(0, -0.25, 0), Vector3(SIZE, 0.5, SIZE), _mat(Color(0.16, 0.18, 0.22)))
	# Team floor tints (readability).
	_box(root, Vector3(-SIZE * 0.25, 0.01, 0), Vector3(SIZE * 0.5 - 1.0, 0.02, SIZE - 2.0), _mat(Color(0.2, 0.3, 0.42), 0.35), true)
	_box(root, Vector3(SIZE * 0.25, 0.01, 0), Vector3(SIZE * 0.5 - 1.0, 0.02, SIZE - 2.0), _mat(Color(0.42, 0.24, 0.2), 0.35), true)

	_build_bounds(root)
	_build_cover(root)
	_build_potions(root, world)

	# Spawns (y = capsule center height).
	var sy := 0.9
	world.setup_spawn(0, [
		Vector3(-16, sy, -6), Vector3(-16, sy, 0), Vector3(-16, sy, 6),
	])
	world.setup_spawn(1, [
		Vector3(16, sy, -6), Vector3(16, sy, 0), Vector3(16, sy, 6),
	])
	return root

static func _build_bounds(root: Node3D) -> void:
	var h := 3.0
	var wall_mat := _mat(Color(0.3, 0.34, 0.4))
	_box(root, Vector3(0, h / 2.0, -SIZE / 2.0), Vector3(SIZE + 1.0, h, 0.5), wall_mat)
	_box(root, Vector3(0, h / 2.0, SIZE / 2.0), Vector3(SIZE + 1.0, h, 0.5), wall_mat)
	_box(root, Vector3(-SIZE / 2.0, h / 2.0, 0), Vector3(0.5, h, SIZE + 1.0), wall_mat)
	_box(root, Vector3(SIZE / 2.0, h / 2.0, 0), Vector3(0.5, h, SIZE + 1.0), wall_mat)

static func _build_cover(root: Node3D) -> void:
	var cover_mat := _mat(Color(0.42, 0.45, 0.5))
	var crate_mat := _mat(Color(0.5, 0.4, 0.3))
	# Center structure: two low walls making lanes.
	_box(root, Vector3(0, 0.6, -3.0), Vector3(8.0, 1.2, 0.5), cover_mat)
	_box(root, Vector3(0, 0.6, 3.0), Vector3(8.0, 1.2, 0.5), cover_mat)
	# Crates scattered (cover at range).
	var crates := [
		Vector3(-8, 0.5, -8), Vector3(8, 0.5, 8), Vector3(-8, 0.5, 8),
		Vector3(8, 0.5, -8), Vector3(0, 0.5, 10), Vector3(0, 0.5, -10),
		Vector3(-12, 0.5, 0), Vector3(12, 0.5, 0),
	]
	for p in crates:
		_box(root, p, Vector3(1.0, 1.0, 1.0), crate_mat)
	# Verticality: two platforms with ramps.
	_box(root, Vector3(-14, 1.5, 12), Vector3(6.0, 0.3, 6.0), cover_mat)
	_box(root, Vector3(14, 1.5, -12), Vector3(6.0, 0.3, 6.0), cover_mat)
	# Ramps (rotated boxes) onto the platforms.
	_ramp(root, Vector3(-14, 0.75, 7.5), 3.5)
	_ramp(root, Vector3(14, 0.75, -7.5), 3.5)

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

static func _build_potions(root: Node3D, world: World) -> void:
	var spots := [Vector3(-4, 0.4, 0), Vector3(4, 0.4, 0), Vector3(-14, 0.4, 12), Vector3(14, 0.4, -12)]
	for p in spots:
		var pk := HealthPickup.new()
		root.add_child(pk)
		pk.setup(world, p)

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
