class_name HeroSelect
extends CanvasLayer
## Hero select screen (Phase 2): roster cards from HeroRegistry + DEPLOY.
## Emits hero_deployed(HeroData). Render-side only (skipped headless).

signal hero_deployed(hero: HeroData)
signal range_deployed(hero: HeroData)
signal net_deployed(host_port: String, hero: HeroData)

var _deploy_btn: Control
var _practice_btn: Control
var _join_edit: LineEdit
var _join_btn: Button
var _scan_btn: Button
var _result_a: Button
var _result_b: Button
var _scanner: DiscoveryScanner = null
var _scan_active := false
var _scan_count := 0
var _hero: HeroData = null
var _cards: Array = []
var _diff_btns: Array = []
## ONLINE matchmaking (Phase 5 v1, lobby prototype - see docs/NETWORKING D12).
var _lob: LobbyClient = null
var _lob_region_btn: Button = null
var _lob_status: Label = null
var _lob_play_btn: Button = null
var _lob_region_idx := 0
var _lob_in_queue := false

func _ready() -> void:
	_hero = HeroRegistry.default_hero()
	_build()

func _select(hd: HeroData) -> void:
	if _hero == hd:
		return
	_hero = hd
	for c in _cards:
		c.control.queue_redraw()

func _process(_delta: float) -> void:
	# Pump the LAN discovery scanner while a scan is in flight.
	if _scan_active and _scanner != null:
		_scanner.pump()

func _unhandled_input(event: InputEvent) -> void:
	# While queued for online, ENTER/SPACE must not launch an offline match.
	if _lob_in_queue:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE or event.keycode == KEY_KP_ENTER:
			_deploy()

func _deploy() -> void:
	if _hero == null:
		return
	hero_deployed.emit(_hero)

func _build() -> void:
	var vp := Vector2(get_viewport().get_visible_rect().size)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var title := Label.new()
	title.text = "HERO ARENA"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.modulate = Color(0.9, 0.95, 1.0)
	add_child(title)

	# Roster cards (one per registry hero; 6 slots arrive with Phase 3).
	var n := HeroRegistry.HEROES.size()
	var spacing := minf(220.0, (vp.x - 40.0) / float(n))  # 6-card roster must fit
	var card_w := spacing - 24.0
	var cards_x := vp.x * 0.5 - float(n) * spacing * 0.5
	var i := 0
	for h in HeroRegistry.HEROES:
		var hd: HeroData = h
		var card := Control.new()
		card.position = Vector2(cards_x + i * spacing, vp.y * 0.5 - 140.0)
		card.size = Vector2(card_w, 280)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		var data := hd
		card.draw.connect(func() -> void: _draw_card(card, data))
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if (ev is InputEventScreenTouch and ev.pressed) or (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
				_select(data)
		)
		add_child(card)
		_cards.append({control = card, data = hd})

		var ic := ColorRect.new()
		ic.color = hd.color
		ic.position = Vector2((card_w - 120.0) * 0.5, 20)
		ic.size = Vector2(120, 90)
		card.add_child(ic)

		var nm := Label.new()
		nm.text = hd.display_name
		nm.position = Vector2(4, 120)
		nm.size = Vector2(card_w - 8.0, 30)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_font_size_override("font_size", 24)
		card.add_child(nm)

		var role := Label.new()
		role.text = _role_text(hd)
		role.position = Vector2(4, 152)
		role.size = Vector2(card_w - 8.0, 20)
		role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		role.add_theme_font_size_override("font_size", 14)
		role.modulate = Color(0.75, 0.8, 0.9)
		card.add_child(role)

		var kit := Label.new()
		kit.text = _kit_text(hd)
		kit.position = Vector2(4, 178)
		kit.size = Vector2(card_w - 8.0, 92)
		kit.add_theme_font_size_override("font_size", 12)
		kit.modulate = Color(0.65, 0.7, 0.8)
		card.add_child(kit)
		i += 1

	var hint := Label.new()
	hint.text = "TAP DEPLOY  (or ENTER)"
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position.y = -8.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(0.6, 0.65, 0.75)
	add_child(hint)

	_make_deploy(vp)
	_make_practice(vp)
	_make_join_row(vp)
	_make_difficulty_row(vp)
	_make_mode_row(vp)
	_make_online_row(vp)

