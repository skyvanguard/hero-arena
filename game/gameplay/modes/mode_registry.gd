class_name ModeRegistry
extends RefCounted
## Mode registry (Phase 6 framework, D16): mode_id (MatchConfig.mode_id,
## hero-select/lobby will choose from this list) -> Mode resource. Modes are
## plain Resources (no nodes) so a fresh instance per match is free and the
## content/balance-style "data, not code" rule holds.
static func ids() -> Array:
	var out: Array = ["tdm", "control", "capture", "escort"]
	for p in ModLoader.mod_files("modes"):  # D34: drop-in modes
		var bn: String = p.get_file().get_basename()
		if not out.has(bn):
			out.append(bn)
	return out

static func get_mode(id: String) -> Mode:
	match id:
		"control":
			return ControlMode.new()
		"capture":
			return CaptureMode.new()
		"escort":
			return EscortMode.new()
		_, _:
			# D34: a mod mode is a Mode-derived Resource (shared cached
			# instance; state lives on the world, so sharing is safe).
			for p in ModLoader.mod_files("modes"):
				if p.get_file() == id + ".tres":
					var r: Resource = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REUSE)
					if r is Mode:
						return r
			return TDMMode.new()
