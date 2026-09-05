class_name ControlMode
extends Mode
## Control (Phase 6 v1, D16): one central objective point; the first team to
## target_captures captures wins, else the higher capture count at
## match_duration (a team holding the point breaks a 0-0 / tied timeout).
## v1 rules (explicit tradeoffs, documented in ROADMAP):
##  - ONE live character inside the radius captures (solo capture);
##  - BOTH teams inside = CONTESTED (progress freezes);
##  - a captured point stays with the capturing team (no neutral reset,
##    no decay) until the enemy re-captures;
##  - re-capture progress starts from 0 for the new occupying team
##    (direction flips reset the bar);
##  - the capture radius is horizontal (|dy| <= 2 m keeps jump-spam and
##    platform-camping out of the circle in v1).
## State lives on World (control_owner/progress/progress_team/score) so the
## in-place match reset (D14, World.reset) clears it; the Mode itself is
## stateless config.
func _init() -> void:
	mode_id = "control"
	display_name = "Control"

## Solo capture time (s) — 15 s x target_captures x contest overhead lands
## matches in the 3-8 min band (directive §6) at 3v3.
@export var capture_seconds := 15.0
@export var capture_radius := 4.0
@export var target_captures := 2
@export var vertical_tolerance := 2.0
## Where capturers aim: inside the circle, spread 120° apart per team-mate
## index, phase-shifted 15° between teams (bots read these from world.mode).
@export var capture_goal_offset := 2.0
@export var capture_goal_spread_deg := 120.0
@export var capture_goal_team_phase_deg := 15.0

func step(world: World, dt: float) -> void:
	if world.match_over or not world.control_active:
		return
	var t0 := false
	var t1 := false
	for ch in world.characters:
		var c: CharacterEntity = ch
		if not c.alive:
			continue
		var d: Vector3 = c.global_position - world.control_point
		if absf(d.y) > vertical_tolerance:
			continue
		if d.x * d.x + d.z * d.z <= capture_radius * capture_radius:
			if int(c.team) == 0:
				t0 = true
			else:
				t1 = true
	if t0 and t1:
		return  # contested: nobody captures
	if not t0 and not t1:
		return  # holding: the owner keeps the point (v1, no neutral reset)
	var occ := 0 if t0 else 1
	if world.control_owner == occ:
		# Holding: the owning team occupies its own captured point - the bar
		# stays full and no further capture fires (the capture is a TRANSITION:
		# neutral -> team, or enemy -> team, never team -> itself).
		world.control_progress = 1.0
		world.control_progress_team = occ
		return
	if world.control_progress_team != occ:
		world.control_progress_team = occ
		world.control_progress = 0.0
	world.control_progress += dt / capture_seconds
	if world.control_progress >= 1.0:
		_capture(world, occ)

func _capture(world: World, team: int) -> void:
	world.control_score[team] = int(world.control_score.get(team, 0)) + 1
	world.control_owner = team
	world.control_progress = 1.0
	world.emit_event("control_capture", {
		"team": team,
		"score": score_of(world),
		"time": world.time,
	})
	if int(world.control_score.get(team, 0)) >= target_captures:
		world.finish_match(team)

func check_over(world: World) -> void:
	if world.match_over:
		return
	var s0: int = int(world.control_score.get(0, 0))
	var s1: int = int(world.control_score.get(1, 0))
	if world.time >= world.match_duration:
		if s0 != s1:
			world.finish_match(0 if s0 > s1 else 1)
		elif world.control_owner != -1:
			world.finish_match(world.control_owner)
		else:
			world.finish_match(-1)

func score_of(world: World) -> Array:
	return [int(world.control_score.get(0, 0)), int(world.control_score.get(1, 0))]
