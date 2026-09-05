class_name AbilityComponent
extends Node
## Data-driven ability execution (Phase 2) — server-authoritative.
## Cast/cooldown/charge math lives here (the sim); the kit comes from
## HeroData. Bots call the same cast()/activate_ult() APIs in Phase 4.

signal ability_cast(index: int, ability: AbilityData)
signal ability_failed(index: int)
signal ult_ready
signal ult_activated

const _DASH_GAP := 0.12
const _DASH_LOCK := 0.15

var hero_data: HeroData = null
var owner_ref: CharacterEntity = null
## Balance-layer charge scaling (content/balance/), set by HeroFactory.
var ult_charge_mult := 1.0

var charge: float = 0.0
var _cooldown_until: Array = []
var _ult_until := 0.0
var _ult_mults: Dictionary = {}
var _streak_hits := 0
var _streak_last := -999.0
var _field_until := 0.0
var _field_params: Dictionary = {}
var _zone_active := false

func setup(hero_data_: HeroData, owner_: CharacterEntity) -> void:
	hero_data = hero_data_
	owner_ref = owner_
	charge = 0.0
	_ult_until = 0.0
	_ult_mults = {}
	_streak_hits = 0
	_streak_last = -999.0
	_cooldown_until = []
	for i in hero_data.abilities.size():
		_cooldown_until.append(0.0)

func _world() -> World:
	return owner_ref.world_ref if owner_ref != null else null

func step(world: World, dt: float) -> void:
	if hero_data.passive != null and hero_data.passive.kind == PassiveData.Kind.HIT_STREAK:
		if _streak_hits > 0 and world.time - _streak_last > float(hero_data.passive.params.window):
			_streak_hits = 0
	# ZONE passive (Nimbus): fire-rate bonus while an enemy is in the aura.
	if hero_data.passive != null and hero_data.passive.kind == PassiveData.Kind.ZONE:
		var r: float = float(hero_data.passive.params.get("radius", 10.0))
		var seen := false
		for ch in world.characters:
			if ch.team != owner_ref.team and ch.alive and ch.global_position.distance_to(owner_ref.global_position) <= r:
				seen = true
				break
		_zone_active = seen
	# FIELD passive (Mira's Mending Presence): always-on tick-heal to allies.
	if hero_data.passive != null and hero_data.passive.kind == PassiveData.Kind.FIELD:
		var pr: float = float(hero_data.passive.params.get("radius", 7.0))
		var rate: float = float(hero_data.passive.params.get("heal_per_s", 0.0))
		for ch in world.characters:
			if ch.team == owner_ref.team and ch.alive and ch.global_position.distance_to(owner_ref.global_position) <= pr:
				world.heal(ch, rate * dt, owner_ref)
	# FIELD ability aura: tick heals + speed boosts to allies in radius.
	if world.time < _field_until:
		var fr: float = float(_field_params.get("radius", 6.0))
		var rate: float = float(_field_params.get("heal_per_s", 0.0))
		var sboost: float = float(_field_params.get("speed_boost", 0.0))
		for ch in world.characters:
			if ch.team == owner_ref.team and ch.alive and ch.global_position.distance_to(owner_ref.global_position) <= fr:
				if rate > 0.0:
					world.heal(ch, rate * dt, owner_ref)
				if sboost > 0.0:
					ch.apply_speed_boost(world, sboost, 0.1)

func can_cast(index: int) -> bool:
	var world := _world()
	if world == null or index < 0 or index >= hero_data.abilities.size():
		return false
	return world.time >= float(_cooldown_until[index])

func cast(index: int) -> bool:
	var world := _world()
	if not can_cast(index):
		ability_failed.emit(index)
		return false
	var ab: AbilityData = hero_data.abilities[index]
	_cooldown_until[index] = world.time + ab.cooldown * passive_cd_mult() * _pm("cooldown")
	ability_cast.emit(index, ab)
	world.emit_event("ability_cast", {"hero" = owner_ref, "id" = ab.id, "kind" = ab.kind})
	_execute(world, ab)
	return true

func _execute(world: World, ab: AbilityData) -> void:
	match ab.kind:
		AbilityData.Kind.DASH:
			_do_dash(world, ab.params)
		AbilityData.Kind.BURST:
			_do_burst(world, ab.params)
		AbilityData.Kind.BUFF:
			_do_buff(world, ab.params)
		AbilityData.Kind.HEAL:
			_do_heal(world, ab.params)
		AbilityData.Kind.FIELD:
			_do_field(world, ab.params)
		AbilityData.Kind.BOOST:
			_do_boost(world, ab.params)
		AbilityData.Kind.ZONE:
			_do_zone(world, ab.params)

func _do_dash(world: World, params: Dictionary) -> void:
	var dir: Vector3 = owner_ref.aim_direction().normalized()
	var count: int = int(params.count)
	for i in count:
		var speed: float = float(params.speed)
		if i == 0:
			_dash_once(world, dir * speed)
		else:
			world.schedule(world.time + float(i) * _DASH_GAP, func() -> void:
				_dash_once(world, dir * speed))