func _draw_card(c: Control, hd: HeroData) -> void:
	var selected := hd == _hero
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Color(0.10, 0.12, 0.17, 1.0))
	if selected:
		c.draw_rect(r.grow(-2.0), Color(1.0, 0.85, 0.4, 1.0), false, 3.0)
		c.draw_rect(r, Color(1.0, 0.85, 0.4, 0.12))
	else:
		c.draw_rect(r.grow(-2.0), Color(0.25, 0.3, 0.4, 1.0), false, 1.5)

func _role_text(hd: HeroData) -> String:
	var roles := ["ASSAULT", "TANK", "SUPPORT", "CONTROLLER"]
	var subs := ["SUSTAINED", "SPRINT", "ARMOR", "FLEX", "FIELD", "ZONE"]
	return roles[hd.role] + " / " + subs[hd.sub_role]

func _kit_text(hd: HeroData) -> String:
	var s := ""
	if hd.passive != null:
		s += "PASSIVE  " + hd.passive.display_name + "\n"
	for a in hd.abilities:
		var ab: AbilityData = a
		var key := "Q" if ab == hd.abilities[0] else "E"
		s += key + "  " + ab.display_name + "\n"
	if hd.ult != null:
		s += "F  ULT  " + hd.ult.display_name
	return s

func _make_deploy(vp: Vector2) -> Control:
	var c := Control.new()
	_deploy_btn = c
	c.position = Vector2(vp.x * 0.5 - 110.0, vp.y - 120.0)
	c.size = Vector2(220, 64)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.draw.connect(_draw_deploy)
	c.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenTouch and event.pressed:
			_deploy()
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_deploy()
	)
	add_child(c)
	return c

func _make_practice(vp: Vector2) -> Control:
	var c := Control.new()
	_practice_btn = c
	c.position = Vector2(vp.x * 0.5 - 110.0, vp.y - 44.0)
	c.size = Vector2(220, 30)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.draw.connect(_draw_practice)
	c.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenTouch and event.pressed:
			_practice()
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_practice()
	)
	add_child(c)
	return c

func _make_join_row(vp: Vector2) -> void:
	# LAN join (Phase 5 v1, directive §21): host:port direct connect.
	_join_edit = LineEdit.new()
	_join_edit.placeholder_text = "host:port  (LAN)"
	_join_edit.position = Vector2(vp.x * 0.5 - 106.0, vp.y - 158.0)
	_join_edit.size = Vector2(130.0, 26.0)
	_join_edit.add_theme_font_size_override("font_size", 12)
	_join_edit.text_submitted.connect(_on_join_text)
	add_child(_join_edit)
	_join_btn = Button.new()
	_join_btn.text = "JOIN"
	_join_btn.position = Vector2(vp.x * 0.5 + 30.0, vp.y - 158.0)
	_join_btn.size = Vector2(76.0, 26.0)
	_join_btn.add_theme_font_size_override("font_size", 12)
	_join_btn.pressed.connect(_join)
	add_child(_join_btn)
	# LAN discovery (Phase 5): SCAN broadcasts the discovery port (and
	# unicasts it too when the field holds an explicit host - that path also
	# works across the emulator NAT, where broadcasts do not reach the host).
	_scan_btn = Button.new()
	_scan_btn.text = "SCAN"
	_scan_btn.position = Vector2(vp.x * 0.5 + 110.0, vp.y - 158.0)
	_scan_btn.size = Vector2(52.0, 26.0)
	_scan_btn.add_theme_font_size_override("font_size", 12)
	_scan_btn.pressed.connect(_scan)
	add_child(_scan_btn)
	# Up to two result slots on the row: right of SCAN and left of the edit.
	_result_a = _make_result_slot(Vector2(vp.x * 0.5 + 166.0, vp.y - 158.0),
			Vector2(vp.x - (vp.x * 0.5 + 166.0) - 8.0, 26.0))
	_result_b = _make_result_slot(Vector2(8.0, vp.y - 158.0),
			Vector2(vp.x * 0.5 - 106.0 - 16.0, 26.0))

func _make_result_slot(pos: Vector2, size: Vector2) -> Button:
	var b := Button.new()
	b.text = ""
	b.position = pos
	b.size = size
	b.add_theme_font_size_override("font_size", 11)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.visible = false
	b.pressed.connect(func() -> void:
		if b.text.begins_with("ip:"):
			_join_edit.text = b.text.substr(3)
			_join_edit.queue_redraw()
	)
	add_child(b)
	return b

func _on_join_text(_t: String) -> void:
	_join()

