class_name BotController
extends Node
## Bot = a controller node on the CharacterEntity, using the same interface as
## a human client (ARCHITECTURE.md §3.6). Perception -> decision -> execution,
## objective-aware, with difficulty tiers as data (Phase 1: target-shooting;
## Phase 4 adds objectives/teams/retreat polish).

enum State { SEARCH, ENGAGE, RETREAT }

# Difficulty parameter packs (data, not code).
const DIFFICULTIES := {
	"beginner": {reaction = 0.9, aim_error_deg = 4.0, engage_range = 20.0, ideal_range = 10.0, retreat_hp = 0.3, strafe_min = 1.4, strafe_max = 2.4},
	"normal":   {reaction = 0.5, aim_error_deg = 2.5, engage_range = 26.0, ideal_range = 14.0, retreat_hp = 0.35, strafe_min = 0.9, strafe_max = 1.8},
	"advanced": {reaction = 0.25, aim_error_deg = 1.3, engage_range = 30.0, ideal_range = 16.0, retreat_hp = 0.4, strafe_min = 0.6, strafe_max = 1.2},
	"expert":   {reaction = 0.12, aim_error_deg = 0.6, engage_range = 34.0, ideal_range = 18.0, retreat_hp = 0.45, strafe_min = 0.4, strafe_max = 0.9},
}

var hero: CharacterEntity
var target: CharacterEntity
var world: World
var difficulty := "normal"

var state := State.SEARCH
var last_seen := Vector3.ZERO
var last_seen_t := -1e9
var reaction_until := 0.0
var strafe_dir := 1.0
var strafe_t := 0.0
var wp_index := 0
var aim_error_offset := Vector3.ZERO
var aim_error_t := 0.0
var _params: Dictionary

func setup(hero_: CharacterEntity, target_: CharacterEntity, world_: World, diff: String = "normal") -> void:
	hero = hero_
	target = target_
	world = world_
	difficulty = diff
	_params = DIFFICULTIES.get(diff, DIFFICULTIES["normal"])
	hero.controller = self
	wp_index = randi() % 4

const WAYPOINTS := [
	Vector3(-10, 0.9, -10), Vector3(10, 0.9, 8), Vector3(8, 0.9, -12), Vector3(-8, 0.9, 10),
]

func step(world_: World, dt: float) -> void:
	world = world_
	if not hero.alive:
		hero.move_input = Vector2.ZERO
		hero.want_fire = false
		return
	_perception(dt)
	_decision(dt)
	_execution(dt)

func _perception(dt: float) -> void:
	var seen := false
	if target.alive:
		var hp := hero.head_pos()
		var tp := target.head_pos()
		var dist := hp.distance_to(tp)
		if dist < 60.0:
			var q := PhysicsRayQueryParameters3D.create(hp, tp,
					CharacterEntity.LAYER_WORLD | CharacterEntity.LAYER_BODY | CharacterEntity.LAYER_HEAD)
			q.exclude = [hero.get_rid(), target.get_rid()]
			var res := hero.get_world_3d().get_direct_space_state().intersect_ray(q)
			if res.is_empty():
				seen = true  # clear line of sight (target RIDs excluded)
	if seen:
		last_seen = target.head_pos()
		last_seen_t = world.time
	else:
		pass
	_los_seen = seen
	aim_error_t -= dt
	if aim_error_t <= 0.0:
		aim_error_t = 0.2
		aim_error_offset = Vector3(randf_range(-1, 1), randf_range(-0.3, 0.7), randf_range(-1, 1)) * deg_to_rad(float(_params.aim_error_deg)) * 10.0

var _los_seen := false

func _decision(_dt: float) -> void:
	var since_seen := world.time - last_seen_t
	var hp_ratio := hero.hp / hero.max_hp
	if not target.alive:
		state = State.SEARCH
		return
	if hp_ratio < float(_params.retreat_hp) and _los_seen:
		state = State.RETREAT
		return
	if _los_seen and since_seen < 0.5:
		if state != State.ENGAGE:
			state = State.ENGAGE
			reaction_until = world.time + float(_params.reaction)
	elif state == State.ENGAGE and since_seen > 1.2:
		state = State.SEARCH

func _execution(dt: float) -> void:
	var hp := hero.global_position
	match state:
		State.SEARCH:
			var wp: Vector3 = WAYPOINTS[wp_index % WAYPOINTS.size()]
			var d := wp - hp
			d.y = 0.0
			if d.length() < 1.5:
				wp_index += 1
				hero.move_input = Vector2.ZERO
			else:
				hero.move_input = _to_local(d.normalized())
			hero.want_fire = false
		State.ENGAGE:
			var to_t := (target.global_position - hp)
			to_t.y = 0.0
			var dist := to_t.length()
			var dir := to_t / maxf(dist, 0.001)
			var fwd := hero.global_transform.basis * CharacterEntity.FWD
			var right := hero.global_transform.basis * Vector3.RIGHT
			strafe_t -= dt
			if strafe_t <= 0.0:
				strafe_dir = -strafe_dir
				strafe_t = randf_range(float(_params.strafe_min), float(_params.strafe_max))
			var desire := Vector3.ZERO
			if dist > float(_params.ideal_range) + 3.0:
				desire += dir
			elif dist < float(_params.ideal_range) - 3.0:
				desire -= dir * 0.6
			desire += (fwd.cross(Vector3.UP)) * strafe_dir * 0.9
			desire = desire.normalized()
			hero.move_input = _to_local(desire)
			hero.aim_target = last_seen + aim_error_offset
			hero.want_fire = world.time >= reaction_until and _los_seen and dist < float(_params.engage_range)
		State.RETREAT:
			var pts: Array = world.spawn_points.get(hero.team, [hero.death_pos])
			var home: Vector3 = pts[0]
			var d := (home - hp)
			d.y = 0.0
			hero.move_input = _to_local(d.normalized()) if d.length() > 1.0 else Vector2.ZERO
			hero.aim_target = last_seen
			hero.want_fire = _los_seen and world.time >= reaction_until
		_:
			hero.want_fire = false

# Convert a world-space direction into the hero's local move_input (x=right, y=forward).
func _to_local(dir: Vector3) -> Vector2:
	var basis := hero.global_transform.basis
	# Basis columns: x=right, z=forward (Godot 4 API; no .rows in 4.x)
	var fwd := Vector3(basis.z.x, 0, basis.z.z).normalized()
	var right := Vector3(basis.x.x, 0, basis.x.z).normalized()
	var v := Vector2(dir.dot(right), dir.dot(fwd))
	if v.length() > 1.0:
		v = v.normalized()
	return v
