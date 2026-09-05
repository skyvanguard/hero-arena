class_name BotDecision
extends Node
## Decision module (Phase 4) — what a bot *does about* what it knows.
## v1: priority utility over five intents with role responsibilities:
##   tank holds the front (retreats late, fights close), support protects
##   (regroups to wounded allies early, fights a bit further), controller
##   investigates sound, assault fights at normal ranges.
## (Behavior trees + objective-aware utilities land with mode objectives.)

enum Intent { ATTACK, CAPTURE, INVESTIGATE, REGROUP, RETREAT, HOLD }

var params: BotDifficulty = null
var role: int = 0

var intent: int = Intent.HOLD
var target: CharacterEntity = null
var goal := Vector3.ZERO
## ATTACK-only: the distance this bot wants to fight at (role-biased).
var fight_range := 14.0
var _low_hp_since := -1e9
var _retreat_committed := false

func setup(params_: BotDifficulty, role_: int) -> void:
	params = params_
	role = role_

func decide(world_: World, perception_: BotPerception, hero_: CharacterEntity) -> void:
	var hp_ratio := hero_.hp / hero_.max_hp
	var t: CharacterEntity = perception_.best_target()
	var fresh_t := t != null and perception_.fresh(t)

	# 1) Retreat: wounded + enemy on us. Confirmation window (retreat_confirm)
	# keeps bots killable; hysteresis holds until HP > retreat_at + 0.15.
	var retreat_at := params.retreat_hp * (0.7 if role == HeroData.Role.TANK else 1.0)
	if _retreat_committed:
		if t != null and perception_.fresh(t) and hp_ratio < retreat_at + 0.15:
			intent = Intent.RETREAT
			target = t
			goal = _own_spawn(world_, hero_)
			return
		_retreat_committed = false
	if t != null and hp_ratio < retreat_at:
		if _low_hp_since < -1e8:
			_low_hp_since = world_.time
		if world_.time - _low_hp_since >= params.retreat_confirm:
			intent = Intent.RETREAT
			target = t
			goal = _own_spawn(world_, hero_)
			_retreat_committed = true
			return
	else:
		_low_hp_since = -1e9

	# 2) Objective pressure (Phase 6, D18): the enemy flag has been
	# uncarried too long -> the lowest-instance-id teammate breaks away from
	# whatever fight they are in and takes it (a stalemate in the center must
	# not leave the flag sitting there forever; 8 s is the patience value).
	if world_.mode is CaptureMode:
		var ef: int = 1 - int(hero_.team)
		if world_.flag_carrier[ef] == null \
				and float(world_.flag_free_time.get(ef, 0.0)) > 8.0 \
				and _is_min_id_teammate(world_, hero_):
			intent = Intent.CAPTURE
			target = null
			goal = world_.flags[ef]
			return

	# 3) Attack: a fresh known enemy. The goal is a flank point, not the
	# enemy itself: team-mates sharing a target spread laterally so the
	# squad stops stacking on one line of fire (params.flank_spacing).
	if fresh_t:
		intent = Intent.ATTACK
		target = t
		fight_range = _fight_range_for_role()
		goal = _flank_goal(world_, hero_, t)
		return

	# 4) Objective (Phase 6, D16/D17): in an objective mode, an UNENGAGED bot
	# takes its mode goal (Control: the point; Capture: flag logic; Escort:
	# the payload). ATTACK above keeps engaged bots fighting, so the squad
	# splits naturally (fighters + objective-takers). Goals are deterministic
	# per-bot spots (no randomness on the server).
	if world_.mode != null and world_.mode.mode_id != "tdm":
		var og: Vector3 = _objective_goal(world_, hero_)
		if og != Vector3.INF:
			intent = Intent.CAPTURE
			target = null
			goal = og
			return

	# 5) Investigate: a heard shot (controllers weigh this highest).
	if perception_.heard():
		intent = Intent.INVESTIGATE
		target = t if t != null and perception_.fresh(t) else null
		goal = perception_.heard_pos
		return

	# 6) Regroup: an ally is badly hurt (support weighs this higher), or I've
	# drifted out of formation while the squad is in a fight (stick/protect).
	var threshold := params.grouping_threshold * (1.1 if role == HeroData.Role.SUPPORT else 1.0)
	var ally := _wounded_ally(world_, hero_, threshold)
	if ally == null:
		ally = _stick_ally(world_, hero_)
	if ally != null:
		intent = Intent.REGROUP
		target = t if t != null and perception_.fresh(t) else null
		goal = ally.global_position
		return

	# 7) Hold: stay put (execution does the scan turn).
	intent = Intent.HOLD
	target = null
	goal = hero_.global_position

