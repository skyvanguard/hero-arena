class_name EscortMode
extends Mode
## Escort (Phase 6, D17): a payload rides the arena's central lane (z =
## lane_z) from the ATTACKER spawn side (team 0) toward the defender side
## (team 1). Attackers within push_radius add push power, defenders within
## slow_radius subtract it; speed = max_speed * clamp(power, 0, 1) - v1:
## the payload never moves backward. Reaching the goal line wins for team 0;
## surviving until match_duration wins for team 1 (defenders hold).
## v1 tradeoffs: 1-D lane (no lateral steering), no obstacle on the lane,
## power is a head-count clamp (two defenders fully stop it, extras don't
## push it back).
func _init() -> void:
	mode_id = "escort"
	display_name = "Escort"

@export var max_speed := 1.5
@export var push_radius := 5.0
@export var slow_radius := 5.0
@export var lane_z := 0.0

func setup(world: World) -> void:
	# Deterministic from the spawns: the payload starts on team 0's side and
	# runs to team 1's side (the central spawn x of each team).
	var x0: float = _spawn_x(world, 0)
	var x1: float = _spawn_x(world, 1)
	world.payload_start_x = x0
	world.payload_goal_x = x1
	world.payload_pos = x0
	world.payload_speed = 0.0

func _spawn_x(world: World, team: int) -> float:
	var pts: Array = world.spawn_points.get(team, [])
	if pts.size() > 1:
		return pts[1].x
	if pts.size() == 1:
		return pts[0].x
	return 16.0 if team == 0 else -16.0

func step(world: World, dt: float) -> void:
	if world.match_over:
		return
	var px: Vector3 = Vector3(world.payload_pos, 0.9, lane_z)
	var power := 0.0
	for ch in world.characters:
		var c: CharacterEntity = ch
		if not c.alive:
			continue
		var d: Vector3 = c.global_position - px
		if absf(d.y) > 2.5:
			continue
		var r := push_radius if int(c.team) == 0 else slow_radius
		if d.x * d.x + d.z * d.z <= r * r:
			power += 1.0 if int(c.team) == 0 else -1.0
	world.payload_speed = max_speed * clampf(power, 0.0, 1.0)
	if world.payload_speed > 0.0:
		var dir := signf(world.payload_goal_x - world.payload_start_x)
		world.payload_pos += world.payload_speed * dt * dir
		if dir > 0.0 and world.payload_pos >= world.payload_goal_x:
			world.finish_match(0)
		elif dir < 0.0 and world.payload_pos <= world.payload_goal_x:
			world.finish_match(0)

## 0..1 along the lane (wire + HUD).
func progress_of(world: World) -> float:
	var span := world.payload_goal_x - world.payload_start_x
	if absf(span) < 0.001:
		return 0.0
	return clampf((world.payload_pos - world.payload_start_x) / span, 0.0, 1.0)

func check_over(world: World) -> void:
	if world.match_over:
		return
	if world.time >= world.match_duration:
		world.finish_match(1)  # defenders held to the final second

func score_of(_world: World) -> Array:
	# Escort has no per-side running score; the winner tells the story.
	return [0, 0]
