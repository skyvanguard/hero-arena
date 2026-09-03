extends SceneTree
func _init() -> void:
	for cls in ["VisualInstance3D", "MeshInstance3D", "Label3D", "Node3D"]:
		print("== ", cls)
		var pl := ClassDB.class_get_property_list(cls)
		for p in pl:
			var name: String = p["name"]
			if name.contains("modulate") or name.contains("color") or name.contains("alpha") or name.contains("transpar"):
				print("  ", name, " type=", p["type"])
	quit()
