extends Node
## Match bootstrap: builds world, arena, player, bot, input, UI.
## Rendering-side nodes are only created when not headless, so the same
## scene tree runs in CI (ARCHITECTURE.md: gameplay/ must run headless).

const FIXED_DT := 1.0 / 60.0

var world: World
var player: Hero
var bot: Hero
var _accum := 0.0
var _hero_select: HeroSelect

func _ready() -> void:
	randomize()
	if DisplayServer.get_name() == "headless":
		_start_match(HeroRegistry.default_hero())
		return
	_hero_select = HeroSelect.new()
	add_child(_hero_select)
	_hero_select.hero_deployed.connect(_on_deploy)

func _on_deploy(hero_data: HeroData) -> void:
	if _hero_select != null:
		_hero_select.queue_free()
		_hero_select = null
	_start_match(hero_data)

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

func _physics_process(delta: float) -> void:
	if world == null:
		return
	_accum += delta
	var steps := 0
	while _accum >= FIXED_DT and steps < 4:
		world.step(FIXED_DT)
		_accum -= FIXED_DT
		steps += 1
