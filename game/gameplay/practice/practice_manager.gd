class_name PracticeManager
extends Node
## Practice range logic (Phase 3) — server-side, headless-safe. Tracks the
## session timer, per-dummy damage, and resets dummies after a short grace
## period (a dummy that keeps taking damage stays down; one left alone
## resets). Dummies are real CharacterEntities (team 1, no controller), so
## the authoritative damage pipeline is exercised unchanged.

## Seconds after the last hit before a damaged dummy resets to full HP.
const RESET_GRACE := 2.0
## Practice targets are sponges by design (sustained fire practice).
const DUMMY_HP := 1000.0

var world: World
var elapsed := 0.0
var dummies: Array = []          # CharacterEntity (practice targets)
var _last_hit: Dictionary = {}   # CharacterEntity -> world.time of last hit
var _damage_taken: Dictionary = {}  # CharacterEntity -> cumulative damage this session

func setup(world_: World) -> void:
	world = world_
	world.world_event.connect(_on_event)

func add_dummy(dummy: CharacterEntity) -> void:
	dummy.max_hp = DUMMY_HP
	dummy.hp = DUMMY_HP
	dummies.append(dummy)
	_last_hit[dummy] = -999.0
	_damage_taken[dummy] = 0.0

func tick(dt: float) -> void:
	if world == null:
		return
	elapsed += dt
	# Reset any damaged dummy whose last hit is older than the grace window.
	for d in dummies:
		if d == null or not is_instance_valid(d):
			continue
		if d.hp >= d.max_hp:
			continue
		if world.time - float(_last_hit.get(d, -999.0)) >= RESET_GRACE:
			d.hp = d.max_hp
			world.emit_event("dummy_reset", {"ch" = d})

func total_damage_to_dummy(d: CharacterEntity) -> float:
	return float(_damage_taken.get(d, 0.0))

func session_damage() -> float:
	var t := 0.0
	for v in _damage_taken.values():
		t += float(v)
	return t

func _on_event(name: String, data: Dictionary) -> void:
	if name != "hit":
		return
	var t = data.get("target", null)
	if not (t in dummies):
		return
	_damage_taken[t] = float(_damage_taken.get(t, 0.0)) + float(data.get("amount", 0.0))
	_last_hit[t] = world.time
