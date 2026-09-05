class_name World
extends Node
## Fixed-timestep authoritative simulation (Phase 1: single-process local match.
## Phase 5 splits this into the dedicated server; this class keeps the same API).
## Emits game-meaningful events for clients / HUD / tests.

signal world_event(name: String, data: Dictionary)

var time := 0.0
var characters: Array[CharacterEntity] = []
var projectiles: Array[Projectile] = []
var zones: Array[ZoneEntity] = []
var spawn_points: Dictionary = {}  # team(int) -> Array[Vector3]
var score: Dictionary = {0: 0, 1: 0}
## TDM end condition (directive §6: 3–8 min matches). Set from MatchConfig by
## the match host; first team to target_score wins, else higher score at
## match_duration (draw if equal). Emitted once via "match_over".
var target_score := 15
var match_duration := 300.0
var match_over := false
var winner := -1  # 0 / 1 / -1 (draw or undecided)
## Mode framework v1 (Phase 6, D16): the match's rules as a data resource.
## null = built-in TDM legacy path (pre-framework matches/suites unchanged).
## The host assigns it (ModeRegistry.get_mode(MatchConfig.mode_id)) before
## the first step; Control additionally needs control_point set.
var mode: Mode = null
## Control objective state (mode == ControlMode): control_active = the
## match runs a point (v1 fixed at control_point, the arena center); owner
## (-1 neutral / 0 / 1), 0..1 progress for progress_team, and per-side
## capture counts (the HUD score in control).
var control_active := false
var control_point: Vector3 = Vector3.ZERO
var control_owner: int = -1
var control_progress: float = 0.0
var control_progress_team: int = -1
var control_score: Dictionary = {0: 0, 1: 0}
## Capture / CTF objective state (mode == CaptureMode, D17): fixed bases per
## team, current flag positions, and the carrier (CharacterEntity, null =
## at base or dropped) of each flag; per-side capture counts = the HUD score.
var flag_bases: Dictionary = {0: Vector3.ZERO, 1: Vector3.ZERO}
var flags: Dictionary = {0: Vector3.ZERO, 1: Vector3.ZERO}
var flag_carrier: Dictionary = {0: null, 1: null}
var captures: Dictionary = {0: 0, 1: 0}
## Escort objective state (mode == EscortMode, D17): the payload's x along
## the central lane (z fixed by the mode), its current speed, and the lane
## endpoints (start = attacker side, goal = defender side).
var payload_start_x := 16.0
var payload_goal_x := -16.0
var payload_pos := 16.0
var payload_speed := 0.0
## Lag compensation (Phase 5): max rewind (s) for hitscan validation. A
## shooter's measured input age (CharacterEntity.net_comp_delay, set by the
## MatchServer from the client's server-time estimate) is clamped to this;
## targets are rewound through _history to the shooter's perception time.
var lag_comp_window := 0.2
var _timers: Array = []            # [{at: float, fn: Callable}]
var _history: Dictionary = {}      # ch -> Array[[pos: Vector3, rot_y: float]] (60 Hz tail)

func emit_event(name: String, data: Dictionary) -> void:
	world_event.emit(name, data)

## In-place match reset (Phase 5 lifecycle, round 28): fresh time/score/over
## state on the same world node (arena + spawn points persist). The caller
## frees characters/projectiles/zones first (node lifetime is the caller's)
## and clears MatchServer slot state; pending timers are dropped (their
## targets - freed characters - would be skipped by the validity guard,
## but a finished match's timers carry no meaning into the next one).
func reset() -> void:
	time = 0.0
	score = {0: 0, 1: 0}
	match_over = false
	winner = -1
	characters.clear()
	projectiles.clear()
	zones.clear()
	_timers.clear()
	_history.clear()
	# Objective state (D14 in-place reset must clear it; the Mode instance
	# persists - it is config, its per-match state lives here).
	control_owner = -1
	control_progress = 0.0
	control_progress_team = -1
	control_score = {0: 0, 1: 0}
	# Capture / Escort objective state (same in-place-reset rule).
	flags = {0: flag_bases.get(0, Vector3.ZERO), 1: flag_bases.get(1, Vector3.ZERO)}
	flag_carrier = {0: null, 1: null}
	captures = {0: 0, 1: 0}
	payload_pos = payload_start_x
	payload_speed = 0.0

func setup_spawn(team: int, points: Array[Vector3]) -> void:
	spawn_points[team] = points

func register_character(ch: CharacterEntity) -> void:
	ch.world_ref = self
	characters.append(ch)

func unregister_character(ch: CharacterEntity) -> void:
	characters.erase(ch)
	_history.erase(ch)

func register_projectile(p: Projectile) -> void:
	add_child(p)
	p.world_ref = self
	projectiles.append(p)

