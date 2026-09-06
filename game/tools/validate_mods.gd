extends Node
## D34 (mod support v1): the mod validation CLI. Run headless:
##   godot --headless --path game res://tools/validate_mods.tscn
## Prints one line per mod (accepted/rejected + every issue) and exits
## with the issue count (0 = all mods valid).
func _ready() -> void:
	var issues: Array = ModValidator.validate_all()
	for m in ModLoader.mods:
		var mid := str(m["id"])
		if bool(m["accepted"]):
			var mm: ModManifest = m["manifest"]
			print("MOD %s v%s (api %d) by %s: OK" % [mid, mm.version, mm.api_version, mm.author])
		else:
			print("MOD %s: REJECTED - %s" % [mid, str(m["reason"])])
	for i in issues:
		if not str(i).begins_with("MOD ") and not str(i).ends_with(": rejected") and not str(i).ends_with(": rejected - "):
			print("  issue: " + str(i))
	print("VALIDATE: %d issue(s), %d mod(s)" % [issues.size(), ModLoader.mods.size()])
	get_tree().quit(issues.size())
