extends Node
## Match bootstrap: builds world, arena, player, bot, input, UI.
## Rendering-side nodes are only created when not headless, so the same
## scene tree runs in CI (ARCHITECTURE.md: gameplay/ must run headless).

const FIXED_DT := 1.0 / 60.0

var world: World
var player: Hero
var bots: Array = []
var practice: PracticeManager = null
var _net_client: MatchClient = null
var _accum := 0.0
var _hero_select: HeroSelect
var _in_range := false
## Everything _start_match/_start_range add to the tree, so the match can be
## torn down cleanly when it ends (results overlay -> hero select).
var _match_nodes: Array = []
var _results: CanvasLayer = null

func _ready() -> void:
	randomize()
	if DisplayServer.get_name() == "headless":
		_start_match(HeroRegistry.default_hero())
		return
	_hero_select = HeroSelect.new()
	add_child(_hero_select)
	_hero_select.hero_deployed.connect(_on_deploy)
	_hero_select.range_deployed.connect(_on_range)
	_hero_select.net_deployed.connect(_on_net_deploy)

func _on_net_deploy(host_port: String, hero_data: HeroData) -> void:
	# LAN match (Phase 5 v1): the MatchClient owns the render side; main only
	# tracks teardown + the results overlay.
	if _hero_select != null:
		_hero_select.queue_free()
		_hero_select = null
	_net_client = MatchClient.new()
	add_child(_net_client)
	_match_nodes.append(_net_client)
	_net_client.ended.connect(_on_net_ended)
	_net_client.setup(host_port, hero_data)

func _on_net_ended(winner: int, score: Array, wtime: float, lost: bool, title: String) -> void:
	# Net titles are computed by the client from my_team (offline is always
	# team 0 and may still rely on the _show_results fallback).
	_show_results(winner, score, wtime, title)

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

## Offline match (directive §2 "zero humans"): player + bot fill on our side,
## full bot team on the other. Team size from MatchConfig (config, not code).
func _start_match(hero_data: HeroData) -> void:
	world = World.new()
	world.name = "World"
	world.target_score = MatchConfig.target_score
	world.match_duration = MatchConfig.match_duration
	world.world_event.connect(_on_world_event)
	add_child(world)
	_match_nodes.append(world)

	var arena := Arena.build(world)
	add_child(arena)
	_match_nodes.append(arena)

	var size: int = clampi(MatchConfig.team_size, 1, 6)
	var team0: Array = world.spawn_points.get(0, [])
	var team1: Array = world.spawn_points.get(1, [])

	# Player on our first spawn.
	player = HeroFactory.create(0, true, hero_data.color, hero_data)
	if team0.size() > 0:
		player.position = team0[0]
	add_child(player)
	_match_nodes.append(player)
	world.register_character(player)

	# Bot roster: shuffle the six heroes so each match team varies.
	var roster: Array = HeroRegistry.HEROES.duplicate()
	roster.shuffle()
	var rix := 0

	# Ally bots fill our remaining spawns (skip the player's hero for variety).
	for i in range(1, size):
		if team0.size() <= i:
			break
		var ally_data: HeroData = roster[rix % roster.size()]
		rix += 1
		if ally_data.id == hero_data.id and roster.size() > 1:
			ally_data = roster[(rix) % roster.size()]
			rix += 1
		_spawn_bot(0, ally_data, team0[i])

	# Enemy team: full bot squad on their spawns.
	for i in size:
		if team1.size() <= i:
			break
		var foe_data: HeroData = roster[rix % roster.size()]
		rix += 1
		_spawn_bot(1, foe_data, team1[i])

func _spawn_bot(team: int, hero_data: HeroData, spawn: Vector3) -> void:
	var b := HeroFactory.create(team, false, hero_data.color, hero_data)
	b.position = spawn
	# Face across the map toward the enemy side.
	b.rotation.y = PI if team == 0 else 0.0
	add_child(b)
	_match_nodes.append(b)
	world.register_character(b)
	var bc := BotController.new()
	b.add_child(bc)
	bc.setup(b, null, world, MatchConfig.difficulty)
	bots.append(b)

	if DisplayServer.get_name() != "headless":
		var di := DesktopInput.new()
		add_child(di)
		_match_nodes.append(di)
		var tc := TouchControls.new()
		add_child(tc)
		_match_nodes.append(tc)
		var perf := PerfProbe.new()
		perf.name = "PerfProbe"
		add_child(perf)
		_match_nodes.append(perf)
		perf.setup(world)
		if not bool(ProjectSettings.get_setting("debugperf/no_hud", false)):
			var hud := HUD.new()
			add_child(hud)
			_match_nodes.append(hud)
			hud.setup(world, player)
		if not bool(ProjectSettings.get_setting("debugperf/no_fx", false)):
			var fx := WorldFX.new()
			add_child(fx)
			_match_nodes.append(fx)
			fx.setup(world)
		if not bool(ProjectSettings.get_setting("debugperf/no_sfx", false)):
			var sfx := Sfx.new()
			add_child(sfx)
			_match_nodes.append(sfx)
			sfx.setup(world, player)
			for p in sfx._players:
				p.bus = "Master"