func _dash_once(world: World, impulse: Vector3) -> void:
	if not is_instance_valid(owner_ref):
		return
	owner_ref.velocity = Vector3(impulse.x, owner_ref.velocity.y, impulse.z)
	owner_ref.dash_lock_until = world.time + _DASH_LOCK

func _do_burst(world: World, params: Dictionary) -> void:
	var n: int = int(params.pellets)
	var cone: float = deg_to_rad(float(params.cone_deg))
	var from: Vector3 = owner_ref.muzzle_pos()
	var fwd: Vector3 = owner_ref.aim_direction().normalized()
	var right: Vector3 = Vector3.UP.cross(fwd).normalized()
	var dmg: float = float(params.damage)
	var range_: float = float(hero_data.weapon.max_range)
	for i in n:
		var t: float = 0.5 if n == 1 else (float(i) / float(n - 1)) - 0.5
		var d: Vector3 = (fwd + right * tan(t * cone)).normalized()
		_burst_pellet(world, from, d, dmg, range_, params)

func _burst_pellet(world: World, from: Vector3, d: Vector3, dmg: float, range_: float, params: Dictionary) -> void:
	if params.get("projectile", false):
		var pr := Projectile.new()
		pr.name = "BurstProj_%d" % int(world.time * 1000.0)
		pr.damage = dmg
		pr.headshot_mult = 1.5
		pr.speed = float(params.get("proj_speed", 20.0))
		pr.max_range = range_
		pr.slow_ratio = float(params.get("slow_ratio", 0.0))
		pr.slow_duration = float(params.get("slow_duration", 0.0))
		pr.setup(world, owner_ref, d)
		pr.global_position = from
		world.register_projectile(pr)
		return
	var to := from + d * range_
	var q := PhysicsRayQueryParameters3D.create(from, to,
			CharacterEntity.LAYER_BODY | CharacterEntity.LAYER_HEAD)
	q.exclude = [owner_ref.get_rid()]
	var res: Dictionary = owner_ref.get_world_3d().get_direct_space_state().intersect_ray(q)
	var end := to
	var hit_ch: CharacterEntity = null
	var is_head := false
	if not res.is_empty():
		end = res.position
		var node: Node = res.collider
		while node != null and not (node is CharacterEntity):
			node = node.get_parent()
		if node is CharacterEntity:
			hit_ch = node
			is_head = CharacterEntity.hit_is_head(res.collider)
	if hit_ch != null and hit_ch != owner_ref:
		world.damage(hit_ch, dmg, owner_ref, is_head, end)
		hit_ch.apply_slow(world, float(params.slow_ratio), float(params.slow_duration))
		on_damage_dealt(dmg)
	world.emit_event("shot", {"shooter" = owner_ref, "from" = from, "to" = end, "hit" = hit_ch != null})

func _do_buff(world: World, params: Dictionary) -> void:
	_ult_until = world.time + float(params.duration)
	_ult_mults = {
		"fire_rate_mult": float(params.fire_rate_mult),
		"speed_mult": float(params.speed_mult),
		"damage_mult": float(params.damage_mult),
		"spread_mult": float(params.spread_mult),
	}
	ult_activated.emit()

func _do_heal(world: World, params: Dictionary) -> void:
	var radius: float = float(params.radius)
	var amount: float = float(params.amount)
	for ch in world.characters:
		if ch.team == owner_ref.team and ch.alive and ch.global_position.distance_to(owner_ref.global_position) <= radius:
			world.heal(ch, amount, owner_ref)

func _do_field(world: World, params: Dictionary) -> void:
	_field_until = world.time + float(params.duration)
	_field_params = params

func _do_boost(world: World, params: Dictionary) -> void:
	var radius: float = float(params.get("radius", 0.0))
	var duration: float = float(params.get("duration", 0.0))
	var sboost: float = float(params.get("speed_boost", 0.0))
	var rboost: float = float(params.get("rate_boost", 0.0))
	if params.get("refill", false) and owner_ref.weapon != null:
		owner_ref.weapon.start_refill()
	var heal_amt: float = float(params.get("heal", 0.0))
	for ch in world.characters:
		if ch.team == owner_ref.team and ch.alive and ch.global_position.distance_to(owner_ref.global_position) <= radius:
			if sboost > 0.0:
				ch.apply_speed_boost(world, sboost, duration)
			if rboost > 0.0:
				ch.apply_rate_boost(world, rboost, duration)
			if heal_amt > 0.0:
				world.heal(ch, heal_amt, owner_ref)

