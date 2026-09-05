class_name CharacterEntity
extends CharacterBody3D
## Base character: movement (coyote + jump buffer), HP with regen-to-cap
## (T3 pattern), protection, death/respawn (world-authoritative).
## Controllers (player input or BotController) fill move_input/aim/want_fire
## before physics each tick — bots and humans share this interface.

const GRAVITY := 10.0
const LAYER_WORLD := 1
const LAYER_BODY := 2
const LAYER_HEAD := 4

## Body/head hit geometry (single source of truth): the capsule collider is
## centered on the character origin (capsule h 1.8, r 0.4 -> cylinder core
## +-0.5 around the origin) and the head sensor is a sphere r 0.28 at +1.6.
## HeroFactory builds the colliders from these; World's lag-comp ray tests
## the same shapes analytically (past poses), so both must agree.
const BODY_RADIUS := 0.4
const BODY_HALF_H := 0.5
const HEAD_RADIUS := 0.28
const HEAD_OFFSET := 1.6

## All of this character's own physics RIDs (body + head sensor). Required
## because the head sensor is a nested StaticBody3D: excluding only the
## body RID still lets rays self-hit the sensor (Phase 4 duel probe — the
## bot's own LOS ray started inside its head and saw nothing).
func own_rids() -> Array:
	var rids: Array = [get_rid()]
	var hs: Node = get_node_or_null("Head/HeadSensor")
	if hs is PhysicsBody3D:
		rids.append((hs as PhysicsBody3D).get_rid())
	return rids

## Headshot detection: walk up from the hit collider; a collider whose
## ancestor chain contains the "HeadSensor" body marks a head hit. (The
## sensor used to be an Area3D, which intersect_ray does not report in
## 4.7 — headshots silently never registered; see hero_factory.)
static func hit_is_head(collider: Object) -> bool:
	var n: Node = collider as Node
	while n != null:
		if n.name == "HeadSensor":
			return true
		n = n.get_parent()
	return false
# Godot 4.7 flipped the forward axis: Vector3.FORWARD is now (0,0,-1).
# Project convention: characters face their local +Z axis (see face_toward),
# camera view direction is the local -Z axis (== Vector3.FORWARD in 4.7).
const FWD := Vector3.BACK
const CAM_FWD := Vector3.FORWARD

signal died(ch: CharacterEntity, killer: CharacterEntity)

@export var display_name := "Hero"
@export var team := 0
@export var max_hp := 100.0
@export var base_speed := 6.0
@export var jump_velocity := 5.8
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.15
@export var respawn_time := 6.0
var _base_max_hp := 100.0  ## captured in _ready (pre-perk), D25
@export var spawn_protection := 2.0
@export var regen_delay := 3.0
@export var regen_rate := 12.0
@export var regen_cap_ratio := 0.5

var hp := 100.0
var alive := true
var death_pos := Vector3.ZERO
## Match stats (D19 results/progression): accumulated server-side only.
var kills := 0
var deaths := 0
var damage_dealt := 0.0
var world_ref: World = null
var controller: Node = null          # BotController or player-input node
var is_player := false
var ability: AbilityComponent = null # Phase 2 kit (hero data driven)

# Controller -> character interface (filled each tick before physics):
var move_input := Vector2.ZERO
var aim_target := Vector3.ZERO       # bots aim at this world position
var want_fire := false
var _jump_buffered := false

var _coyote := 0.0
var _since_damage := 1e9
var protected_until := 0.0
## World-clock time of last death (HUD respawn countdown; set by world.kill).
var death_time := 0.0
## D25 perks (Phase 7): matched multiplier table applied by PerkSystem on
## pick (damage / fire_rate / cooldown / speed / max_hp / regen / charge /
## spread). 1.0 = no effect; read via perk_mult() from the modifier
## pipeline (AbilityComponent, regen, physics).
var perk_mults: Dictionary = {}
func perk_mult(k: String, dflt: float = 1.0) -> float:
	return float(perk_mults.get(k, dflt))
func refresh_max_hp() -> void:
	max_hp = _base_max_hp * perk_mult("max_hp")
var slow_ratio := 0.0     ## strongest active slow (0..1), decays via slow_until
var slow_until := 0.0
## Server-measured input age for this character (MatchServer, clamped to the
## world's lag-comp window): World.hitscan rewinds OTHER characters to this
## character's perception time when validating its shots.
var net_comp_delay := 0.0
# Support-side boosts (data-driven): strongest active wins, like slow.
var speed_boost_ratio := 0.0
var speed_boost_until := 0.0
var rate_boost_ratio := 0.0
var rate_boost_until := 0.0
var dash_lock_until := 0.0  ## while active, movement blend is skipped (dash impulse holds)
var _head_marker: Marker3D
var _muzzle: Marker3D
var _body_visible := true

func _ready() -> void:
	_base_max_hp = max_hp
	hp = max_hp
	for c in get_children():
		if c is Marker3D:
			if c.name == "HeadMarker":
				_head_marker = c
			elif c.name == "Muzzle":
				_muzzle = c

func head_pos() -> Vector3:
	if _head_marker:
		return _head_marker.global_position
	return global_position + Vector3.UP * 1.6

func muzzle_pos() -> Vector3:
	if _muzzle:
		return _muzzle.global_position
	return global_position + Vector3.UP * 1.25

