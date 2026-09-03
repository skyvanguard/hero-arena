class_name PracticeRange
extends RefCounted
## Practice range (Phase 3): an offline target hall — a long lane with no
## cover and resettable dummies at 14/22/30 m. Fully local: no cloud, no
## bots, no opponents. Original geometry only.

const SIZE_X := 24.0
const SIZE_Z := 40.0
const PLAYER_SPAWN := Vector3(0, 0.9, -15.0)
const DUMMY_OFFSETS_Z := [14.0, 22.0, 30.0]  # distance from player spawn

## Pitch that centers the nearest dummy (14 m, mid-body) in the default view,
## so first-timers can shoot the range without re-aiming.
static func initial_aim_pitch() -> float:
	return -atan2(1.67 - 0.9, float(DUMMY_OFFSETS_Z[0]))

static func dummy_positions() -> Array:
	var out: Array = []
	for dz in DUMMY_OFFSETS_Z:
		out.append(Vector3(0, 0.9, PLAYER_SPAWN.z + dz))
	return out

static func build(world: World) -> Node3D:
	var root := Node3D.new()
	root.name = "PracticeRange"

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.09, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.6
	env_node.environment = env
	root.add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -20, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	root.add_child(sun)

	# Floor + lane markings (readability at 30 m).
	_box(root, Vector3(0, -0.25, 0), Vector3(SIZE_X, 0.5, SIZE_Z), _mat(Color(0.15, 0.17, 0.21)))
	_box(root, Vector3(-8.0, 0.02, 2.0), Vector3(0.2, 0.02, SIZE_Z - 2.0), _mat(Color(0.4, 0.6, 0.5), 0.5), true)
	_box(root, Vector3(8.0, 0.02, 2.0), Vector3(0.2, 0.02, SIZE_Z - 2.0), _mat(Color(0.4, 0.6, 0.5), 0.5), true)
	# Range line behind the shooter.
	_box(root, Vector3(0, 0.02, -15.0), Vector3(SIZE_X - 4.0, 0.02, 0.2), _mat(Color(0.5, 0.45, 0.3), 0.6), true)

	_build_bounds(root)

	world.setup_spawn(0, [PLAYER_SPAWN])
	return root

static func _build_bounds(root: Node3D) -> void:
	var h := 3.0
	var mat := _mat(Color(0.28, 0.32, 0.38))
	_box(root, Vector3(0, h / 2.0, -SIZE_Z / 2.0), Vector3(SIZE_X + 1.0, h, 0.5), mat)
	_box(root, Vector3(0, h / 2.0, SIZE_Z / 2.0), Vector3(SIZE_X + 1.0, h, 0.5), mat)
	_box(root, Vector3(-SIZE_X / 2.0, h / 2.0, 0), Vector3(0.5, h, SIZE_Z + 1.0), mat)
	_box(root, Vector3(SIZE_X / 2.0, h / 2.0, 0), Vector3(0.5, h, SIZE_Z + 1.0), mat)

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
