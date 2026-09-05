class_name CaptureMode
extends Mode
## Capture / CTF (Phase 6, D17): each team's flag starts at its central
## spawn (the "base"). A LIVE character of the other side within
## steal_radius takes the flag; the flag's OWN team may re-carry a dropped
## flag (re-secure, no score). Carrying the ENEMY flag into your own base
## scores a capture and the flag goes home. The carrier dies -> the flag
## drops where they fell (v1: no drop decay).
## v1 tradeoffs (documented): one flag per team; a flag mid-carry cannot be
## re-stolen until it drops; a teammate re-carrying their own flag home does
## not score; timeout tiebreak = the team holding the ENEMY flag, else draw.
func _init() -> void:
	mode_id = "capture"
	display_name = "Capture"

@export var steal_radius := 1.5
@export var base_radius := 3.0
@export var target_captures := 2

func setup(world: World) -> void:
	world.flag_bases = {0: _base_of(world, 0), 1: _base_of(world, 1)}
	world.flags = {0: world.flag_bases[0], 1: world.flag_bases[1]}
	world.flag_carrier = {0: null, 1: null}
	world.captures = {0: 0, 1: 0}

## A team's base = its CENTRAL spawn point (index 1 of the arena's 3
## spawn z-rows), falling back to the side center.
func _base_of(world: World, team: int) -> Vector3:
	var pts: Array = world.spawn_points.get(team, [])
	if pts.size() > 1:
		return pts[1]
	if pts.size() == 1:
		return pts[0]
	return Vector3(16.0 if team == 0 else -16.0, 0.9, 0.0)

func step(world: World, _dt: float) -> void:
	if world.match_over:
		return
	for team in 2:
		var carrier: CharacterEntity = world.flag_carrier[team]
		if carrier != null:
			if is_instance_valid(carrier) and carrier.alive:
				world.flags[team] = carrier.global_position
			else:
				# Death path: World.kill -> on_kill drops it; this guard
				# covers a freed carrier (tests) without a kill event.
				world.flag_carrier[team] = null
		# Steal / re-secure: any live non-carrier character in the circle.
		if world.flag_carrier[team] == null:
			var fp: Vector3 = world.flags[team]
			for ch in world.characters:
				var c: CharacterEntity = ch
				if not c.alive:
					continue
				var d: Vector3 = c.global_position - fp
				if absf(d.y) > 2.0:
					continue
				if d.x * d.x + d.z * d.z <= steal_radius * steal_radius:
					world.flag_carrier[team] = c
					world.emit_event("flag_stolen", {
						"flag": team, "carrier": c.team,
						"pos": c.global_position, "time": world.time,
					})
					break
		# Return: the carrier of a flag reaches the CARRIER's own base.
		var back: CharacterEntity = world.flag_carrier[team]
		if back != null and is_instance_valid(back) and back.alive:
			var home: Vector3 = world.flag_bases[back.team]
			var d2: Vector3 = back.global_position - home
			if d2.x * d2.x + d2.z * d2.z <= base_radius * base_radius:
				if int(back.team) != int(team):
					# Enemy flag brought home: CAPTURE.
					world.captures[back.team] = int(world.captures.get(back.team, 0)) + 1
					world.emit_event("flag_captured", {
						"flag": team, "team": back.team,
						"score": score_of(world), "time": world.time,
					})
				# The flag goes home either way (capture or re-secure).
				world.flag_carrier[team] = null
				world.flags[team] = world.flag_bases[team]
				if int(world.captures.get(back.team, 0)) >= target_captures:
					world.finish_match(int(back.team))
					return

func on_kill(world: World, _killer: CharacterEntity, victim: CharacterEntity) -> void:
	for team in 2:
		if world.flag_carrier[team] == victim:
			# The flag drops where the carrier fell (v1: no decay).
			world.flags[team] = victim.death_pos if victim.death_pos != Vector3.ZERO else victim.global_position
			world.flag_carrier[team] = null
			world.emit_event("flag_dropped", {
				"flag": team, "pos": world.flags[team], "time": world.time,
			})

func check_over(world: World) -> void:
	if world.match_over:
		return
	var s0: int = int(world.captures.get(0, 0))
	var s1: int = int(world.captures.get(1, 0))
	if world.time >= world.match_duration:
		if s0 != s1:
			world.finish_match(0 if s0 > s1 else 1)
			return
		# Tied: the team HOLDING the enemy flag wins (they were about to
		# score); both flags free -> draw.
		var c0: CharacterEntity = world.flag_carrier[1]  # team0 holds team1's flag
		var c1: CharacterEntity = world.flag_carrier[0]  # team1 holds team0's flag
		if c0 != null and c1 != null:
			world.finish_match(-1)
		elif c0 != null:
			world.finish_match(0)
		elif c1 != null:
			world.finish_match(1)
		else:
			world.finish_match(-1)

func score_of(world: World) -> Array:
	return [int(world.captures.get(0, 0)), int(world.captures.get(1, 0))]