func step(world: World, dt: float) -> void:
	world_ref = world
	if not alive:
		velocity = Vector3.ZERO
		return
	if controller != null and is_instance_valid(controller):
		controller.step(world, dt)
	elif not is_player:
		# No active controller: no stale input may persist (server authority).
		move_input = Vector2.ZERO
		want_fire = false
	if ability != null:
		ability.step(world, dt)
	if world.time >= slow_until:
		slow_ratio = 0.0
	if world.time >= speed_boost_until:
		speed_boost_ratio = 0.0
	if world.time >= rate_boost_until:
		rate_boost_ratio = 0.0
	_update_timers(world, dt)
	_update_regen(world, dt)
	_update_physics(world, dt)

func apply_slow(world: World, ratio: float, duration: float) -> void:
	var new_ratio := ratio if world.time >= slow_until else maxf(slow_ratio, ratio)
	slow_ratio = new_ratio
	slow_until = maxf(slow_until, world.time + duration)

func apply_speed_boost(world: World, ratio: float, duration: float) -> void:
	speed_boost_ratio = ratio if world.time >= speed_boost_until else maxf(speed_boost_ratio, ratio)
	speed_boost_until = maxf(speed_boost_until, world.time + duration)

func apply_rate_boost(world: World, ratio: float, duration: float) -> void:
	rate_boost_ratio = ratio if world.time >= rate_boost_until else maxf(rate_boost_ratio, ratio)
	rate_boost_until = maxf(rate_boost_until, world.time + duration)

func _update_timers(world: World, dt: float) -> void:
	_since_damage += dt
	_coyote = _coyote - dt if not is_on_floor() else coyote_time
	if _jump_buffered and (is_on_floor() or _coyote > 0.0):
		velocity.y = jump_velocity
		_jump_buffered = false
		world_ref.emit_event("jump", {"ch" = self})
	elif _jump_buffered:
		_jump_buffered = false

func buffer_jump() -> void:
	_jump_buffered = true

func _update_regen(world: World, dt: float) -> void:
	if not alive or hp <= 0.0:
		return
	var cap := max_hp * regen_cap_ratio
	if _since_damage > regen_delay and hp < cap:
		hp = minf(hp + regen_rate * perk_mult("regen") * dt, cap)
		emit_hp()

func _update_physics(world: World, dt: float) -> void:
	var vel := velocity
	if not is_on_floor():
		vel.y -= GRAVITY * dt
	var fwd := global_transform.basis * FWD
	var right := global_transform.basis * Vector3.RIGHT
	var spd := base_speed
	if ability != null:
		spd *= ability.speed_mult()
	spd *= (1.0 - slow_ratio)
	spd *= (1.0 + speed_boost_ratio)
	var wish := (fwd * move_input.y + right * move_input.x) * spd
	var cur := Vector3(vel.x, 0.0, vel.z)
	var blend := 0.0 if world.time < dash_lock_until else (minf(1.0, 12.0 * dt) if is_on_floor() else minf(1.0, 5.0 * dt))
	cur = cur.lerp(wish, blend)
	vel.x = cur.x
	vel.z = cur.z
	velocity = vel
	move_and_slide()

## Direction the character aims its weapon/abilities at. Hero overrides with
## camera (player) or aim_target (bot) awareness. Base: local forward.
## Aim FROM head height, not the capsule origin: the ray flies out of the
## muzzle (~head height), so origin-based direction runs high over targets
## (the Phase 4 bot-duel probe caught this: rays passed 1.3 m over heads).
const AIM_HEIGHT := 1.25

func aim_direction() -> Vector3:
	if aim_target != Vector3.ZERO:
		var d := aim_target - (global_position + Vector3.UP * AIM_HEIGHT)
		if d.length_squared() > 0.001:
			return d.normalized()
	return (global_transform.basis * FWD).normalized()

func face_toward(target_pos: Vector3) -> void:
	var d := (target_pos - global_position)
	d.y = 0.0
	if d.length_squared() > 0.001:
		rotation.y = atan2(d.x, d.z)

func apply_damage(amount: float, source: CharacterEntity, is_head: bool,
		hit_pos: Vector3, prot: bool) -> void:
	if not alive:
		return
	# Passives may mitigate before the HP hit; ult charge tracks the final amount.
	var mitigated := amount * (ability.passive_damage_taken_mult() if ability != null else 1.0)
	if ability != null:
		ability.on_damage_taken(mitigated)
	hp -= mitigated
	_since_damage = 0.0
	if source != null and source != self:
		source.damage_dealt += mitigated  # D19: stats track the final amount
	world_ref.emit_event("hit", {
		"target" = self, "source" = source, "amount" = mitigated, "raw" = amount,
		"is_head" = is_head, "pos" = hit_pos, "prot" = prot,
	})
	emit_hp()
	if hp <= 0.0:
		hp = 0.0
		died.emit(self, source)
		world_ref.kill(self, source, is_head)

func emit_hp() -> void:
	world_ref.emit_event("hp_changed", {"ch" = self, "hp" = hp, "max" = max_hp})

func hide_visual() -> void:
	_body_visible = false
	_set_visual_visible(false)

func show_visual() -> void:
	_body_visible = true
	_set_visual_visible(true)

func _set_visual_visible(v: bool) -> void:
	for n in get_children():
		if n is MeshInstance3D or n is Node3D:
			n.visible = v

func respawn(pos: Vector3, facing: Vector3) -> void:
	global_position = pos
	rotation.y = atan2(facing.x, facing.z)
	velocity = Vector3.ZERO
	hp = max_hp
	alive = true
	protected_until = world_ref.time + spawn_protection
	_since_damage = 1e9
	show_visual()
	emit_hp()
