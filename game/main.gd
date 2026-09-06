extends Node
## Match bootstrap: builds world, arena, player, bot, input, UI.
## Rendering-side nodes are only created when not headless, so the same
## scene tree runs in CI (ARCHITECTURE.md: gameplay/ must run headless).

const FIXED_DT := 1.0 / 60.0

var world: World
var player: Hero
var _bot_name_idx := [0, 0]
## D20: next-match mode vote (results screen, net + lobby matches only).
var _vote_lob: LobbyClient = null
var _vote_status: Label = null
var _map_vote_status: Label = null
var _net_match_id := 0
var bots: Array = []
var practice: PracticeManager = null
var _net_client: MatchClient = null
var _accum := 0.0
var _hero_select: HeroSelect
var _in_range := false
## D19 results/progression: local cosmetic account (server never reads it)
## + the data-driven XP/level config.
var profile: PlayerProfile = null
var progression: ProgressionConfig = null
var _my_hero_id := ""
var _net_hero_id := ""
var _bank: HeroVariantBank = null  # D22 cosmetic variants (data)
## Everything _start_match/_start_range add to the tree, so the match can be
## torn down cleanly when it ends (results overlay -> hero select).
var _match_nodes: Array = []
var _results: CanvasLayer = null

func _ready() -> void:
	randomize()
	progression = load("res://content/progression.tres") as ProgressionConfig
	profile = PlayerProfile.load(progression)
	_bank = HeroVariantBank.load_bank()
	if DisplayServer.get_name() == "headless":
		_start_match(HeroRegistry.default_hero())
		return
	_hero_select = HeroSelect.new()
	_hero_select.profile = profile
	_hero_select.progression = progression
	add_child(_hero_select)  # badge builds in _ready with the profile set
	_hero_select.hero_deployed.connect(_on_deploy)
	_hero_select.range_deployed.connect(_on_range)
	_hero_select.net_deployed.connect(_on_net_deploy)

func _on_net_deploy(host_port: String, hero_data: HeroData, match_id: int) -> void:
	# LAN match (Phase 5 v1): the MatchClient owns the render side; main only
	# tracks teardown + the results overlay. match_id (D20) identifies the
	# lobby entry for the next-match mode vote.
	_net_match_id = match_id
	_net_hero_id = hero_data.id
	if _hero_select != null:
		_hero_select.queue_free()
		_hero_select = null
	_net_client = MatchClient.new()
	add_child(_net_client)
	_match_nodes.append(_net_client)
	_net_client.ended.connect(_on_net_ended)
	# D22: the player's character wears the mastery-selected variant color
	# (client-side only; the server never reads the profile).
	var pcolor: Color = HeroVariantBank.color_for(_bank, profile, hero_data.id,
			hero_data.color)
	_net_client.setup(host_port, hero_data, pcolor)

func _on_net_ended(winner: int, score: Array, wtime: float, lost: bool,
		title: String, stats: Array) -> void:
	# Net titles are computed by the client from my_team (offline is always
	# team 0 and may still rely on the _show_results fallback).
	var info := {"stats": stats, "hero_id": _net_hero_id}
	# My stats row index: my_id is the match character id (monotonic, NOT a
	# row index - see MatchClient._char_order); the snapshot order IS the
	# M_STATS row order.
	var my_idx := -1
	if _net_client != null:
		my_idx = _net_client.stats_index_of(_net_client.my_id)
	info["names"] = []
	for i in stats.size():
		var nm := ""
		if _net_client != null and _net_client._views.has(int(i)):
			nm = _net_client._views[int(i)].display_name
		info["names"].append(nm + ("  (you)" if i == my_idx else ""))
	var mvp: int = World.mvp_index(stats)
	if my_idx >= 0 and stats.size() > my_idx:
		var row: Array = stats[my_idx]
		info["level"] = profile.apply_match(progression, _net_client.my_hero_id,
				winner == _net_client.my_team, int(row[1]), mvp == my_idx,
				int(row[4]) if row.size() > 4 else 0,
				int(row[5]) if row.size() > 5 else 0)
		# D26: newly unlocked achievements (cosmetic rewards only).
		info["achievements"] = info["level"].get("achievements_unlocked", [])
	var ids_m: Array = ModeRegistry.ids()
	var ids_map: Array = MapRegistry.ids()
	var mc: int = _net_client._mode_code if _net_client != null else 0
	var mp: int = _net_client._map_code if _net_client != null else 0
	info["label"] = (ids_m[mc] if mc < ids_m.size() else "tdm").to_upper() \
			+ "  ·  " + (ids_map[mp] if mp < ids_map.size() else "crossdocks").to_upper()
		# D27: the map just played - the map-vote UI grays it out (anti-repeat).
		info["last_map"] = ids_map[mp] if mp < ids_map.size() else "crossdocks"
	# D20: next-match mode vote (lobby-assigned matches only; offline has
	# no lobby to vote against).
	if _net_match_id > 0 and DisplayServer.get_name() != "headless":
		info["vote_match_id"] = _net_match_id
		_start_vote_lobby()
	_show_results(winner, score, wtime, title, info)

