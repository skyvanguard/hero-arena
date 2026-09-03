class_name WorldFX
extends Node
## Render-side feedback spawned from authoritative world events:
## floating damage numbers + hitscan tracers. Headless-safe (no-ops there).

var world: World
var _labels: Array[Label3D] = []

func setup(world_: World) -> void:
	world = world_
	if DisplayServer.get_name() == "headless":
		return
	world.world_event.connect(_on_world_event)

func _on_world_event(name: String, data: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	match name:
		"hit":
			_spawn_damage_number(data)
		"shot":
			_spawn_tracer(data)

func _spawn_damage_number(data: Dictionary) -> void:
	var pos: Vector3 = data.pos + Vector3(0.3, 0.4, 0) + Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2))
	var l := Label3D.new()
	var amt: float = data.amount
	l.text = ("HS %d" % int(amt)) if data.is_head else ("%d" % int(amt))
	l.position = pos
	l.pixel_size = 0.004
	l.font_size = 48
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = Color(1, 0.85, 0.2) if data.is_head else Color.WHITE
	add_child(l)
	_labels.append(l)
	var t := 0.0
	var tween := create_tween()
	tween.tween_property(l, "position:y", pos.y + 0.9, 0.6)
	tween.parallel().tween_property(l, "modulate",
			Color(l.modulate.r, l.modulate.g, l.modulate.b, 0.0), 0.6)
	tween.tween_callback(l.queue_free)
	_labels.erase(l)

func _spawn_tracer(data: Dictionary) -> void:
	# Godot 4.7 removed Line3D: tracer is a thin unshaded box stretched from->to.
	var from: Vector3 = data.from
	var to: Vector3 = data.to
	var len := from.distance_to(to)
	if len < 0.05:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.03, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.9, 0.5, 0.65)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = mat
	mi.mesh = bm
	add_child(mi)  # must be in-tree before look_at (4.7)
	mi.position = (from + to) * 0.5
	mi.look_at(to, Vector3.UP)
	mi.scale.z = len
	# 4.7: VisualInstance3D.modulate removed; MeshInstance3D uses `transparency` (0=opaque).
	mi.transparency = 0.0
	var tween := create_tween()
	tween.tween_property(mi, "transparency", 1.0, 0.06)
	tween.tween_callback(mi.queue_free)
