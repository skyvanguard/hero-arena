class_name BotController
extends Node
## Bot = a controller node on the CharacterEntity, using the same interface as
## a human client (ARCHITECTURE.md §3.6). Phase 4: perception -> decision ->
## execution as composed nodes (BotPerception / BotDecision); the whole
## behavior profile comes from a BotDifficulty pack (content/balance/bots/).
## Contract (unchanged from Phase 1): setup(hero, target, world, diff) and
## step(world, dt) once per world tick; the controller re-pulses
## move_input/want_fire/aim_target every tick (server authority resets them
## on non-player entities).

var hero: CharacterEntity = null
var target: CharacterEntity = null   # legacy 1v1 hint; multi-target uses perception
var world: World = null
var difficulty := "normal"
var params: BotDifficulty = null

var perception: BotPerception = null
var decision: BotDecision = null

var reaction_until := 0.0
var _fresh_target: CharacterEntity = null
## Angular aim error (aim error model): a small random rotation resampled
## every 0.2 s, applied by rotating the direction toward the known position
## (angular, not a fixed meter offset: accuracy must degrade with range).
var aim_error_dev := Vector3.ZERO
var _aim_error_t := 0.0
var strafe_dir := 1.0
var strafe_t := 0.0
var _ability_t := 0.0

func setup(hero_: CharacterEntity, target_: CharacterEntity, world_: World, diff: String = "normal") -> void:
	hero = hero_
	target = target_
	world = world_
	difficulty = diff
	params = BotDifficulties.by_id(diff)
	hero.controller = self
	perception = BotPerception.new()
	perception.name = "Perception"
	add_child(perception)
	perception.setup(hero_, world_, params)
	decision = BotDecision.new()
	decision.name = "Decision"
	add_child(decision)
	var role: int = 0
	if hero_ is Hero and (hero_ as Hero).hero_data != null:
		role = (hero_ as Hero).hero_data.role
	decision.setup(params, role)

func step(world_: World, dt: float) -> void:
	world = world_
	if not hero.alive:
		hero.move_input = Vector2.ZERO
		hero.want_fire = false
		return
	perception.scan(world_)
	decision.decide(world_, perception, hero)
	target = decision.target
	_aim_error(dt)
	_ability_t -= dt
	match decision.intent:
		BotDecision.Intent.ATTACK:
			_execute_attack(dt)
		BotDecision.Intent.INVESTIGATE:
			_execute_move_to(decision.goal, dt, false)
		BotDecision.Intent.REGROUP:
			_execute_move_to(_regroup_goal(), dt, decision.target != null)
		BotDecision.Intent.RETREAT:
			_execute_retreat(dt)
		_:
			_execute_hold(dt)
	_ability_timing(dt)
	_maybe_reload()

## --- Execution -----------------------------------------------------------
func _execute_attack(dt: float) -> void:
	var hp := hero.global_position
	var known_pos := perception.last_known(decision.target)
	# Move toward the flank goal (target + lateral spread for team-mates),
	# aim at the enemy's actual known position.
	var goal: Vector3 = decision.goal
	hero.face_toward(known_pos)
	var to_g := goal - hp
	to_g.y = 0.0
	var dist_g := to_g.length()
	var dir_g := to_g / maxf(dist_g, 0.001)
	var fwd := hero.global_transform.basis * CharacterEntity.FWD
	strafe_t -= dt
	if strafe_t <= 0.0:
		strafe_dir = -strafe_dir
		strafe_t = randf_range(params.strafe_min, params.strafe_max)
	var desire := Vector3.ZERO
	if dist_g > decision.fight_range + 3.0:
		desire += dir_g
	elif dist_g < decision.fight_range - 3.0:
		desire -= dir_g * 0.6
	desire += (fwd.cross(Vector3.UP)) * strafe_dir * 0.9
	_desire_move(desire.normalized())
	var dist := known_pos.distance_to(hp)  # firing range check uses the real target
	var fresh := perception.fresh(decision.target)
	if fresh:
		if _fresh_target != decision.target:
			reaction_until = world.time + params.reaction
		_fresh_target = decision.target
	else:
		_fresh_target = null
	hero.aim_target = _aim_point(known_pos)
	hero.want_fire = fresh and world.time >= reaction_until and dist < params.engage_range

func _execute_move_to(goal: Vector3, dt: float, can_fire: bool) -> void:
	var d := goal - hero.global_position
	d.y = 0.0
	if d.length() > 1.5:
		hero.face_toward(goal)
		_desire_move(d.normalized())
	else:
		hero.move_input = Vector2.ZERO
	var fresh := decision.target != null and perception.fresh(decision.target)
	if can_fire and fresh and perception.last_known(decision.target).distance_to(hero.global_position) < params.engage_range:
		hero.aim_target = _aim_point(perception.last_known(decision.target))
		hero.want_fire = world.time >= reaction_until
	else:
		hero.want_fire = false

