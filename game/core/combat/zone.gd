class_name ZoneEntity
extends Node3D
## Server-authoritative effect zone (Phase 3: slow fields). Stepped by the
## world at 60 Hz: applies its effect to every enemy inside `radius` each
## tick (re-applied, so presence = continuous effect), dies at duration.

var caster: CharacterEntity
var team := 0
var radius := 3.0
var duration := 4.0
var slow_ratio := 0.3
var elapsed := 0.0
var dead := false
var world_ref: World = null
var color := Color(0.6, 0.5, 1.0)

func setup(world: World, caster_: CharacterEntity, pos: Vector3, radius_: float, duration_: float, slow_: float) -> void:
	world_ref = world
	caster = caster_
	team = caster_.team
	radius = radius_
	duration = duration_
	slow_ratio = slow_
	# Local position: the zone is added to the world (at the origin) by the
	# caller right after setup; global_position before in-tree logs an error.
	position = pos

func _ready() -> void:
	# Render-side ring (placeholder; original VFX pass with hero art).
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.08
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.18)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cyl.material = mat
	mi.mesh = cyl
	add_child(mi)

func step(world: World, dt: float) -> void:
	if dead:
		return
	if caster == null or not is_instance_valid(caster):
		_die()
		return
	elapsed += dt
	if elapsed >= duration:
		world.emit_event("zone_expire", {"zone" = self, "pos" = global_position})
		_die()
		return
	# Continuous effect: re-apply to each enemy inside every tick.
	for ch in world.characters:
		if ch.team != team and ch.alive:
			if ch.global_position.distance_to(global_position) <= radius + 0.4:
				ch.apply_slow(world, slow_ratio, 0.25)  # short re-apply; presence extends it

func _die() -> void:
	dead = true
	queue_free()