func _scan() -> void:
	if _scan_active:
		return
	_scan_active = true
	_scan_count = 0
	_scan_btn.text = "..."
	_result_a.visible = false
	_result_b.visible = false
	_scanner = DiscoveryScanner.new()
	_scanner.found.connect(_on_server_found)
	_scanner.done.connect(_on_scan_done)
	# Unicast the explicit host from the field (if any) in addition to the
	# broadcast.
	var host := _join_edit.text.strip_edges()
	var unicast := ""
	if host != "":
		unicast = host.split(":")[0]
	_scanner.start(unicast)

func _on_server_found(info: Dictionary) -> void:
	var slot: Button = _result_a if _scan_count == 0 else _result_b
	_scan_count += 1
	var word: String = ["open", "full", "over"][clampi(int(info.state), 0, 2)]
	slot.text = "ip:" + str(info.ip) + ":" + str(info.game_port)
	slot.tooltip_text = str(info.ip) + ":" + str(info.game_port) + "  " + word 			+ "  " + str(info.humans) + "/" + str(info.team_size) + "  (tap to fill)"
	slot.visible = true
	slot.queue_redraw()

func _on_scan_done(count: int) -> void:
	_scan_active = false
	_scan_btn.text = "SCAN"
	_scan_btn.queue_redraw()
	if count == 0:
		_result_a.text = "no servers found"
		_result_a.tooltip_text = ""
		_result_a.visible = true
		_result_a.queue_redraw()
	_scanner = null

func _join() -> void:
	var hp := _join_edit.text.strip_edges()
	if hp.is_empty() or _hero == null:
		return
	net_deployed.emit(hp, _hero)

func _practice() -> void:
	if _hero == null:
		return
	range_deployed.emit(_hero)

func _draw_practice() -> void:
	var c := _practice_btn
	if c == null:
		return
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Color(0.2, 0.32, 0.42, 0.9))
	c.draw_rect(r.grow(-2.0), Color(0.35, 0.5, 0.62, 0.9), false, 1.5)
	var f := ThemeDB.fallback_font
	var sz := f.get_string_size("PRACTICE RANGE", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 16, 16)
	c.draw_string(f, Vector2(r.position.x + (r.size.x - sz.x) * 0.5, r.position.y + r.size.y * 0.5 + sz.y * 0.35), "PRACTICE RANGE", HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 16, Color(0.85, 0.9, 1.0))

func _draw_deploy() -> void:
	var c := _deploy_btn
	if c == null:
		return
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Color(0.25, 0.55, 0.95, 0.9))
	c.draw_rect(r.grow(-3.0), Color(0.35, 0.65, 1.0, 0.9))
	var f := ThemeDB.fallback_font
	var sz := f.get_string_size("DEPLOY", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 26, 26)
	c.draw_string(f, Vector2(r.position.x + (r.size.x - sz.x) * 0.5, r.position.y + r.size.y * 0.5 + sz.y * 0.35), "DEPLOY", HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 26, Color.WHITE)

