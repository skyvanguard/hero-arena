class_name BotPerception
extends Node
## Perception module (Phase 4) — what a bot *knows*. Server-side, headless.
## Difficulty gates the info (BotDifficulty): vision range/FOV cone, LOS,
## hearing radius (shot events), and how long a lost target stays 'known'.
## Composition: the BotController owns this node; the Decision module reads
## its output. Nothing here trusts the client — it reads the authoritative
## world only.

var hero: CharacterEntity = null
var world: World = null
var params: BotDifficulty = null

## ch -> {"pos": Vector3, "t": float} — most recent sighting.
var known: Dictionary = {}
var heard_pos := Vector3.ZERO
var heard_until := -1e9

func setup(hero_: CharacterEntity, world_: World, params_: BotDifficulty) -> void:
	hero = hero_
	world = world_
	params = params_
	if world_.world_event.is_connected(_on_event):
		world_.world_event.disconnect(_on_event)
	world_.world_event.connect(_on_event)

func _exit_tree() -> void:
	if world != null and world.world_event.is_connected(_on_event):
		world.world_event.disconnect(_on_event)

## Vision scan (called every tick by the controller).
func scan(world_: World) -> void:
	world = world_
	if hero == null or not hero.alive or params == null:
		return
	var head := hero.head_pos()
	var fwd := hero.global_transform.basis * CharacterEntity.FWD
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		fwd = Vector3.BACK  # degenerate basis: face world -Z
	fwd = fwd.normalized()
	var cos_half := cos(deg_to_rad(params.vision_fov_deg) * 0.5)
	for chx in world_.characters.duplicate():
		var ch: CharacterEntity = chx
		if ch == hero or not is_instance_valid(ch) or not ch.alive:
			continue
		if ch.team == hero.team:
			continue
		var to: Vector3 = ch.head_pos() - head
		var dist: float = to.length()
		if dist > params.vision_range:
			continue
		var dir: Vector3 = to / maxf(dist, 0.001)
		if fwd.dot(dir) < cos_half:
			continue
		if not _los(head, ch):
			continue
		known[ch] = {"pos": ch.head_pos(), "t": world_.time}
	# Prune long-forgotten entries (memory hygiene; freshness checked on read).
	for ch in known.keys():
		var info: Dictionary = known[ch]
		if world_.time - float(info.t) > params.lost_sight_timeout * 8.0:
			known.erase(ch)

## Hearing: enemy shots within hearing_range register a position + time.
func _on_event(name: String, data: Dictionary) -> void:
	if name != "shot" or world == null or hero == null or not hero.alive:
		return
	var shooter: CharacterEntity = data.get("shooter")
	if shooter == null or shooter == hero or not is_instance_valid(shooter):
		return
	if not shooter.alive or shooter.team == hero.team:
		return
	var d: float = shooter.global_position.distance_to(hero.global_position)
	if d <= params.hearing_range:
		heard_pos = shooter.global_position
		heard_until = world.time + 2.0

## True while the heard shot is still 'recent'.
func heard() -> bool:
	return world != null and world.time < heard_until

## Most recently seen living enemy (null when nothing is known).
func best_target() -> CharacterEntity:
	var best: CharacterEntity = null
	var best_t := -1e9
	for ch in known.keys():
		if not is_instance_valid(ch) or not ch.alive:
			continue
		var info: Dictionary = known[ch]
		if float(info.t) > best_t:
			best_t = float(info.t)
			best = ch
	return best

## Was ch seen within the lost-sight window (fresh target)?
func fresh(ch: CharacterEntity) -> bool:
	if ch == null or not known.has(ch) or world == null:
		return false
	var info: Dictionary = known[ch]
	return world.time - float(info.t) <= params.lost_sight_timeout

## Last known position of ch (falls back to current position if valid).
func last_known(ch: CharacterEntity) -> Vector3:
	if known.has(ch):
		var info: Dictionary = known[ch]
		return Vector3(info.get("pos", Vector3.ZERO))
	if is_instance_valid(ch):
		return ch.global_position
	return Vector3.ZERO

func _los(from: Vector3, ch: CharacterEntity) -> bool:
	var to := ch.head_pos()
	var q := PhysicsRayQueryParameters3D.create(from, to,
			CharacterEntity.LAYER_WORLD | CharacterEntity.LAYER_BODY | CharacterEntity.LAYER_HEAD)
	q.exclude = hero.own_rids() + ch.own_rids()
	var res := hero.get_world_3d().get_direct_space_state().intersect_ray(q)
	return res.is_empty()
