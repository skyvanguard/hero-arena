class_name Weapon
extends Node
## Hitscan weapon. Server-authoritative damage: this runs in the sim (world.step),
## so in Phase 5 it is server code unchanged. Visuals are render-guarded.

@export var display_name := "Pistol"
@export var damage := 12.0
@export var headshot_mult := 2.5
@export var fire_rate := 8.0
@export var clip_size := 30
@export var reload_time := 1.8
@export var max_range := 120.0
@export var spread_deg := 0.5
@export var reserve_infinite := true

## Ability-driven multipliers, synced by the hero each tick (server-side).
var fire_rate_mult := 1.0
var damage_mult := 1.0
var spread_mult := 1.0

var ammo := 0
var reloading := false
var shots_fired := 0
var _cd := 0.0
var _reload_t := 0.0
var _owner: CharacterEntity
var _flash: OmniLight3D

func setup(owner: CharacterEntity) -> void:
	_owner = owner
	ammo = clip_size
	for c in owner.get_children():
		if c is Node3D:
			for gc in c.get_children():
				if gc is OmniLight3D:
					_flash = gc

func ready() -> void:
	ammo = clip_size

func start_reload() -> void:
	if reloading or ammo >= clip_size:
		return
	reloading = true
	_reload_t = 0.0
	_owner.world_ref.emit_event("reload_start", {"ch" = _owner})

func update(world: World, dt: float, firing: bool, dir: Vector3) -> void:
	_cd = maxf(0.0, _cd - dt)
	if reloading:
		_reload_t += dt
		if _reload_t >= reload_time:
			reloading = false
			ammo = clip_size
			world.emit_event("reload_done", {"ch" = _owner})
	if firing and not reloading and _cd <= 0.0 and ammo > 0:
		_cd = 1.0 / (fire_rate * fire_rate_mult)
		ammo -= 1
		shots_fired += 1
		_fire(world, dir)

func _fire(world: World, dir: Vector3) -> void:
	if _flash and _flash.visible == false:
		_flash.visible = true
		_flash.light_energy = 2.0
		world.schedule(world.time + 0.05, func() -> void:
			if _flash:
				_flash.visible = false)
	var origin := _owner.muzzle_pos()
	var d := _apply_spread(dir)
	var to := origin + d * max_range
	var q := PhysicsRayQueryParameters3D.create(origin, to,
			CharacterEntity.LAYER_BODY | CharacterEntity.LAYER_HEAD)
	q.exclude = [_owner.get_rid()]
	var res := _owner.get_world_3d().get_direct_space_state().intersect_ray(q)
	var end := to
	var hit_ch: CharacterEntity = null
	var is_head := false
	if res:
		end = res.position
		var node: Node = res.collider
		while node != null and not (node is CharacterEntity):
			node = node.get_parent()
		if node is CharacterEntity:
			hit_ch = node
			if res.collider is Area3D:
				is_head = true
	if hit_ch != null and hit_ch != _owner:
		var dmg := damage * damage_mult * (headshot_mult if is_head else 1.0)
		world.damage(hit_ch, dmg, _owner, is_head, end)
		if _owner.ability != null:
			_owner.ability.on_damage_dealt(dmg)
			_owner.ability.on_hit_landed()
	world.emit_event("shot", {
		"shooter" = _owner, "from" = origin, "to" = end,
		"hit" = hit_ch != null,
	})

func _apply_spread(dir: Vector3) -> Vector3:
	var base := dir.normalized()
	var err := deg_to_rad(spread_deg * spread_mult)
	var v := base
	v += (Vector3.RIGHT * randf_range(-err, err) + Vector3.UP * randf_range(-err, err))
	return v.normalized()