func _on_deploy(hero_data: HeroData) -> void:
	_my_hero_id = hero_data.id
	if _hero_select != null:
		_hero_select.queue_free()
		_hero_select = null
	_start_match(hero_data)

func _on_range(hero_data: HeroData) -> void:
	_my_hero_id = hero_data.id
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

	var map_data: Map = MapRegistry.get_map(MatchConfig.map_id)
	var arena := Arena.build(world, map_data)
	add_child(arena)
	_match_nodes.append(arena)

	# Mode framework v1 (Phase 6, D16/D17): same resource the server uses.
	world.mode = ModeRegistry.get_mode(MatchConfig.mode_id)
	if world.mode != null:
		world.mode.setup(world)

	# D25 (Phase 7): in-match perks; the local world is authoritative offline.
	_attach_perks()

	var size: int = clampi(MatchConfig.team_size, 1, 6)
	var team0: Array = world.spawn_points.get(0, [])
	var team1: Array = world.spawn_points.get(1, [])

	# Player on our first spawn (D22: mastery-selected variant color).
	player = HeroFactory.create(0, true,
			HeroVariantBank.color_for(_bank, profile, hero_data.id, hero_data.color),
			hero_data)
	if team0.size() > 0:
		player.position = team0[0]
	add_child(player)
	_match_nodes.append(player)
	world.register_character(player)

	# Bot roster: shuffle the six heroes so each match team varies.
	_bot_name_idx = [0, 0]
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
	# Unique display name per team (the factory's random names collide on
	# small teams; the results table and kill feed must stay readable).
	b.display_name = "Bot %d" % (team * 10 + int(_bot_name_idx[team]))
	_bot_name_idx[team] += 1
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
		# D24: desktop mouse aim honors the user's aim sensitivity.
		ControlSettings.aim_sens_active = profile.control_settings().aim_sens
		var di := DesktopInput.new()
		add_child(di)
		_match_nodes.append(di)
		var tc := TouchControls.new()
		# D24: the touch layer resolves from the baseline layout x the
		# user's persisted settings (hero-select CONTROLS panel).
		tc.layout = ControlLayout.load_layout()
		tc.settings = profile.control_settings()
		add_child(tc)
		_match_nodes.append(tc)
		var perf := PerfProbe.new()
		perf.name = "PerfProbe"
		add_child(perf)
		_match_nodes.append(perf)
		perf.setup(world)
		if not bool(ProjectSettings.get_setting("debugperf/no_hud", false)):
			var hud := HUD.new()
			hud.perk_chosen.connect(func(i: int) -> void: Controls.perk_pick = i)  # D25
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
	var stats: Array = world.stats_rows()
	var names: Array = []
	var my_idx: int = world.characters.find(player)
	for i in stats.size():
		var c: CharacterEntity = world.characters[i]
		names.append(c.display_name + ("  (you)" if i == my_idx else ""))
	var info := {"stats": stats, "names": names, "hero_id": _my_hero_id}
	var mvp: int = World.mvp_index(stats)
	if my_idx >= 0:
		var row: Array = stats[my_idx]
		info["level"] = profile.apply_match(progression, _my_hero_id, winner == 0,
				int(row[1]), mvp == my_idx,
				int(row[4]) if row.size() > 4 else 0,
				int(row[5]) if row.size() > 5 else 0)
		info["achievements"] = info["level"].get("achievements_unlocked", [])
	info["label"] = MatchConfig.mode_id.to_upper() \
			+ "  ·  " + MapRegistry.get_map(MatchConfig.map_id).short_name.to_upper()
		info["last_map"] = MatchConfig.map_id
	_show_results(winner, sc, wtime, "", info)

