extends Node
## Dedicated headless match server scene (Phase 5): same codebase, 60 Hz
## authoritative World, ENet transport. Run:
##   godot --headless --path game res://net/server.tscn -- --port=7777
## Bot fill: both teams pre-spawned at MatchConfig.team_size; a human join
## takes the last bot's spot (MatchServer._on_hello).
const FIXED_DT := 1.0 / 60.0

var world: World
var net: MatchServer
var _accum := 0.0

func _ready() -> void:
	randomize()
	var port := MatchConfig.net_port
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.substr(7))
	var size := clampi(MatchConfig.team_size, 1, 6)
	world = World.new()
	world.name = "World"
	world.target_score = MatchConfig.target_score
	world.match_duration = MatchConfig.match_duration
	add_child(world)
	var arena := Arena.build(world)
	add_child(arena)
	net = MatchServer.new()
	add_child(net)
	net.setup(world, port, size)
	_fill_teams(size)

func _fill_teams(size: int) -> void:
	# Same roster variety as the offline match (main.gd): shuffled heroes.
	var roster: Array = HeroRegistry.HEROES.duplicate()
	roster.shuffle()
	var rix := 0
	for team in 2:
		var pts: Array = world.spawn_points.get(team, [])
		for i in size:
			if pts.size() <= i:
				break
			var data: HeroData = roster[rix % roster.size()]
			rix += 1
			net.spawn_bot(team, data, pts[i])

func _physics_process(delta: float) -> void:
	_accum += delta
	var steps := 0
	while _accum >= FIXED_DT and steps < 4:
		world.step(FIXED_DT)
		_accum -= FIXED_DT
		steps += 1
	net.tick(delta)
