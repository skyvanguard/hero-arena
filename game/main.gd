extends Node
## Match bootstrap: builds world, arena, player, bot, input, UI.
## Rendering-side nodes are only created when not headless, so the same
## scene tree runs in CI (ARCHITECTURE.md: gameplay/ must run headless).

const FIXED_DT := 1.0 / 60.0

var world: World
var player: Hero
var bot: Hero
var _accum := 0.0

func _ready() -> void:
	randomize()
	world = World.new()
	world.name = "World"
	add_child(world)

	var arena := Arena.build(world)
	add_child(arena)

	player = HeroFactory.create(0, true, Color(0.35, 0.7, 1.0))
	add_child(player)
	world.register_character(player)

	bot = HeroFactory.create(1, false, Color(1.0, 0.4, 0.3))
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

func _physics_process(delta: float) -> void:
	_accum += delta
	var steps := 0
	while _accum >= FIXED_DT and steps < 4:
		world.step(FIXED_DT)
		_accum -= FIXED_DT
		steps += 1
