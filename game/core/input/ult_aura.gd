class_name UltAura
extends Node3D
## Render-side ultimate aura: a glowing ring that follows its hero while the
## ult buff is active (Phase 2, Kestrel Dive). Render-side only; created by
## WorldFX on the ability_cast event and freed by the world clock.

var hero_ref: CharacterEntity
var aura_color := Color(0.4, 0.7, 1.0)

var _mi: MeshInstance3D

func _ready() -> void:
	_mi = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.1
	cyl.bottom_radius = 1.1
	cyl.height = 0.06
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(aura_color.r, aura_color.g, aura_color.b, 0.35)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cyl.material = mat
	_mi.mesh = cyl
	add_child(_mi)

func _process(delta: float) -> void:
	if hero_ref == null or not is_instance_valid(hero_ref):
		queue_free()
		return
	global_position = hero_ref.global_position + Vector3(0, 0.06, 0)
	rotation.y += delta * 2.0
