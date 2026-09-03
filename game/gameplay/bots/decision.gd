class_name BotDecision
extends Node
## Decision module (Phase 4) — what a bot *does about* what it knows.
## v1: priority utility over five intents with role responsibilities:
##   tank holds the front (retreats late, fights close), support protects
##   (regroups to wounded allies early, fights a bit further), controller
##   investigates sound, assault fights at normal ranges.
## (Behavior trees + objective-aware utilities land with mode objectives.)

enum Intent { ATTACK, INVESTIGATE, REGROUP, RETREAT, HOLD }

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

	# 2) Attack: a fresh known enemy.
	if fresh_t:
		intent = Intent.ATTACK
		target = t
		fight_range = _fight_range_for_role()
		goal = t.global_position
		return

	# 3) Investigate: a heard shot (controllers weigh this highest).
	if perception_.heard():
		intent = Intent.INVESTIGATE
		target = t if t != null and perception_.fresh(t) else null
		goal = perception_.heard_pos
		return

	# 4) Regroup: an ally is badly hurt (support weighs this higher).
	var threshold := params.grouping_threshold * (1.1 if role == HeroData.Role.SUPPORT else 1.0)
	var ally := _wounded_ally(world_, hero_, threshold)
	if ally != null:
		intent = Intent.REGROUP
		target = t if t != null and perception_.fresh(t) else null
		goal = ally.global_position
		return

	# 5) Hold: stay put (execution does the scan turn).
	intent = Intent.HOLD
	target = null
	goal = hero_.global_position

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

func _own_spawn(world_: World, hero_: CharacterEntity) -> Vector3:
	var pts: Array = world_.spawn_points.get(hero_.team, [])
	if pts.size() > 0:
		return pts[0]
	return hero_.death_pos