## The mode goal for an unengaged bot (INF = none: fall through to combat).
func _objective_goal(world_: World, hero_: CharacterEntity) -> Vector3:
	match (world_.mode as Mode).mode_id:
		"control":
			if world_.control_active and world_.control_owner != hero_.team:
				return _capture_goal(world_, hero_)
			return Vector3.INF
		"capture":
			return _capture_flag_goal(world_, hero_)
		"escort":
			return _escort_goal(world_, hero_)
		_, _:
			return Vector3.INF

## Capture (D17): (1) I carry the enemy flag -> my base; (2) the enemy flag
## is uncarried (base or drop) -> steal it (per-bot offset, no stacking);
## (3) my flag is carried by the enemy -> the lowest-instance-id unengaged
## teammate goes home, the rest keep fighting.
func _capture_flag_goal(world_: World, hero_: CharacterEntity) -> Vector3:
	var enemy_flag: int = 1 - int(hero_.team)
	var enemy_carrier: CharacterEntity = world_.flag_carrier[enemy_flag]
	if enemy_carrier == hero_:
		return world_.flag_bases[hero_.team]
	if enemy_carrier == null:
		var fp: Vector3 = world_.flags[enemy_flag]
		var a := deg_to_rad(float(_team_index(world_, hero_)) * 90.0 + 45.0)
		return fp + Vector3(cos(a) * 1.0, 0.0, sin(a) * 1.0)
	var own_carrier: CharacterEntity = world_.flag_carrier[hero_.team]
	if own_carrier != null and _is_min_id_teammate(world_, hero_):
		return world_.flag_bases[hero_.team]
	return Vector3.INF

## Escort (D17): both teams converge on the payload - attackers a step
## AHEAD on the goal side (push), defenders a step BEHIND (brake), with a
## deterministic per-bot z offset so the lane doesn't stack.
func _escort_goal(world_: World, hero_: CharacterEntity) -> Vector3:
	var dir := signf(world_.payload_goal_x - world_.payload_start_x)
	var ahead := 2.0 if int(hero_.team) == 0 else -2.0
	var z := float(_team_index(world_, hero_) - 1) * 2.5
	return Vector3(world_.payload_pos + dir * ahead, 0.9, z)

func _team_index(world_: World, hero_: CharacterEntity) -> int:
	var idx := 0
	for chx in world_.characters:
		var ch: CharacterEntity = chx
		if ch == hero_ or not ch.alive:
			continue
		if ch.team == hero_.team and ch.get_instance_id() < hero_.get_instance_id():
			idx += 1
	return idx

func _is_min_id_teammate(world_: World, hero_: CharacterEntity) -> bool:
	for chx in world_.characters:
		var ch: CharacterEntity = chx
		if ch == hero_ or not ch.alive:
			continue
		if ch.team == hero_.team and ch.get_instance_id() < hero_.get_instance_id():
			return false
	return true

