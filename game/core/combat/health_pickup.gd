class_name HealthPickup
extends Area3D
## T3-style map health potion: restores a chunk of HP, respawns after a delay.
## Timers run on the world clock (authoritative, headless-safe).

const HEAL_AMOUNT := 40.0
const RESPAWN_TIME := 25.0

var world_ref: World
var used := false

func _ready() -> void:
	collision_layer = 1
	collision_mask = CharacterEntity.LAYER_BODY
	monitoring = true
	body_entered.connect(_on_body_entered)

func setup(world: World, pos: Vector3) -> void:
	# position (not global_position): setup runs before the arena enters the tree.
	world_ref = world
	position = pos
	_build_visual()

func _on_body_entered(body: Node3D) -> void:
	if used or body is not CharacterEntity:
		return
	var ch := body as CharacterEntity
	if not ch.alive or ch.hp >= ch.max_hp:
		return
	used = true
	ch.hp = minf(ch.hp + HEAL_AMOUNT, ch.max_hp)
	ch.emit_hp()
	ch._since_damage = 0.0
	world_ref.emit_event("pickup", {"pos" = global_position, "heal" = HEAL_AMOUNT})
	hide()
	world_ref.schedule(world_ref.time + RESPAWN_TIME, func() -> void:
		used = false
		show())

func _build_visual() -> void:
	var shape := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = Vector3(0.5, 0.5, 0.5)
	shape.shape = s
	add_child(shape)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.45, 0.45, 0.45)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.2, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.2, 0.25)
	mat.emission_energy_multiplier = 0.6
	box.material = mat
	mi.mesh = box
	add_child(mi)
