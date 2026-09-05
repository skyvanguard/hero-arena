class_name ModeRegistry
extends RefCounted
## Mode registry (Phase 6 framework, D16): mode_id (MatchConfig.mode_id,
## hero-select/lobby will choose from this list) -> Mode resource. Modes are
## plain Resources (no nodes) so a fresh instance per match is free and the
## content/balance-style "data, not code" rule holds.
static func ids() -> Array:
	return ["tdm", "control", "capture", "escort"]

static func get_mode(id: String) -> Mode:
	match id:
		"control":
			return ControlMode.new()
		"capture":
			return CaptureMode.new()
		"escort":
			return EscortMode.new()
		_, _:
			return TDMMode.new()
