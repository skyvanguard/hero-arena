class_name Hero
extends CharacterEntity
## Playable character: unique weapon (Phase 1: one placeholder hero kit),
## TPS camera for players, shared controller interface for bots.

var weapon: Weapon
var camera_rig: Node3D = null
var _camera: Camera3D = null
var _cam_yaw := 0.0
var _cam_pitch := -0.18

# Cosmetic gun recoil (render-side; harmless headless).
const GUN_BASE_Z := 0.4
var _gun: Node3D = null
var _recoil := 0.0

const LOOK_SPEED := 0.16

func _ready() -> void:
	super._ready()
	if camera_rig != null:
		_camera = camera_rig.get_node("Camera3D")
		_camera.current = true
		_apply_camera()
	_gun = get_node_or_null("Gun")
	if _gun != null and weapon != null:
		weapon.fired.connect(_on_weapon_fired)

func _on_weapon_fired(_shooter: CharacterEntity) -> void:
	# Recoil kick: gun slides back and tilts up; decays in step().
	_recoil = minf(_recoil + 0.05, 0.16)

func _apply_camera() -> void:
	if camera_rig == null:
		return
	camera_rig.rotation.y = _cam_yaw
	_camera.rotation.x = _cam_pitch

func step(world: World, dt: float) -> void:
	if not alive:
		super.step(world, dt)
		return
	# Player input binding (desktop or touch) via the shared Controls contract.
	if is_player:
		move_input = Controls.move
		if Controls.consume_jump():
			buffer_jump()
		if Controls.consume_reload():
			weapon.start_reload()
		if Controls.consume_ability1() and ability != null:
			ability.cast(0)
		if Controls.consume_ability2() and ability != null:
			ability.cast(1)
		if Controls.consume_ultimate() and ability != null:
			ability.activate_ult()
		if camera_rig != null:
			var aim: Vector2
			if Controls.aim != Vector2.ZERO:
				aim = Controls.consume_aim()
			else:
				aim = Input.get_last_mouse_velocity() * LOOK_SPEED
			_cam_yaw -= aim.x
			_cam_pitch = clampf(_cam_pitch - aim.y, -1.25, 0.9)
			_apply_camera()
		want_fire = Controls.fire
	# Timers, regen, movement, physics — same path for humans and bots.
	super.step(world, dt)
	_update_recoil(dt)
	_sync_ability_mults()
	if is_player:
		var cf := _camera_forward()
		weapon.update(world, dt, want_fire, cf)
		face_toward(global_position + cf)
	else:
		# Bot path: controller sets move_input / aim_target / want_fire.
		if want_fire:
			var dir := (aim_target - muzzle_pos()).normalized()
			weapon.update(world, dt, true, dir)
			face_toward(aim_target)

func _update_recoil(dt: float) -> void:
	if _gun == null:
		return
	if _recoil > 0.0:
		_recoil = maxf(_recoil - dt * 0.55, 0.0)
	_gun.position.z = GUN_BASE_Z - _recoil
	_gun.rotation.x = -_recoil * 0.7

func _sync_ability_mults() -> void:
	var rate_boost := 1.0 + rate_boost_ratio
	if ability != null:
		weapon.fire_rate_mult = ability.fire_rate_mult()
		weapon.damage_mult = ability.damage_mult()
		weapon.spread_mult = ability.spread_mult()
		weapon.rate_boost_mult = rate_boost * ability.passive_rate_mult()
	else:
		weapon.rate_boost_mult = rate_boost

func set_aim_pitch(p: float) -> void:
	_cam_pitch = p

func aim_direction() -> Vector3:
	if is_player:
		return _camera_forward().normalized()
	return super.aim_direction()

func _camera_forward() -> Vector3:
	# In Godot 4.7 the camera view direction equals basis * Vector3.FORWARD
	# (FORWARD is (0,0,-1) since 4.7).
	if _camera != null:
		return _camera.global_transform.basis * CharacterEntity.CAM_FWD
	return global_transform.basis * CharacterEntity.FWD

func hide_visual() -> void:
	super.hide_visual()
	if camera_rig != null:
		camera_rig.visible = false

func respawn(pos: Vector3, facing: Vector3) -> void:
	super.respawn(pos, facing)
	if camera_rig != null:
		camera_rig.visible = true
		_cam_yaw = atan2(facing.x, facing.z)
		_apply_camera()
