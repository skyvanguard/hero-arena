extends Node
## Match bootstrap: builds world, arena, player, bot, input, UI.
## Rendering-side nodes are only created when not headless, so the same
## scene tree runs in CI (ARCHITECTURE.md: gameplay/ must run headless).

const FIXED_DT := 1.0 / 60.0

var world: World
var player: Hero
var bot: Hero
var practice: PracticeManager = null
var _accum := 0.0
var _hero_select: HeroSelect
var _in_range := false

func _ready() -> void:
	randomize()
	if DisplayServer.get_name() == "headless":
		_start_match(HeroRegistry.default_hero())
		return
	_hero_select = HeroSelect.new()
	add_child(_hero_select)
	_hero_select.hero_deployed.connect(_on_deploy)
	_hero_select.range_deployed.connect(_on_range)

func _on_deploy(hero_data: HeroData) -> void:
	if _hero_select != null:
		_hero_select.queue_free()
		_hero_select = null
	_start_match(hero_data)

func _on_range(hero_data: HeroData) -> void:
	if _hero_select != null:
		_hero_select.queue_free()
		_hero_select = null
	_start_range(hero_data)

func _start_match(hero_data: HeroData) -> void:
	world = World.new()
	world.name = "World"
	add_child(world)

	var arena := Arena.build(world)
	add_child(arena)

	player = HeroFactory.create(0, true, hero_data.color, hero_data)
	add_child(player)
	world.register_character(player)

	var bot_hero: HeroData = HeroRegistry.default_hero()
	bot = HeroFactory.create(1, false, bot_hero.color, bot_hero)
	add_child(bot)
	world.register_character(bot)

	var bc := BotController.new()
	bot.add_child(bc)
	bc.setup(bot, player, world)

	if DisplayServer.get_name() != "headless":
		add_child(DesktopInput.new())
		var tc := TouchControls.new()
		add_child(tc)
		var perf := PerfProbe.new()
		perf.name = "PerfProbe"
		add_child(perf)
		perf.setup(world)
		var hud := HUD.new()
		add_child(hud)
		hud.setup(world, player)
		var fx := WorldFX.new()
		add_child(fx)
		fx.setup(world)
		var sfx := Sfx.new()
		add_child(sfx)
		sfx.setup(world, player)
		for p in sfx._players:
			p.bus = "Master"

func _start_range(hero_data: HeroData) -> void:
	_in_range = true
	world = World.new()
	world.name = "World"
	add_child(world)

	var range_root := PracticeRange.build(world)
	add_child(range_root)

	player = HeroFactory.create(0, true, hero_data.color, hero_data)
	player.position = PracticeRange.PLAYER_SPAWN
	player.rotation.y = 0.0
	player.set_aim_pitch(PracticeRange.initial_aim_pitch())
	add_child(player)
	world.register_character(player)

	practice = PracticeManager.new()
	practice.name = "PracticeManager"
	add_child(practice)
	practice.setup(world)

	# Dummies: real team-1 characters with no controller (authoritative sim).
	var dummy_colors := [Color(0.85, 0.55, 0.3), Color(0.85, 0.7, 0.3), Color(0.7, 0.8, 0.45)]
	var positions := PracticeRange.dummy_positions()
	var dummies: Array = []
	for i in positions.size():
		var d := HeroFactory.create(1, false, dummy_colors[i % dummy_colors.size()], null)
		d.position = positions[i]
		d.rotation.y = deg_to_rad(180.0)  # face back down the range toward the shooter
		add_child(d)
		world.register_character(d)
		practice.add_dummy(d)
		dummies.append(d)

	if DisplayServer.get_name() != "headless":
		add_child(DesktopInput.new())
		var tc := TouchControls.new()
		add_child(tc)
		var perf := PerfProbe.new()
		perf.name = "PerfProbe"
		add_child(perf)
		perf.setup(world)
		var fx := WorldFX.new()
		add_child(fx)
		fx.setup(world)
		var sfx := Sfx.new()
		add_child(sfx)
		sfx.setup(world, player)
		for p in sfx._players:
			p.bus = "Master"
		var hud := PracticeHUD.new()
		add_child(hud)
		hud.setup(practice, dummies)
		hud.reset_pressed.connect(func() -> void:
			for d in dummies:
				d.hp = d.max_hp
		)
		hud.back_pressed.connect(func() -> void: get_tree().reload_current_scene())

func _physics_process(delta: float) -> void:
	if world == null:
		return
	_accum += delta
	var steps := 0
	while _accum >= FIXED_DT and steps < 4:
		world.step(FIXED_DT)
		if practice != null:
			practice.tick(FIXED_DT)
		_accum -= FIXED_DT
		steps += 1
