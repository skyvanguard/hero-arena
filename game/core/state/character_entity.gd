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
@export var spawn_protection := 2.0
@export var regen_delay := 3.0
@export var regen_rate := 12.0
@export var regen_cap_ratio := 0.5

var hp := 100.0
var alive := true
var death_pos := Vector3.ZERO
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
var slow_ratio := 0.0     ## strongest active slow (0..1), decays via slow_until
var slow_until := 0.0
var dash_lock_until := 0.0  ## while active, movement blend is skipped (dash impulse holds)
var _head_marker: Marker3D
var _muzzle: Marker3D
var _body_visible := true

func _ready() -> void:
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
	_update_timers(world, dt)
	_update_regen(world, dt)
	_update_physics(world, dt)

func apply_slow(world: World, ratio: float, duration: float) -> void:
	var new_ratio := ratio if world.time >= slow_until else maxf(slow_ratio, ratio)
	slow_ratio = new_ratio
	slow_until = maxf(slow_until, world.time + duration)

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
		hp = minf(hp + regen_rate * dt, cap)
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
func aim_direction() -> Vector3:
	if aim_target != Vector3.ZERO:
		var d := aim_target - global_position
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
	if ability != null:
		ability.on_damage_taken(amount)
	hp -= amount
	_since_damage = 0.0
	world_ref.emit_event("hit", {
		"target" = self, "source" = source, "amount" = amount,
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