## Results overlay v1 (D19): VICTORY/DEFEAT/DRAW + final score + duration
## + the mode/map label + a per-player stats table with the MVP marked +
## the local player's XP gain / level. info = {stats, names, level,
## label} (all optional; an empty info keeps the legacy minimal overlay).
## Any tap returns to the hero select.
func _show_results(winner: int, score: Array, wtime: float, title_override := "",
		info: Dictionary = {}) -> void:
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
	var y := vp.y * 0.28 + 108.0
	var label: String = str(info.get("label", ""))
	if label != "":
		var ml := Label.new()
		ml.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ml.text = label
		ml.position = Vector2(vp.x * 0.5 - 200, y)
		ml.size = Vector2(400, 24)
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ml.add_theme_font_size_override("font_size", 18)
		ml.modulate = Color(0.65, 0.72, 0.9)
		_results.add_child(ml)
		y += 34.0
	# Per-player stats table (D19): [team, kills, deaths, damage] rows, MVP
	# marked. Team colors match the in-match HUD palette.
	var stats: Array = info.get("stats", [])
	var names: Array = info.get("names", [])
	var mvp: int = World.mvp_index(stats) if stats.size() > 0 else -1
	var rows_h := 0.0
	if stats.size() > 0:
		var hdr := Label.new()
		hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hdr.text = "PLAYER                    K   D   DMG"
		hdr.position = Vector2(vp.x * 0.5 - 230, y)
		hdr.size = Vector2(460, 22)
		hdr.add_theme_font_size_override("font_size", 16)
		hdr.modulate = Color(0.55, 0.6, 0.75)
		_results.add_child(hdr)
		y += 24.0
		for i in stats.size():
			var r: Array = stats[i]
			var row := Label.new()
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var nm: String = str(names[i]) if i < names.size() else "Player"
			if i == mvp:
				nm = "★ " + nm
			row.text = "%-22s  %2d  %2d  %5d" % [nm, int(r[1]), int(r[2]), int(r[3])]
			row.position = Vector2(vp.x * 0.5 - 230, y)
			row.size = Vector2(460, 24)
			row.add_theme_font_size_override("font_size", 16)
			var tc: Color = Color(0.45, 0.75, 1.0) if int(r[0]) == 0 else Color(1.0, 0.6, 0.35)
			if i == mvp:
				tc = Color(1.0, 0.85, 0.4)
			row.modulate = tc
			_results.add_child(row)
			y += 25.0
		rows_h = y
	# XP / level line (D19 local progression; cosmetic).
	var li: Dictionary = info.get("level", {})
	if li.size() > 0:
		var xl := Label.new()
		xl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lvl_txt := "+%.0f XP   ·   LV %d" % [float(li.get("xp_gained", 0.0)), int(li.get("level_after", 1))]
		if int(li.get("level_after", 1)) > int(li.get("level_before", 1)):
			lvl_txt += "   ⬆ LEVEL UP!"
		xl.text = lvl_txt
		xl.position = Vector2(vp.x * 0.5 - 200, y + 6)
		xl.size = Vector2(400, 28)
		xl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		xl.add_theme_font_size_override("font_size", 22)
		xl.modulate = Color(0.75, 1.0, 0.75)
		_results.add_child(xl)
		y += 34.0
	# D22 per-hero mastery line (cosmetic progression for THIS hero).
	var hid: String = str(info.get("hero_id", ""))
	if hid != "" and profile != null and progression != null:
		var mp: Dictionary = profile.mastery_progress_of(progression, hid)
		var hdn: HeroVariantSet = _bank.set_for(hid) if _bank != null else null
		var hdname := hid.to_upper()
		if hdn != null and _bank != null:
			for h in HeroRegistry.HEROES:
				if h is HeroData and str(h.id) == hid:
					hdname = str(h.display_name).to_upper()
					break
		var ml := Label.new()
		ml.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ml.text = "%s  MASTERY LV %d  (%.0f/%.0f)" % [
				hdname, int(mp.level), float(mp.xp_into), float(mp.need)]
		ml.position = Vector2(vp.x * 0.5 - 200, y + 2)
		ml.size = Vector2(400, 22)
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ml.add_theme_font_size_override("font_size", 16)
		ml.modulate = Color(0.7, 0.78, 0.95)
		_results.add_child(ml)
		y += 28.0
	# D26: newly unlocked achievements (cosmetic rewards only; data-driven).
	var ach: Array = info.get("achievements", [])
	if ach.size() > 0:
		var ah := Label.new()
		ah.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ah.text = "NEW ACHIEVEMENTS"
		ah.position = Vector2(vp.x * 0.5 - 230, y + 2)
		ah.size = Vector2(460, 20)
		ah.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ah.add_theme_font_size_override("font_size", 15)
		ah.modulate = Color(1.0, 0.85, 0.4)
		_results.add_child(ah)
		var rows: Array = AchievementBank.view_rows(ach)
		y += 24.0
		for i in rows.size():
			var ar := Label.new()
			ar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ar.text = str(rows[i])
			ar.position = Vector2(vp.x * 0.5 - 230, y)
			ar.size = Vector2(460, 20)
			ar.add_theme_font_size_override("font_size", 14)
			ar.modulate = Color(0.9, 0.9, 0.95)
			_results.add_child(ar)
			y += 20.0
	# D26: the current seasonal cosmetic track (data; cosmetic-only).
	var sname: String = SeasonBank.current_name()
	if sname != "":
		var sl := Label.new()
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sl.text = "SEASON  " + sname.to_upper() + "  (cosmetic track)"
		sl.position = Vector2(vp.x * 0.5 - 200, y + 4)
		sl.size = Vector2(400, 18)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.add_theme_font_size_override("font_size", 13)
		sl.modulate = Color(0.6, 0.68, 0.85)
		_results.add_child(sl)
		y += 22.0
	# Next-match mode vote (D20, net + lobby only): four mode buttons; the
	# lobby tallies (one vote per peer, last write wins) and a strict
	# majority decides - the match server applies it at the next reset.
	var vote_mid: int = int(info.get("vote_match_id", 0))
	if vote_mid > 0:
		var vl := Label.new()
		vl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vl.text = "NEXT MATCH  -  VOTE THE MODE"
		vl.position = Vector2(vp.x * 0.5 - 200, y + 2)
		vl.size = Vector2(400, 20)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vl.add_theme_font_size_override("font_size", 14)
		vl.modulate = Color(0.55, 0.6, 0.75)
		_results.add_child(vl)
		var vb_w := 74.0
		var vb_gap := 8.0
		var vb_total := 4.0 * vb_w + 3.0 * vb_gap
		var vb_x := vp.x * 0.5 - vb_total * 0.5
		var vote_ids: Array = ModeRegistry.ids()
		for i in 4:
			var vb := Button.new()
			vb.text = str(vote_ids[i]).to_upper().left(3)
			vb.position = Vector2(vb_x + float(i) * (vb_w + vb_gap), y + 26)
			vb.size = Vector2(vb_w, 30)
			vb.add_theme_font_size_override("font_size", 13)
			var opt := str(vote_ids[i])
			vb.pressed.connect(func() -> void: _cast_vote(opt))
			_results.add_child(vb)
		_vote_status = Label.new()
		_vote_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_vote_status.text = "tap a mode - applies to the NEXT match"
		_vote_status.position = Vector2(vp.x * 0.5 - 200, y + 62)
		_vote_status.size = Vector2(400, 20)
		_vote_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_vote_status.add_theme_font_size_override("font_size", 14)
		_vote_status.modulate = Color(0.7, 0.78, 0.9)
		_results.add_child(_vote_status)
		# D21: the second voting domain - the next match's map. Same rules;
		# the server rebuilds the arena at the next in-place reset.
		var ml2 := Label.new()
		ml2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ml2.text = "NEXT MATCH  -  VOTE THE MAP"
		ml2.position = Vector2(vp.x * 0.5 - 200, y + 96)
		ml2.size = Vector2(400, 20)
		ml2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ml2.add_theme_font_size_override("font_size", 14)
		ml2.modulate = Color(0.55, 0.6, 0.75)
		_results.add_child(ml2)
		var mb_w := 110.0
		var mb_gap := 10.0
		var map_ids: Array = MapRegistry.ids()
		var mb_total := float(map_ids.size()) * mb_w + float(map_ids.size() - 1) * mb_gap
		var mb_x := vp.x * 0.5 - mb_total * 0.5
		for i in map_ids.size():
			var vb2 := Button.new()
			var md: Map = MapRegistry.get_map(str(map_ids[i]))
			var lbl := str(md.display_name)
			if lbl.begins_with("The "):
				lbl = lbl.substr(4)
			vb2.text = lbl.to_upper()
			vb2.position = Vector2(mb_x + float(i) * (mb_w + mb_gap), y + 120)
			vb2.size = Vector2(mb_w, 30)
			vb2.add_theme_font_size_override("font_size", 13)
			var mopt := str(map_ids[i])
			vb2.pressed.connect(func() -> void: _cast_map_vote(mopt))
			# D27: the map just played is grayed out - the lobby rejects it as
			# a repeat while alternatives remain.
			if mopt == str(info.get("last_map", "")):
				vb2.disabled = true
				vb2.modulate = Color(0.45, 0.48, 0.55)
				vb2.text = vb2.text + " (last)"
			_results.add_child(vb2)
		_map_vote_status = Label.new()
		_map_vote_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_map_vote_status.text = "tap a map - applies to the NEXT match"
		_map_vote_status.position = Vector2(vp.x * 0.5 - 200, y + 156)
		_map_vote_status.size = Vector2(400, 20)
		_map_vote_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_map_vote_status.add_theme_font_size_override("font_size", 14)
		_map_vote_status.modulate = Color(0.7, 0.78, 0.9)
		_results.add_child(_map_vote_status)
		y += 184.0
	var hint := Label.new()
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mins := int(wtime) / 60
	var secs := int(wtime) % 60
	hint.text = "%d:%02d  ·  TAP TO CONTINUE" % [mins, secs]
	hint.position = Vector2(vp.x * 0.5 - 160, maxf(y + 8.0, vp.y * 0.28 + 130.0))
	hint.size = Vector2(320, 30)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 20)
	hint.modulate = Color(0.8, 0.85, 1.0)
	_results.add_child(hint)