## Control CAPTURE goal: a deterministic per-bot spot INSIDE the capture
## circle (offset/spread/phase from the ControlMode resource) so the point
## gets taken quickly without the capturers clumping on one capsule.
func _capture_goal(world_: World, hero_: CharacterEntity) -> Vector3:
	var cm: ControlMode = world_.mode
	var idx := 0
	for chx in world_.characters:
		var ch: CharacterEntity = chx
		if ch == hero_ or not ch.alive:
			continue
		if ch.team == hero_.team and ch.get_instance_id() < hero_.get_instance_id():
			idx += 1
	var a := deg_to_rad(float(idx) * cm.capture_goal_spread_deg
			+ float(hero_.team) * cm.capture_goal_team_phase_deg)
	return world_.control_point + Vector3(cos(a) * cm.capture_goal_offset, 0.0,
			sin(a) * cm.capture_goal_offset)

func _fight_range_for_role() -> float:
	match role:
		HeroData.Role.TANK:
			return params.ideal_range * 0.8
		HeroData.Role.SUPPORT:
			return params.ideal_range * 1.25
		_:
			return params.ideal_range

func _wounded_ally(world_: World, hero_: CharacterEntity, threshold: float) -> CharacterEntity:
	var best: CharacterEntity = null
	var best_ratio := 1.0
	for chx in world_.characters.duplicate():
		var ch: CharacterEntity = chx
		if ch == hero_ or not is_instance_valid(ch) or not ch.alive:
			continue
		if ch.team != hero_.team:
			continue
		var ratio: float = ch.hp / ch.max_hp
		if ratio < threshold and ratio < best_ratio:
			best_ratio = ratio
			best = ch
	return best

## Flank point for ATTACK: the enemy position plus a lateral offset for
## each team-mate bot sharing this target. Ordering is deterministic
## (nearest bot to the target keeps the center slot), so no per-bot state is
## needed; the offset axis is the bot's own approach perpendicular, so bots
## on opposite sides of the enemy fan out in opposite directions.
func _flank_goal(world_: World, hero_: CharacterEntity, t: CharacterEntity) -> Vector3:
	var base: Vector3 = t.global_position
	var attackers: Array = []
	for chx in world_.characters.duplicate():
		var ch: CharacterEntity = chx
		if ch == hero_ or not is_instance_valid(ch) or not ch.alive:
			continue
		if ch.team != hero_.team:
			continue
		if ch.controller is BotController and (ch.controller as BotController).decision.target == t:
			attackers.append(ch)
	if attackers.is_empty():
		return base
	attackers.append(hero_)
	attackers.sort_custom(func(a: CharacterEntity, b: CharacterEntity) -> bool:
		return a.global_position.distance_squared_to(base) < b.global_position.distance_squared_to(base))
	var idx: int = attackers.find(hero_)
	if idx <= 0:
		return base
	var to_t: Vector3 = base - hero_.global_position
	to_t.y = 0.0
	if to_t.length_squared() < 0.01:
		return base
	var side: Vector3 = to_t.cross(Vector3.UP).normalized()
	return base + side * (float(idx) * params.flank_spacing)

## Stick/protect: the nearest in-combat ally when I am farther from them than
## stick_range and have nothing else to do. "In combat" = the ally is
## attacking or took damage within the last 2 s (regen-delay window).
func _stick_ally(world_: World, hero_: CharacterEntity) -> CharacterEntity:
	var best: CharacterEntity = null
	var best_d := 1e9
	for chx in world_.characters.duplicate():
		var ch: CharacterEntity = chx
		if ch == hero_ or not is_instance_valid(ch) or not ch.alive:
			continue
		if ch.team != hero_.team:
			continue
		var in_combat := false
		if ch.controller is BotController and (ch.controller as BotController).decision.intent == Intent.ATTACK:
			in_combat = true
		if not in_combat and ch._since_damage < 2.0:
			in_combat = true
		if not in_combat:
			continue
		var d: float = ch.global_position.distance_to(hero_.global_position)
		if d > params.stick_range and d < best_d:
			best_d = d
			best = ch
	return best

func _own_spawn(world_: World, hero_: CharacterEntity) -> Vector3:
	var pts: Array = world_.spawn_points.get(hero_.team, [])
	if pts.size() > 0:
		return pts[0]
	return hero_.death_pos