func register_zone(z: ZoneEntity) -> void:
	add_child(z)
	z.world_ref = self
	zones.append(z)

## Authoritative heal (supports, D7): capped at max_hp, event for HUD/VFX.
func heal(target: CharacterEntity, amount: float, source: CharacterEntity) -> void:
	if not target.alive:
		return
	var healed := minf(amount, target.max_hp - target.hp)
	if healed <= 0.0:
		return
	target.hp += healed
	if source != null and source.ability != null:
		source.ability.on_heal_dealt(healed)
	emit_event("heal", {"target" = target, "source" = source, "amount" = healed, "pos" = target.global_position})

func schedule(at_time: float, fn: Callable) -> void:
	_timers.append({at = at_time, fn = fn})

func step(dt: float) -> void:
	if match_over:
		# Match finished: freeze the sim (score/respawns stop, the results
		# overlay owns the screen until the player returns to select).
		return
	time += dt
	var due: Array[Callable] = []
	var keep: Array = []
	for t in _timers:
		if time >= float(t.at):
			due.append(t.fn)
		else:
			keep.append(t)
	_timers = keep
	for fn in due:
		# Callables of freed nodes must not fire. is_valid() catches bound
		# methods and (in 4.7) instance lambdas whose owner was freed; the
		# get_object() check additionally catches the mid-frame case where a
		# character is freed (e.g. a yielding bot, immediate free during a
		# tick) before the physics flush and the lambda still reports valid
		# while its captured/self instance is gone.
		if not fn.is_valid():
			continue
		var obj = fn.get_object()
		if obj != null and obj != self and not is_instance_valid(obj):
			continue
		fn.call()
	for ch in characters:
		ch.step(self, dt)
	_record_history()
	for pr in projectiles:
		pr.step(self, dt)
	var alive_pr: Array[Projectile] = []
	for pr in projectiles:
		if not pr.dead:
			alive_pr.append(pr)
	projectiles = alive_pr
	for z in zones:
		z.step(self, dt)
	var alive_z: Array[ZoneEntity] = []
	for z in zones:
		if not z.dead:
			alive_z.append(z)
	zones = alive_z
	if mode != null:
		mode.step(self, dt)
	_check_match_over()

## Per-step pose tail for lag compensation (capped to the window).
func _record_history() -> void:
	var cap := maxi(2, int(lag_comp_window * 60.0) + 2)
	for ch in characters:
		var h: Array = _history.get(ch, [])
		h.append([ch.global_position, ch.rotation.y])
		if h.size() > cap:
			h.remove_at(0)
		_history[ch] = h

## Authoritative hitscan with lag compensation. Ray from origin along dir
## (normalized) within max_range: world geometry + characters, where enemy
## characters are ALSO tested analytically at past poses (their _history,
## rewound by source.net_comp_delay clamped to lag_comp_window). The current
## physics ray still provides the wall distance (shots never reach through
## geometry) and the no-delay result.
## Returns {pos: Vector3, ch: CharacterEntity or null, is_head: bool}.
func hitscan(origin: Vector3, dir: Vector3, source: CharacterEntity,
		max_range: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_range,
			CharacterEntity.LAYER_WORLD | CharacterEntity.LAYER_BODY | CharacterEntity.LAYER_HEAD)
	if source != null:
		q.exclude = source.own_rids()
	var res: Dictionary = get_tree().root.get_world_3d().get_direct_space_state().intersect_ray(q)
	var best_d := max_range
	var best_ch: CharacterEntity = null
	var best_head := false
	if res:
		best_d = (res.position - origin).length()
		var node: Node = res.collider
		while node != null and not (node is CharacterEntity):
			node = node.get_parent()
		if node is CharacterEntity:
			best_ch = node
			best_head = CharacterEntity.hit_is_head(res.collider)
	var delay := 0.0
	if source != null:
		delay = clampf(source.net_comp_delay, 0.0, lag_comp_window)
	if delay > 0.005 and best_ch != source:
		var n := mini(int(ceilf(delay * 60.0)), 120)
		for ch in characters:
			if ch == source or not ch.alive or int(ch.team) == int(source.team):
				continue
			var h: Array = _history.get(ch, [])
			if h.size() < 2:
				continue
			for i in mini(n, h.size() - 1):
				var pose: Vector3 = (h[h.size() - 1 - i] as Array)[0]
				var t: Array = _ray_character(origin, dir, pose, best_d)
				if t[0] < best_d:
					best_d = float(t[0])
					best_ch = ch
					best_head = bool(t[1])
	return {"pos": origin + dir * best_d, "ch": best_ch, "is_head": best_head}

