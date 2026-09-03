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
## Hitscan pellets per shot (shotguns: 8; rifles: 1). Each pellet rolls spread.
@export var pellets := 1
## Phase 3 weapon framework: "hitscan" (instant ray) or "projectile" (stepped
## Projectile entity). Projectile tuning lives in the data-driven profile.
@export var mode := "hitscan"
@export var projectile_speed := 22.0
@export var projectile_range := 60.0
@export var projectile_slow_ratio := 0.0
@export var projectile_slow_duration := 0.0

## Fired by _fire on every shot (render-side listeners: recoil, SFX, VFX).
signal fired(shooter: CharacterEntity)

## Ability-driven multipliers, synced by the hero each tick (server-side).
var fire_rate_mult := 1.0
var damage_mult := 1.0
var spread_mult := 1.0
## Support rate boosts (Patch/Nimbus ults): synced by the hero each tick.
var rate_boost_mult := 1.0

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

## Instant refill (Patch's Field Resupply): cancel reload, full clip.
func start_refill() -> void:
	reloading = false
	_reload_t = 0.0
	ammo = clip_size
	_cd = 0.0

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
		_cd = 1.0 / (fire_rate * fire_rate_mult * rate_boost_mult)
		ammo -= 1
		shots_fired += 1
		if mode == "projectile":
			_fire_projectile(world, dir)
		else:
			_fire(world, dir)

func _fire_projectile(world: World, dir: Vector3) -> void:
	if _flash and _flash.visible == false:
		_flash.visible = true
		_flash.light_energy = 1.2
		world.schedule(world.time + 0.04, func() -> void:
			if _flash:
				_flash.visible = false)
	var origin := _owner.muzzle_pos()
	var d := _apply_spread(dir)
	var pr := Projectile.new()
	pr.name = "Proj_%d" % shots_fired
	pr.damage = damage * damage_mult
	pr.headshot_mult = headshot_mult
	pr.speed = projectile_speed
	pr.max_range = projectile_range
	pr.slow_ratio = projectile_slow_ratio
	pr.slow_duration = projectile_slow_duration
	pr.setup(world, _owner, d)
	pr.global_position = origin
	world.register_projectile(pr)
	world.emit_event("shot", {
		"shooter" = _owner, "from" = origin, "to" = origin + d * 4.0, "hit" = false,
	})
	fired.emit(_owner)

func _fire(world: World, dir: Vector3) -> void:
	if _flash and _flash.visible == false:
		_flash.visible = true
		_flash.light_energy = 2.0
		world.schedule(world.time + 0.05, func() -> void:
			if _flash:
				_flash.visible = false)
	var origin := _owner.muzzle_pos()
	var any_hit := false
	var first_end := origin + dir * max_range
	for i in pellets:
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
			any_hit = true
		if i == 0:
			first_end = end
	world.emit_event("shot", {
		"shooter" = _owner, "from" = origin, "to" = first_end,
		"hit" = any_hit,
	})
	fired.emit(_owner)

func _apply_spread(dir: Vector3) -> Vector3:
	var base := dir.normalized()
	var err := deg_to_rad(spread_deg * spread_mult)
	var v := base
	v += (Vector3.RIGHT * randf_range(-err, err) + Vector3.UP * randf_range(-err, err))
	return v.normalized()