func _do_zone(world: World, params: Dictionary) -> void:
	var dir: Vector3 = owner_ref.aim_direction().normalized()
	var dist: float = float(params.distance)
	var pos: Vector3 = owner_ref.global_position + Vector3(dir.x * dist, 0.0, dir.z * dist)
	pos.y = 0.1
	var z := ZoneEntity.new()
	z.name = "Zone_%d" % int(world.time * 100.0)
	z.color = hero_data.color if hero_data != null else Color(0.6, 0.5, 1.0)
	z.setup(world, owner_ref, pos, float(params.radius), float(params.duration), float(params.slow_ratio))
	world.register_zone(z)

## ---- multipliers consumed by the weapon/physics each tick ----
func is_ult_active() -> bool:
	var world := _world()
	return world != null and world.time < _ult_until

## D25: perk multiplier on the owner character (1.0 without a perk).
func _pm(k: String) -> float:
	return owner_ref.perk_mult(k) if owner_ref != null else 1.0

func fire_rate_mult() -> float:
	return _ult_mults.get("fire_rate_mult", 1.0) * _pm("fire_rate") if is_ult_active() else _pm("fire_rate")

func damage_mult() -> float:
	return _ult_mults.get("damage_mult", 1.0) * _pm("damage") if is_ult_active() else _pm("damage")

func speed_mult() -> float:
	return passive_speed_mult() * _ult_mults.get("speed_mult", 1.0) * _pm("speed") if is_ult_active() else passive_speed_mult() * _pm("speed")

func spread_mult() -> float:
	return passive_spread_mult() * _ult_mults.get("spread_mult", 1.0) * _pm("spread") if is_ult_active() else passive_spread_mult() * _pm("spread")

func passive_speed_mult() -> float:
	if hero_data.passive != null and hero_data.passive.kind == PassiveData.Kind.SPRINT:
		return float(hero_data.passive.params.get("speed_mult", 1.0))
	return _streak_mult("speed_mult")

func passive_spread_mult() -> float:
	return _streak_mult("spread_mult")

## Incoming damage multiplier from the passive (ARMOR: 1 - dmg_reduce).
func passive_damage_taken_mult() -> float:
	if hero_data.passive != null and hero_data.passive.kind == PassiveData.Kind.ARMOR:
		return 1.0 - float(hero_data.passive.params.get("dmg_reduce", 0.0))
	return 1.0

## Fire-rate multiplier from the passive (ZONE: while an enemy is in radius).
func passive_rate_mult() -> float:
	if hero_data.passive != null and hero_data.passive.kind == PassiveData.Kind.ZONE and _zone_active:
		return float(hero_data.passive.params.get("rate_mult", 1.0))
	return 1.0

## Cooldown multiplier from the passive (FLEX: cd_mult < 1).
func passive_cd_mult() -> float:
	if hero_data.passive != null and hero_data.passive.kind == PassiveData.Kind.FLEX:
		return float(hero_data.passive.params.get("cd_mult", 1.0))
	return 1.0

func _streak_mult(key: String) -> float:
	if hero_data.passive == null or hero_data.passive.kind != PassiveData.Kind.HIT_STREAK or _streak_hits <= 0:
		return 1.0
	var p: Dictionary = hero_data.passive.params
	var tier: int = clampi(int(_streak_hits / int(p.stack_hits)) - 1, 0, int(p.tiers.size()) - 1)
	return float(p.tiers[tier].get(key, 1.0))

## ---- combat-driven ultimate charge (D8) ----
func can_activate_ult() -> bool:
	return hero_data.ult != null and charge >= hero_data.ult_max

func activate_ult() -> bool:
	var world := _world()
	if world == null or not can_activate_ult():
		return false
	charge = 0.0
	ability_cast.emit(hero_data.abilities.size(), hero_data.ult)
	world.emit_event("ability_cast", {"hero" = owner_ref, "id" = hero_data.ult.id, "kind" = hero_data.ult.kind})
	_execute(world, hero_data.ult)
	return true

func on_damage_dealt(amount: float) -> void:
	_add_charge(amount * hero_data.charge_per_damage_dealt)

func on_heal_dealt(amount: float) -> void:
	_add_charge(amount * hero_data.charge_per_heal_dealt)

func on_damage_taken(amount: float) -> void:
	_add_charge(amount * hero_data.charge_per_damage_taken)

func on_kill() -> void:
	_add_charge(hero_data.charge_per_kill)

## Passive hit-streak: count a landed hit (weapon or burst).
func on_hit_landed() -> void:
	var world := _world()
	if world == null:
		return
	_streak_hits += 1
	_streak_last = world.time

func _add_charge(x: float) -> void:
	# D25: the charge perk scales every charge source (damage/heal/taken/kill).
	x *= _pm("charge")
	if x <= 0.0 or hero_data == null:
		return
	if charge >= hero_data.ult_max:
		return
	var before := charge
	charge = minf(charge + x * ult_charge_mult, hero_data.ult_max)
	if before < hero_data.ult_max and charge >= hero_data.ult_max:
		ult_ready.emit()