## Ray vs one character's analytic body (3-sphere capsule approx) + head
## sphere at a past pose. Returns [t_along (INF = miss), is_head].
static func _ray_character(origin: Vector3, dir: Vector3, pose: Vector3,
		max_d: float) -> Array:
	var best := INF
	var head := false
	var up := Vector3.UP
	for k in [-CharacterEntity.BODY_HALF_H, 0.0, CharacterEntity.BODY_HALF_H]:
		var t: float = _ray_sphere(origin, dir, pose + up * k, CharacterEntity.BODY_RADIUS)
		if t < best:
			best = t
			head = false
	var th: float = _ray_sphere(origin, dir, pose + up * CharacterEntity.HEAD_OFFSET,
			CharacterEntity.HEAD_RADIUS)
	if th < best:
		best = th
		head = true
	if best > max_d:
		return [INF, false]
	return [best, head]

## Ray vs sphere: earliest t >= 0 along the (normalized) ray, INF on miss.
static func _ray_sphere(origin: Vector3, dir: Vector3, c: Vector3, r: float) -> float:
	var oc := origin - c
	var b := oc.dot(dir)
	var disc := b * b - (oc.length_squared() - r * r)
	if disc < 0.0:
		return INF
	var t := -b - sqrt(disc)
	return t if t >= 0.0 else INF

func _check_match_over() -> void:
	if match_over:
		return
	if mode != null:
		mode.check_over(self)
		return
	# Legacy built-in TDM (mode == null; TDMMode mirrors these rules).
	var s0: int = int(score.get(0, 0))
	var s1: int = int(score.get(1, 0))
	if s0 >= target_score or s1 >= target_score:
		_finish_match(0 if s0 > s1 else (1 if s1 > s0 else -1))
	elif time >= match_duration:
		_finish_match(0 if s0 > s1 else (1 if s1 > s0 else -1))

## Public finish (modes call this through the framework; the score in the
## event is the MODE'S score when a mode is set, kills otherwise).
func finish_match(w: int) -> void:
	_finish_match(w)

func _finish_match(w: int) -> void:
	match_over = true
	winner = w
	var sc: Array = [int(score.get(0, 0)), int(score.get(1, 0))]
	if mode != null:
		sc = mode.score_of(self)
	emit_event("match_over", {"winner" = w, "score" = sc, "time" = time})

func world_protected(target: CharacterEntity) -> bool:
	return time < target.protected_until

func damage(target: CharacterEntity, amount: float, source: CharacterEntity,
		is_head: bool, hit_pos: Vector3) -> void:
	if not target.alive:
		return
	var prot := world_protected(target)
	var final := amount * (0.5 if prot else 1.0)
	target.apply_damage(final, source, is_head, hit_pos, prot)

func kill(target: CharacterEntity, source: CharacterEntity, is_head: bool) -> void:
	if not target.alive:
		return
	target.alive = false
	target.death_pos = target.global_position
	target.death_time = time
	if source != null:
		score[source.team] = int(score.get(source.team, 0)) + 1
		if source.ability != null:
			source.ability.on_kill()
	# Respawn is authoritative and scheduled on the world clock (directive:
	# death/respawn is never client-trusted).
	schedule(time + target.respawn_time, _make_respawn(target.get_instance_id()))
	emit_event("kill", {
		"killer" = _name_of(source),
		"victim" = _name_of(target),
		"killer_team" = source.team if source != null else -1,
		"victim_team" = target.team,
		"headshot" = is_head,
	})
	if mode != null:
		mode.on_kill(self, source, target)
	target.hide_visual()

func _make_respawn(id: int) -> Callable:
	# Capture the instance id (a plain int), not the character: a freed
	# character (tests, a yielding bot) would otherwise trip "Lambda capture
	# was freed, passed null" when the respawn fires.
	return func() -> void: _respawn_id(id)

func _respawn_id(id: int) -> void:
	for ch in characters:
		if ch.get_instance_id() == id:
			_respawn(ch)
			return

func _respawn(target: CharacterEntity) -> void:
	# A freed character (tests free bots mid-match) can still have a pending
	# respawn lambda; is_instance_valid is the only safe check on it.
	if not is_instance_valid(target):
		return
	if target.alive:
		return
	var pts: Array = spawn_points.get(target.team, [])
	if pts.is_empty():
		pts = [Vector3.ZERO]
	var idx := int(randf() * pts.size()) % pts.size()
	var p: Vector3 = pts[idx]
	var facing := Vector3.FORWARD
	if pts.size() > 1:
		facing = (pts[(idx + 1) % pts.size()] - p).normalized()
	target.respawn(p, facing)
	emit_event("respawn", {"name" = _name_of(target), "team" = target.team,
		"ch" = target, "pos" = p})

func _name_of(ch: CharacterEntity) -> String:
	if ch == null:
		return "World"
	return ch.display_name