## D20: the vote lobby (results screen only). Same host heuristic as
## hero-select's lobby (10.0.2.2 on Android = the host under NAT).
func _start_vote_lobby() -> void:
	if _vote_lob != null:
		return
	_vote_lob = LobbyClient.new()
	add_child(_vote_lob)
	var host := "10.0.2.2" if OS.has_feature("android") else "127.0.0.1"
	_vote_lob.setup(host, MatchConfig.lobby_port)
	_vote_lob.vote_result.connect(_on_vote_result)
	_vote_lob.map_vote_result.connect(_on_map_vote_result)

func _cast_vote(mode: String) -> void:
	if _vote_lob != null and _net_match_id > 0:
		_vote_lob.vote(_net_match_id, mode)

func _cast_map_vote(map: String) -> void:
	if _vote_lob != null and _net_match_id > 0:
		_vote_lob.map_vote(_net_match_id, map)

func _format_vote_status(info: Dictionary, ids: Array, choice_key: String) -> String:
	if bool(info.get("decided", false)):
		return "DECIDED: " + str(info.get(choice_key, "?")).to_upper() + "  (next match)"
	var tally: Dictionary = info.get("tally", {})
	var parts: Array = []
	for k in ids:
		if tally.has(k):
			parts.append(str(k).to_upper() + " " + str(int(tally[k])))
	var txt: String = "  ·  ".join(parts) if parts.size() > 0 else "no votes yet"
	var ld := str(info.get("leading", ""))
	if ld != "":
		txt += "   leading " + ld.to_upper()
	return txt

