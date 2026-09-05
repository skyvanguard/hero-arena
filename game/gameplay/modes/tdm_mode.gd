class_name TDMMode
extends Mode
## Team Deathmatch as a Mode resource (Phase 6 framework, D16): same rules
## the built-in World legacy path has always used (first to
## world.target_score kills, else higher score at world.match_duration).
## Keeping the rules here — instead of in World — means future modes share
## the host/over/score plumbing; World only keeps the legacy path for
## mode == null (pre-framework callers).
func _init() -> void:
	mode_id = "tdm"
	display_name = "Team Deathmatch"

func check_over(world: World) -> void:
	if world.match_over:
		return
	var s0: int = int(world.score.get(0, 0))
	var s1: int = int(world.score.get(1, 0))
	if s0 >= world.target_score or s1 >= world.target_score:
		world.finish_match(0 if s0 > s1 else (1 if s1 > s0 else -1))
	elif world.time >= world.match_duration:
		world.finish_match(0 if s0 > s1 else (1 if s1 > s0 else -1))