func _on_world_event(name: String, data: Dictionary) -> void:
	if name != "match_over" or _results != null:
		return
	var winner: int = int(data.winner)
	var sc: Array = data.score
	var wtime: float = float(data.time)
	print("MATCH_OVER winner=%d score=%s t=%.0f s" % [winner, str(sc), wtime])
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return
	_show_results(winner, sc, wtime)

## TDM results overlay (VICTORY/DEFEAT/DRAW + final score + duration);
## any tap returns to the hero select.
func _show_results(winner: int, score: Array, wtime: float, title_override := "") -> void:
	_results = CanvasLayer.new()
	_results.layer = 100
	add_child(_results)
	# Hide the in-match touch layer while the overlay is up: its full-rect
	# STOP zones swallow the dismiss tap (GUI routes the lower layer first).
	for n in _match_nodes:
		if n is TouchControls:
			(n as TouchControls).visible = false
	# The overlay's own background takes the touch: the in-match TouchControls
	# stop full-rect layers would swallow the tap before _unhandled_input.
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(func(ev: InputEvent) -> void:
		# The GUI pipeline delivers the touch as a mouse press on the mobile
		# backend (same pattern as the hero-select buttons) — accept both.
		if (ev is InputEventScreenTouch and ev.pressed) or (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
			_exit_to_select()
	)
	_results.add_child(bg)
	var vp := get_viewport().get_visible_rect().size
	# Labels IGNORE mouse so taps fall through to bg (Label default is STOP,
	# which would swallow the tap — see the hint label incident).
	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Fallback (offline, local is always team 0) or the client-provided title
	# (net, computed from my_team).
	var eff_title := title_override if title_override != "" else ("VICTORY" if winner == 0 else ("DEFEAT" if winner == 1 else "DRAW"))
	title.text = eff_title
	title.position = Vector2(vp.x * 0.5 - 160, vp.y * 0.28)
	title.size = Vector2(320, 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.modulate = Color(1.0, 0.85, 0.4) if eff_title == "VICTORY" else Color(1.0, 1.0, 1.0)
	_results.add_child(title)
	var sub := Label.new()
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.text = "%d  —  %d" % [int(score[0]), int(score[1])]
	sub.position = Vector2(vp.x * 0.5 - 160, vp.y * 0.28 + 70)
	sub.size = Vector2(320, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 34)
	_results.add_child(sub)
	var hint := Label.new()
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mins := int(wtime) / 60
	var secs := int(wtime) % 60
	hint.text = "%d:%02d  ·  TAP TO CONTINUE" % [mins, secs]
	hint.position = Vector2(vp.x * 0.5 - 160, vp.y * 0.28 + 130)
	hint.size = Vector2(320, 30)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 20)
	hint.modulate = Color(0.8, 0.85, 1.0)
	_results.add_child(hint)

func _unhandled_input(event: InputEvent) -> void:
	if _results == null:
		return
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		_exit_to_select()

func _exit_to_select() -> void:
	# Re-entry guard: the touch arrives as both a mouse press and a
	# ScreenTouch, so this can fire twice per tap.
	if _results == null:
		return
	if _results != null:
		_results.queue_free()
		_results = null
	if _net_client != null and is_instance_valid(_net_client):
		_net_client.exit()
	for n in _match_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_match_nodes = []
	world = null
	player = null
	bots = []
	_hero_select = HeroSelect.new()
	add_child(_hero_select)
	_hero_select.hero_deployed.connect(_on_deploy)
	_hero_select.range_deployed.connect(_on_range)
	_hero_select.net_deployed.connect(_on_net_deploy)
	_net_client = null

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
		if not bool(ProjectSettings.get_setting("debugperf/no_fx", false)):
			var fx := WorldFX.new()
			add_child(fx)
			fx.setup(world)
		if not bool(ProjectSettings.get_setting("debugperf/no_sfx", false)):
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