func _execute_retreat(dt: float) -> void:
	var pts: Array = world.spawn_points.get(hero.team, [hero.death_pos])
	var home: Vector3 = pts[0]
	var d := home - hero.global_position
	d.y = 0.0
	if d.length() > 1.0:
		_desire_move(d.normalized())
	else:
		hero.move_input = Vector2.ZERO
	var fresh := decision.target != null and perception.fresh(decision.target)
	if fresh:
		hero.face_toward(perception.last_known(decision.target))
		hero.aim_target = _aim_point(perception.last_known(decision.target))
		hero.want_fire = world.time >= reaction_until
	else:
		hero.want_fire = false

func _execute_hold(dt: float) -> void:
	# No known enemy: hold position and slowly scan the horizon.
	hero.move_input = Vector2.ZERO
	hero.want_fire = false
	hero.rotation.y += params.scan_speed * dt

## Reloads are a bot responsibility (humans press R): top up when the clip is
## dry in combat, and pre-load when out of the fight.
func _maybe_reload() -> void:
	var w: Weapon = hero.weapon
	if w == null or w.reloading:
		return
	if w.ammo <= 0:
		if decision.intent == BotDecision.Intent.ATTACK or decision.intent == BotDecision.Intent.RETREAT:
			w.start_reload()
	elif decision.intent == BotDecision.Intent.HOLD and w.ammo * 2 <= w.clip_size:
		w.start_reload()

func _regroup_goal() -> Vector3:
	# Offset from the wounded ally so bots don't stack on one point.
	var side := hero.global_transform.basis * Vector3.RIGHT
	return decision.goal + side * 1.2 + Vector3.UP * 0.0

## --- Shared ---------------------------------------------------------------
func _desire_move(dir: Vector3) -> void:
	hero.move_input = _to_local(dir)

func _aim_error(dt: float) -> void:
	_aim_error_t -= dt
	if _aim_error_t <= 0.0:
		_aim_error_t = 0.2
		var v := Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1))
		if v.length_squared() > 0.0001:
			aim_error_dev = v.normalized() * deg_to_rad(params.aim_error_deg)
		else:
			aim_error_dev = Vector3.ZERO

## Aim point with the angular error model applied: rotate the direction to
## target_pos by random deviations inside the aim error cone (resampled
## every 0.2 s). Aimed from head height (CharacterEntity.AIM_HEIGHT).
func _aim_point(target_pos: Vector3) -> Vector3:
	var origin := hero.global_position + Vector3.UP * CharacterEntity.AIM_HEIGHT
	var base: Vector3 = (target_pos - origin).normalized()
	if base.length_squared() < 0.001:
		return target_pos
	if aim_error_dev.length() > 0.0001:
		var axis1: Vector3 = base.cross(Vector3.UP)
		if axis1.length_squared() < 0.0001:
			axis1 = base.cross(Vector3.RIGHT)
		axis1 = axis1.normalized()
		var axis2: Vector3 = base.cross(axis1).normalized()
		base = base.rotated(axis1, aim_error_dev.x)
		base = base.rotated(axis2, aim_error_dev.y)
	return origin + base * 40.0

## Ability timing (v1): one evaluated cue set per 0.5 s, gated by the pack's
## ability_quality. Bots use the SAME cast API as players (server-side).
func _ability_timing(dt: float) -> void:
	if _ability_t > 0.0 or decision.intent != BotDecision.Intent.ATTACK:
		return
	_ability_t = 0.5
	if hero.ability == null or decision.target == null:
		return
	if not perception.fresh(decision.target):
		return
	if randf() > params.ability_quality:
		return
	var dist: float = perception.last_known(decision.target).distance_to(hero.global_position)
	var role: int = decision.role
	if role == HeroData.Role.SUPPORT and hero.ability.can_cast(0):
		if _ally_in_range(8.0, 0.6):
			hero.ability.cast(0)
			return
	elif role == HeroData.Role.CONTROLLER and hero.ability.can_cast(0) and dist < params.engage_range + 4.0:
		hero.ability.cast(0)
		return
	elif hero.ability.can_cast(0) and dist < decision.fight_range + 4.0:
		hero.ability.cast(0)
		return
	if hero.ability.can_activate_ult() and dist < params.engage_range:
		hero.ability.activate_ult()

func _ally_in_range(range: float, hp_max: float) -> bool:
	for ch in world.characters.duplicate():
		if ch == hero or not is_instance_valid(ch) or not ch.alive:
			continue
		if ch.team != hero.team or ch.hp / ch.max_hp > hp_max:
			continue
		if ch.global_position.distance_to(hero.global_position) <= range:
			return true
	return false

# Convert a world-space direction into the hero's local move_input (x=right, y=forward).
func _to_local(dir: Vector3) -> Vector2:
	var basis := hero.global_transform.basis
	var fwd := Vector3(basis.z.x, 0, basis.z.z).normalized()
	var right := Vector3(basis.x.x, 0, basis.x.z).normalized()
	var v := Vector2(dir.dot(right), dir.dot(fwd))
	if v.length() > 1.0:
		v = v.normalized()
	return v