func _on_vote_result(info: Dictionary) -> void:
	if _vote_status == null:
		return
	_vote_status.text = _format_vote_status(info, ModeRegistry.ids(), "mode")
	if bool(info.get("decided", false)):
		_vote_status.modulate = Color(1.0, 0.85, 0.4)

func _on_map_vote_result(info: Dictionary) -> void:
	if _map_vote_status == null:
		return
	var txt: String = _format_vote_status(info, MapRegistry.ids(), "map")
	var rep: String = str(info.get("repeat", ""))
	if rep != "":
		txt += "   ·   " + rep.to_upper() + " was just played"
	_map_vote_status.text = txt
	if bool(info.get("decided", false)):
		_map_vote_status.modulate = Color(1.0, 0.85, 0.4)

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
	if _vote_lob != null and is_instance_valid(_vote_lob):
		_vote_lob.queue_free()
	_vote_lob = null
	_vote_status = null
	_map_vote_status = null
	_net_match_id = 0
	for n in _match_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_match_nodes = []
	world = null
	player = null
	bots = []
	_hero_select = HeroSelect.new()
	_hero_select.profile = profile
	_hero_select.progression = progression
	add_child(_hero_select)
	_hero_select.hero_deployed.connect(_on_deploy)
	_hero_select.range_deployed.connect(_on_range)
	_hero_select.net_deployed.connect(_on_net_deploy)
	_net_client = null

## D25: one PerkSystem per match world (the range deliberately has none:
## it trains the kit, not the match).
func _attach_perks() -> void:
	world.perk_system = PerkSystem.new()
	world.add_child(world.perk_system)
	world.perk_system.setup(world, load("res://content/perks/perks.tres"), randi())

func _start_range(hero_data: HeroData) -> void:
	_in_range = true
	world = World.new()
	world.name = "World"
	add_child(world)

	var range_root := PracticeRange.build(world)
	add_child(range_root)

	player = HeroFactory.create(0, true,
			HeroVariantBank.color_for(_bank, profile, hero_data.id, hero_data.color),
			hero_data)
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
		# D24: the practice range honors the user's control settings too
		# (same wiring as _start_match).
		ControlSettings.aim_sens_active = profile.control_settings().aim_sens
		add_child(DesktopInput.new())
		var tc := TouchControls.new()
		tc.layout = ControlLayout.load_layout()
		tc.settings = profile.control_settings()
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
