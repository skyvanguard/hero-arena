class_name Projectile
extends Node3D
## Server-authoritative projectile (Phase 3 weapon framework). Stepped by the
## world at 60 Hz: moves along dir at speed, dies at max_range, damages the
## first opposing CharacterEntity (body or head sensor) it touches.
## Render-side visual (small glowing core) is headless-safe.

var shooter: CharacterEntity
var team := 0
var damage := 10.0
var headshot_mult := 1.5
var speed := 22.0
var max_range := 60.0
var hit_radius := 0.25
var dir := Vector3.BACK
var traveled := 0.0
var dead := false
var world_ref: World = null
var slow_ratio := 0.0
var slow_duration := 0.0
var color := Color(0.6, 0.9, 1.0)

func setup(world: World, shooter_: CharacterEntity, dir_: Vector3) -> void:
	world_ref = world
	shooter = shooter_
	team = shooter_.team
	dir = dir_.normalized()
	randomize_offset()

func _ready() -> void:
	# Render-side glowing core (placeholder; original VFX pass comes with art).
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.07
	s.height = 0.14
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	s.material = mat
	mi.mesh = s
	add_child(mi)

func randomize_offset() -> void:
	# Slight lateral jitter keeps multi-shots readable (no stacking tracers).
	dir += Vector3(randf_range(-0.004, 0.004), randf_range(-0.004, 0.004), 0.0)
	dir = dir.normalized()

func step(world: World, dt: float) -> void:
	if dead:
		return
	if shooter == null or not is_instance_valid(shooter):
		_die()
		return
	var step_len := speed * dt
	var from := global_position
	var to := from + dir * step_len
	traveled += step_len
	var q := PhysicsRayQueryParameters3D.create(from, to,
			CharacterEntity.LAYER_BODY | CharacterEntity.LAYER_HEAD)
	q.exclude = [shooter.get_rid()]
	var res: Dictionary = shooter.get_world_3d().get_direct_space_state().intersect_ray(q)
	if not res.is_empty():
		if _resolve_hit(res, world):
			return
	if traveled >= max_range:
		world.emit_event("projectile_exhaust", {"proj" = self, "pos" = to})
		_die()
		return
	global_position = to

func _resolve_hit(res: Dictionary, world: World) -> bool:
	var node: Node = res.collider
	while node != null and not (node is CharacterEntity):
		node = node.get_parent()
	if node is CharacterEntity and node.team != team and node.alive:
		var is_head := res.collider is Area3D
		var dmg := damage * (headshot_mult if is_head else 1.0)
		world.damage(node, dmg, shooter, is_head, res.position)
		if shooter.ability != null:
			shooter.ability.on_damage_dealt(dmg)
			shooter.ability.on_hit_landed()
		if is_hit_slow():
			(node as CharacterEntity).apply_slow(world, slow_ratio, slow_duration)
		world.emit_event("projectile_hit", {"proj" = self, "target" = node, "pos" = res.position})
		_die()
		return true
	return false

func is_hit_slow() -> bool:
	return slow_ratio > 0.0

func _die() -> void:
	dead = true
	queue_free()