## Bot difficulty picker (Phase 4): 4 tier buttons, writes MatchConfig.
func _make_difficulty_row(vp: Vector2) -> void:
	var lbl := Label.new()
	lbl.text = "BOT DIFFICULTY"
	lbl.position = Vector2(vp.x * 0.5, vp.y - 196.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.modulate = Color(0.55, 0.6, 0.72)
	add_child(lbl)
	var ids: Array = BotDifficulties.ids()
	var short := {"beginner": "BEG", "normal": "NORM", "advanced": "ADV", "expert": "EXPT"}
	var w := 52.0
	var gap := 4.0
	var total := float(ids.size()) * w + float(ids.size() - 1) * gap
	var x := vp.x * 0.5 - total * 0.5
	for i in ids.size():
		var id: String = ids[i]
		var c := Control.new()
		c.position = Vector2(x + i * (w + gap), vp.y - 176.0)
		c.size = Vector2(w, 26)
		c.mouse_filter = Control.MOUSE_FILTER_STOP
		c.set_meta("diff_id", id)
		c.set_meta("diff_short", short[id])
		c.draw.connect(func() -> void: _draw_diff(c))
		c.gui_input.connect(func(ev: InputEvent) -> void:
			if (ev is InputEventScreenTouch and ev.pressed) or (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
				MatchConfig.set_difficulty(String(c.get_meta("diff_id")))
				for b in _diff_btns:
					b.queue_redraw()
		)
		add_child(c)
		_diff_btns.append(c)

## Mode + map picker (Phase 6, D16-D18): the host's match settings. Writes
## MatchConfig (mode_id / map_id); hosts (main.gd, server_main) read them,
## the server advertises the mode into the lobby (reg) and both into M_SLOT.
func _make_mode_row(vp: Vector2) -> void:
	var lbl := Label.new()
	lbl.text = "MODE / MAP"
	lbl.position = Vector2(vp.x * 0.5, vp.y - 256.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.modulate = Color(0.55, 0.6, 0.72)
	add_child(lbl)
	var items: Array = []
	var mshort := {"tdm": "TDM", "control": "CTL", "capture": "CAP", "escort": "ESC"}
	for mid in ModeRegistry.ids():
		items.append(["mode", mid, mshort.get(mid, mid), 54.0])
	for mid in MapRegistry.ids():
		var m: Map = MapRegistry.get_map(mid)
		items.append(["map", mid, m.short_name, 70.0])
	var gap := 4.0
	var total := 0.0
	for it in items:
		total += float(it[3]) + gap
	var x := vp.x * 0.5 - total * 0.5 + gap * 0.5
	for it in items:
		var kind: String = it[0]
		var id: String = it[1]
		var c := Control.new()
		c.position = Vector2(x, vp.y - 236.0)
		c.size = Vector2(float(it[3]), 26)
		c.mouse_filter = Control.MOUSE_FILTER_STOP
		c.set_meta("pick_kind", kind)
		c.set_meta("pick_id", id)
		c.set_meta("pick_short", it[2])
		c.draw.connect(func() -> void: _draw_pick(c))
		c.gui_input.connect(func(ev: InputEvent) -> void:
			if (ev is InputEventScreenTouch and ev.pressed) or (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
				if kind == "mode":
					_pick_mode(id)
				else:
					_pick_map(id)
			)
		add_child(c)
		_pick_btns.append(c)
		x += float(it[3]) + gap

## Named handlers (testable headless): write the pick into MatchConfig and
## redraw the row.
func _pick_mode(id: String) -> void:
	if id in ModeRegistry.ids():
		MatchConfig.mode_id = id
	for c in _get_pick_btns():
		c.queue_redraw()

func _pick_map(id: String) -> void:
	if id in MapRegistry.ids():
		MatchConfig.map_id = id
	for c in _get_pick_btns():
		c.queue_redraw()

var _pick_btns: Array = []

func _get_pick_btns() -> Array:
	return _pick_btns

func _draw_pick(c: Control) -> void:
	var kind: String = String(c.get_meta("pick_kind"))
	var id: String = String(c.get_meta("pick_id"))
	var sel: bool = (kind == "mode" and MatchConfig.mode_id == id) \
			or (kind == "map" and MatchConfig.map_id == id)
	var r := Rect2(Vector2.ZERO, c.size)
	var fill := Color(0.16, 0.19, 0.26, 1.0) if not sel else Color(0.35, 0.62, 1.0, 0.95)
	c.draw_rect(r, fill)
	var f := ThemeDB.fallback_font
	var txt: String = String(c.get_meta("pick_short"))
	var sz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, 14)
	c.draw_string(f, Vector2(r.position.x + (r.size.x - sz.x) * 0.5, r.position.y + r.size.y * 0.5 + sz.y * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 14, Color(0.95, 0.97, 1.0))

func _draw_diff(c: Control) -> void:
	var sel: bool = MatchConfig.difficulty == String(c.get_meta("diff_id"))
	var r := Rect2(Vector2.ZERO, c.size)
	var fill := Color(0.16, 0.19, 0.26, 1.0) if not sel else Color(0.35, 0.62, 1.0, 0.95)
	c.draw_rect(r, fill)
	c.draw_rect(r.grow(-1.5), Color(0.4, 0.85, 0.5, 1.0) if sel else Color(0.3, 0.36, 0.46, 1.0), false, 1.5)
	var f := ThemeDB.fallback_font
	var txt: String = String(c.get_meta("diff_short"))
	var sz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, 14)
	c.draw_string(f, Vector2(r.position.x + (r.size.x - sz.x) * 0.5, r.position.y + r.size.y * 0.5 + sz.y * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 14, Color(0.95, 0.97, 1.0))
## ONLINE matchmaking row (Phase 5 v1, lobby prototype - docs/NETWORKING, D12).
## Compact panel in the bottom-left, clear of the centered DEPLOY / join /
## difficulty rows. Region cycles the LATAM-first table; PLAY joins the queue
## and auto-joins the assigned game server (net_deployed).
func _make_online_row(vp: Vector2) -> void:
	var panel_x := 12.0
	var panel_w := 252.0
	var row_y := vp.y - 118.0
	var row_h := 28.0
	_lob_region_btn = Button.new()
	_lob_region_btn.text = "REGION  " + Regions.display(str(Regions.all()[0].code))
	_lob_region_btn.position = Vector2(panel_x, row_y)
	_lob_region_btn.size = Vector2(panel_w, row_h)
	_lob_region_btn.add_theme_font_size_override("font_size", 11)
	_lob_region_btn.pressed.connect(_cycle_region)
	add_child(_lob_region_btn)
	_lob_status = Label.new()
	_lob_status.text = "connecting…"
	_lob_status.position = Vector2(panel_x, row_y + row_h + 2.0)
	_lob_status.size = Vector2(panel_w, 18.0)
	_lob_status.add_theme_font_size_override("font_size", 11)
	_lob_status.modulate = Color(0.7, 0.78, 0.9)
	add_child(_lob_status)
	_lob_play_btn = Button.new()
	_lob_play_btn.text = "PLAY"
	_lob_play_btn.position = Vector2(panel_x, row_y + row_h + 24.0)
	_lob_play_btn.size = Vector2(panel_w, 30.0)
	_lob_play_btn.add_theme_font_size_override("font_size", 13)
	_lob_play_btn.pressed.connect(_on_play_online)
	add_child(_lob_play_btn)
	_setup_lobby()

## Lobby address: the emulator reaches the host via 10.0.2.2 (NAT); desktop /
## dev via loopback. Documented prototype heuristic (D12) - not user-configurable yet.
func _setup_lobby() -> void:
	var host := "10.0.2.2" if OS.has_feature("android") else "127.0.0.1"
	_lob = LobbyClient.new()
	_lob.connected_ok.connect(_on_lob_connected)
	_lob.disconnected.connect(_on_lob_disconnected)
	_lob.hello.connect(_on_lob_hello)
	_lob.pong.connect(_on_lob_pong)
	_lob.queue.connect(_on_lob_queue)
	_lob.assign.connect(_on_lob_assign)
	add_child(_lob)
	_lob.setup(host, MatchConfig.lobby_port)

func _cycle_region() -> void:
	_lob_region_idx = (_lob_region_idx + 1) % Regions.all().size()
	var code: String = str(Regions.all()[_lob_region_idx].code)
	_lob_region_btn.text = "REGION  " + Regions.display(code)

func _on_lob_connected() -> void:
	if not _lob_in_queue:
		_lob_status.text = "lobby online"
		_lob_status.modulate = Color(0.55, 0.85, 0.55)

func _on_lob_disconnected() -> void:
	if not _lob_in_queue:
		_lob_status.text = "lobby offline"
		_lob_status.modulate = Color(0.9, 0.55, 0.5)

func _on_lob_hello(_info: Dictionary) -> void:
	# v1: hello carries region + open-match/waiter counts; the queue messages
	# already surface what the player needs, so nothing to render yet.
	pass

func _on_lob_pong(rtt_ms: float) -> void:
	if _lob_in_queue:
		return
	_lob_status.text = "lobby  %d ms" % int(rtt_ms)
	_lob_status.modulate = Color(0.7, 0.78, 0.9)

func _on_lob_queue(info: Dictionary) -> void:
	var waited: int = int(info.get("waited", 0.0))
	_lob_status.text = "queue %d:%02d  stage %d" % [waited / 60, waited % 60, int(info.get("stage", 1))]
	_lob_status.modulate = Color(0.95, 0.8, 0.4)
	_lob_play_btn.text = "WAITING…"

func _on_lob_assign(info: Dictionary) -> void:
	_lob_in_queue = false
	var host_port := str(info.get("host")) + ":" + str(info.get("port"))
	var mode_s: String = str(info.get("mode", "tdm"))
	_lob_status.text = "joining " + host_port + "  [" + mode_s + "]"
	_lob_play_btn.text = "PLAY"
	if _hero != null:
		net_deployed.emit(host_port, _hero)

func _on_play_online() -> void:
	if _lob_in_queue:
		return
	if _hero == null:
		return
	_lob_in_queue = true
	var code: String = str(Regions.all()[_lob_region_idx].code)
	_lob.join_queue(code, 1, 0, "P1")
	_lob_status.text = "joining queue…"
	_lob_status.modulate = Color(0.95, 0.8, 0.4)
	_lob_play_btn.text = "WAITING…"
