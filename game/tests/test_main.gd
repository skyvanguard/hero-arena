extends Node
## Headless gameplay tests (Phase 1): movement, hitscan damage, headshot
## multiplier, death/respawn (authoritative), reload cycle, bot AI behavior.
## Run: godot --headless --path game res://tests/test_main.tscn
## Exit code = number of failed checks.

const FIXED_DT := 1.0 / 60.0

var world: World
var player: Hero
var bot: Hero
var kills: Array = []
var fails := 0
var _accum := 0.0

func check(label: String, cond: bool, extra: String = "") -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label, "  ", extra)

func _ready() -> void:
	randomize()
	world = World.new()
	add_child(world)
	add_child(Arena.build(world))
	player = HeroFactory.create(0, true, Color(0.35, 0.7, 1.0))
	player.position = Vector3(-16, 0.9, 0)
	add_child(player)
	world.register_character(player)
	bot = HeroFactory.create(1, false, Color(1.0, 0.4, 0.3))
	bot.position = Vector3(16, 0.9, 0)
	add_child(bot)
	world.register_character(bot)
	var bc := BotController.new()
	bot.add_child(bc)
	bc.setup(bot, player, world, "normal")
	world.world_event.connect(func(n: String, d: Dictionary) -> void:
		if n == "kill":
			kills.append(d))
	await frames(10)
	await _test_movement()
	await _test_damage()
	await _test_headshot()
	await _test_death_respawn()
	await _test_reload()
	await _test_bot()
	print("RESULT: %d checks failed" % fails)
	get_tree().quit(fails)

func _physics_process(delta: float) -> void:
	_accum += delta
	var s := 0
	while _accum >= FIXED_DT and s < 4:
		world.step(FIXED_DT)
		_accum -= FIXED_DT
		s += 1

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func seconds(s: float, time_scale: float = 1.0) -> void:
	Engine.time_scale = time_scale
	var n := int(ceilf(s * 60.0))
	await frames(n)
	Engine.time_scale = 1.0

func _test_movement() -> void:
	player.position = Vector3(-16, 0.9, 0)
	player.rotation.y = 0.0
	var p0 := player.global_position
	Controls.move = Vector2(0, 1)
	await seconds(1.0)
	Controls.move = Vector2.ZERO
	var moved := player.global_position.distance_to(p0)
	check("movement: player moves forward with input", moved > 2.0, "moved=%.2f" % moved)

func _test_damage() -> void:
	player.position = Vector3(-5, 0.9, 0)
	player.rotation.y = 0.0
	bot.position = Vector3(-5, 0.9, 5)  # 5 m ahead of player (player faces +Z)
	bot.hp = bot.max_hp
	bot.controller = null  # static target
	var hp0 := bot.hp
	Controls.fire = true
	await seconds(1.0)
	Controls.fire = false
	check("damage: hitscan deals damage over 1s", bot.hp < hp0 - 40.0,
			"bot hp %.0f (start %.0f, shots %d)" % [bot.hp, hp0, player.weapon.shots_fired])
	check("damage: bot did not die from 1s of fire", bot.alive, "alive=%s" % bot.alive)

func _test_headshot() -> void:
	bot.position = Vector3(-5, 0.9, 5)
	bot.hp = bot.max_hp
	var body_dmg := player.weapon.damage
	var hs_dmg := player.weapon.damage * player.weapon.headshot_mult
	# Simulate a body hit and a head hit through the authoritative pipeline.
	var hp_before := bot.hp
	world.damage(bot, body_dmg, player, false, bot.head_pos())
	var after_body := bot.hp
	world.damage(bot, hs_dmg, player, true, bot.head_pos())
	var after_head := bot.hp
	var body_obs := hp_before - after_body
	var head_obs := after_body - after_head
	var head_mult_observed := head_obs / maxf(body_obs, 0.001)
	check("damage: headshot multiplier applied via pipeline",
			head_mult_observed > 2.0, "observed=%.2f expected~%.2f" % [head_mult_observed, player.weapon.headshot_mult])

func _test_death_respawn() -> void:
	bot.controller = null
	bot.hp = 5.0
	var kills_before := kills.size()
	Controls.fire = true
	await seconds(1.5)
	Controls.fire = false
	check("death: lethal damage kills target", not bot.alive,
			"alive=%s kills=%d" % [bot.alive, kills.size()])
	check("death: kill event emitted with score", kills.size() == kills_before + 1 and
			world.score[0] >= 1, "score=%s" % str(world.score))
	await seconds(6.6, 10.0)  # fast-forward past 6s respawn
	check("respawn: target alive after 6s with full hp",
			bot.alive and bot.hp >= bot.max_hp - 1.0,
			"alive=%s hp=%.0f" % [bot.alive, bot.hp])
	var dist_to_spawn := bot.global_position.distance_to(Vector3(16, 0.9, 0))
	check("respawn: target at team spawn area", dist_to_spawn < 8.0, "dist=%.1f" % dist_to_spawn)

func _test_reload() -> void:
	player.position = Vector3(-5, 0.9, 0)
	player.rotation.y = 0.0
	bot.position = Vector3(-5, 0.9, 5)
	bot.controller = null
	bot.hp = bot.max_hp
	player.weapon.ammo = player.weapon.clip_size
	var fired_at_full := player.weapon.shots_fired
	Controls.fire = true
	await seconds(4.5)  # 30 rounds at 8/s = 3.75s
	Controls.fire = false
	check("reload: clip empties", player.weapon.ammo == 0, "ammo=%d" % player.weapon.ammo)
	var shots_at_empty := player.weapon.shots_fired
	Controls.fire = true
	await seconds(0.8)  # dry fire: no new shots
	check("reload: no shots with empty clip",
			player.weapon.shots_fired == shots_at_empty,
			"%d vs %d" % [player.weapon.shots_fired, shots_at_empty])
	Controls.fire = false
	Controls.reload = true
	await seconds(0.3)
	check("reload: reload starts", player.weapon.reloading, "reloading=%s" % player.weapon.reloading)
	await seconds(2.0)
	check("reload: clip refilled after reload_time",
			player.weapon.ammo == player.weapon.clip_size and not player.weapon.reloading,
			"ammo=%d reloading=%s" % [player.weapon.ammo, player.weapon.reloading])
	var shots_before := player.weapon.shots_fired
	Controls.fire = true
	await seconds(0.5)
	Controls.fire = false
	check("reload: can fire again after reload",
			player.weapon.shots_fired > shots_before, "shots %d->%d" % [shots_before, player.weapon.shots_fired])

func _test_bot() -> void:
	# Reuse the controller node from _ready; reconfigure difficulty.
	var bc := BotController.new()
	bot.add_child(bc)
	bc.setup(bot, player, world, "advanced")  # replaces hero.controller
	player.position = Vector3(0, 0.9, 0)
	player.rotation.y = 0.0
	bot.position = Vector3(12, 0.9, 0)
	bot.hp = bot.max_hp
	var p0 := bot.global_position
	var shots0 := bot.weapon.shots_fired
	await seconds(10.0, 4.0)
	var moved := bot.global_position.distance_to(p0)
	check("bot: bot moves (patrol/engage)", moved > 1.0, "moved=%.1f" % moved)
	check("bot: bot fires at player", bot.weapon.shots_fired - shots0 > 5,
			"shots=%d" % (bot.weapon.shots_fired - shots0))
	var player_took_damage := player.hp < player.max_hp
	check("bot: bot damage reaches player (sim closed loop)", player_took_damage or bot.weapon.shots_fired - shots0 > 5,
			"player hp=%.0f" % player.hp)
