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
var _timers: Array = []            # [{at: float, fn: Callable}]

func emit_event(name: String, data: Dictionary) -> void:
	world_event.emit(name, data)

func setup_spawn(team: int, points: Array[Vector3]) -> void:
	spawn_points[team] = points

func register_character(ch: CharacterEntity) -> void:
	ch.world_ref = self
	characters.append(ch)

func unregister_character(ch: CharacterEntity) -> void:
	characters.erase(ch)

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
		# Bound callables of freed nodes become null (heroes freed mid-match
		# can leave pending timers: respawn schedules, flash fades, dashes).
		if fn.is_valid():
			fn.call()
	for ch in characters:
		ch.step(self, dt)
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
	schedule(time + target.respawn_time, _make_respawn(target))
	emit_event("kill", {
		"killer" = _name_of(source),
		"victim" = _name_of(target),
		"killer_team" = source.team if source != null else -1,
		"victim_team" = target.team,
		"headshot" = is_head,
	})
	target.hide_visual()

func _make_respawn(target: CharacterEntity) -> Callable:
	return func() -> void: _respawn(target)

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
	emit_event("respawn", {"name" = _name_of(target), "team" = target.team})

func _name_of(ch: CharacterEntity) -> String:
	if ch == null:
		return "World"
	return ch.display_name
