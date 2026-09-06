class_name HeroSelect
extends CanvasLayer
## Hero select screen (Phase 2): roster cards from HeroRegistry + DEPLOY.
## Emits hero_deployed(HeroData). Render-side only (skipped headless).

signal hero_deployed(hero: HeroData)
signal range_deployed(hero: HeroData)
signal net_deployed(host_port: String, hero: HeroData, match_id: int)

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
var _room_edit: LineEdit = null  # D35: private room code input
var _room_join_btn: Button = null
var _lob_region_idx := 0
var _lob_in_queue := false
## D19: local cosmetic progression (main.gd passes the loaded profile + the
## XP/level config so the badge shows level/XP/matches/wins).
var profile: PlayerProfile = null
var progression: ProgressionConfig = null
## D22: cosmetic variant bank (data) + the per-card variant dot states.
var _bank: HeroVariantBank = null
var _variant_dots: Array = []
## D24: control customization panel (persisted in the profile; the in-match
## touch layer resolves baseline layout x these settings).
var _ctl_btn: Button = null
## D31: the shop overlay (cosmetic-only; see docs/GAME_DESIGN "Shop").
var _shop_btn: Button = null
var _shop_panel: Control = null
var _ctl_panel: Control = null
var _ctl_settings: ControlSettings = null
var _ctl_vals: Array = []   # {label, key, min, max} per numeric row
var _ctl_side: Array = []   # [left_btn, right_btn] FIRE SIDE row
var _ctl_reset: Button = null

func _ready() -> void:
	_hero = HeroRegistry.default_hero()
	_bank = HeroVariantBank.load_bank()
	_build()

func _select(hd: HeroData) -> void:
	if _hero == hd:
		return
	_hero = hd
	for c in _cards:
		c.control.queue_redraw()

func _cards_meta_swatch(idx: int, swatch: ColorRect) -> void:
	if idx < _cards.size():
		_cards[idx].swatch = swatch

## D22: one tap-dot per cosmetic variant (data: palette + mastery unlock).
## Unlocked dots are tappable; locked ones are dimmed and inert.
func _add_variant_strip(card: Control, hd: HeroData, pos: Vector2,
		card_w: float) -> void:
	var s: HeroVariantSet = _bank.set_for(hd.id) if _bank != null else null
	if s == null:
		return
	var n := s.palette.size()
	if n == 0:
		return
	var dot_w := 18.0
	var gap := 4.0
	var total := float(n) * dot_w + float(n - 1) * gap
	var x0: float = (card_w - total) * 0.5
	for i in n:
		var dot := Control.new()
		dot.position = pos + Vector2(x0 + float(i) * (dot_w + gap), 0)
		dot.size = Vector2(dot_w, 12)
		dot.mouse_filter = Control.MOUSE_FILTER_STOP
		var st := {hero = hd, idx = i, unlocked = true, selected = false}
		var ss := s
		dot.draw.connect(func() -> void: _draw_dot(dot, st, ss))
		dot.gui_input.connect(func(ev: InputEvent) -> void:
			if (ev is InputEventScreenTouch and ev.pressed) or (ev is InputEventMouseButton and ev.pressed):
				_on_variant_tap(hd, i)
		)
		_refresh_dot_state(st, ss, hd)
		card.add_child(dot)
		_variant_dots.append({ctrl = dot, st = st, set = ss, hero = hd})

func _draw_dot(dot: Control, st: Dictionary, s: HeroVariantSet) -> void:
	var col: Color = s.color_of(int(st.idx), Color.WHITE)
	if not bool(st.unlocked):
		col = col.darkened(0.65)
	dot.draw_rect(Rect2(Vector2.ZERO, dot.size), col)
	if bool(st.selected):
		dot.draw_rect(Rect2(Vector2.ZERO, dot.size), Color.WHITE, false, 2.0)
	elif not bool(st.unlocked):
		dot.draw_rect(Rect2(Vector2.ZERO, dot.size), Color(1.0, 1.0, 1.0, 0.25),
				false, 1.0)

func _refresh_dot_state(st: Dictionary, s: HeroVariantSet, hd: HeroData) -> void:
	# D31: mastery gate OR any cosmetic grant (ach / event / shop).
	st.unlocked = HeroVariantBank.variant_unlocked(_bank, profile,
			progression, hd.id, int(st.idx))
	st.selected = (profile != null and profile.selected_variant(hd.id) == int(st.idx)) \
			or (profile == null and int(st.idx) == 0)

func _on_variant_tap(hd: HeroData, idx: int) -> void:
	if profile == null or progression == null or _bank == null:
		return
	var s: HeroVariantSet = _bank.set_for(hd.id)
	if s == null:
		return
	if not HeroVariantBank.variant_unlocked(_bank, profile, progression,
				hd.id, idx):
		return  # locked: needs more mastery or a cosmetic grant
	profile.set_variant(hd.id, idx)
	for d in _variant_dots:
		if d.hero == hd:
			_refresh_dot_state(d.st, d.set, hd)
			d.ctrl.queue_redraw()
	for c in _cards:
		if c.data == hd:
			c.swatch.color = HeroVariantBank.color_for(_bank, profile, hd.id, hd.color)

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

	# D19 progression badge (cosmetic; the server never reads it).
	if profile != null:
		var need := progression.xp_for_level(profile.level) if progression != null else 0.0
		var lv := Label.new()
		lv.text = "LV %d  ·  %.0f/%.0f XP  ·  %d matches  ·  %d wins" % [
				profile.level, profile.xp, need, profile.matches, profile.wins]
		lv.position = Vector2(vp.x - 380.0, 10.0)
		lv.size = Vector2(368.0, 24.0)
		lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lv.add_theme_font_size_override("font_size", 16)
		lv.modulate = Color(0.6, 0.75, 0.9)
		lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(lv)

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
		# D22: the card preview shows the player's SELECTED variant color
		# (mastery-unlocked cosmetics; profile may be null in tests).
		ic.color = HeroVariantBank.color_for(_bank, profile, hd.id, hd.color)
		ic.position = Vector2((card_w - 120.0) * 0.5, 14)
		ic.size = Vector2(120, 90)
		card.add_child(ic)
		_cards_meta_swatch(i, ic)

		var nm := Label.new()
		nm.text = hd.display_name
		nm.position = Vector2(4, 126)
		nm.size = Vector2(card_w - 8.0, 30)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_font_size_override("font_size", 24)
		card.add_child(nm)

		var role := Label.new()
		role.text = _role_text(hd)
		role.position = Vector2(4, 158)
		role.size = Vector2(card_w - 8.0, 20)
		role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		role.add_theme_font_size_override("font_size", 14)
		role.modulate = Color(0.75, 0.8, 0.9)
		card.add_child(role)

		var kit := Label.new()
		kit.text = _kit_text(hd)
		if profile != null and progression != null:
			kit.text += "\nMASTERY LV " + str(profile.mastery_level_of(progression, hd.id))
		kit.position = Vector2(4, 180)
		kit.size = Vector2(card_w - 8.0, 92)
		kit.add_theme_font_size_override("font_size", 12)
		kit.modulate = Color(0.65, 0.7, 0.8)
		card.add_child(kit)

		_add_variant_strip(card, hd, Vector2(0, 108), card_w)
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
	_make_controls_row(vp)
	_make_shop_btn(vp)

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
	# D35: custom matches - enter a private room code (the dedicated server
	# prints its code with --room; the lobby resolves code -> address).
	_room_edit = LineEdit.new()
	_room_edit.placeholder_text = "ROOM CODE (5)"
	_room_edit.max_length = LobbyProtocol.ROOM_LEN
	_room_edit.position = Vector2(panel_x, row_y + 2.0 * (row_h + 24.0) + 6.0)
	_room_edit.size = Vector2(panel_w * 0.62, row_h)
	_room_edit.add_theme_font_size_override("font_size", 12)
	add_child(_room_edit)
	_room_join_btn = Button.new()
	_room_join_btn.text = "JOIN"
	_room_join_btn.position = Vector2(panel_x + panel_w * 0.66, row_y + 2.0 * (row_h + 24.0) + 6.0)
	_room_join_btn.size = Vector2(panel_w * 0.34 - 4.0, row_h)
	_room_join_btn.add_theme_font_size_override("font_size", 11)
	_room_join_btn.pressed.connect(_on_room_join)
	add_child(_room_join_btn)
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
	_lob.roomjoinack.connect(_on_room_joinack)  # D35
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
	# D28: the lobby's win-probability estimate for this join (side A = us).
	var wp_txt := ""
	var wp: float = float(info.get("win_prob", -1.0))
	if wp >= 0.0:
		wp_txt = "  P(win) ~ %d%%" % int(wp * 100.0 + 0.5)
	_lob_status.text = "joining " + host_port + "  [" + mode_s + "]" + wp_txt
	_lob_play_btn.text = "PLAY"
	if _hero != null:
		# match_id (D20): the lobby's id of this match - the results screen
		# votes the NEXT match's mode against it.
		net_deployed.emit(host_port, _hero, int(info.get("match_id", 0)))

## D35: join a private match by room code.
func _on_room_join() -> void:
	if _lob_in_queue:
		return
	var code := _room_edit.text.strip_edges().to_upper()
	if not LobbyProtocol.is_room_code(code):
		_lob_status.text = "code: " + str(LobbyProtocol.ROOM_LEN) + " chars (no 0/O/1/I)"
		_lob_status.modulate = Color(0.9, 0.55, 0.5)
		return
	_lob_status.text = "resolving " + code + "\u2026"
	_lob_status.modulate = Color(0.95, 0.8, 0.4)
	_lob.join_room(code)

func _on_room_joinack(info: Dictionary) -> void:
	if bool(info.get("ok", false)):
		var hp := str(info.get("host")) + ":" + str(info.get("port"))
		var mode_s: String = str(info.get("mode", "tdm"))
		_lob_status.text = "room " + str(info.get("code")) + " @ " + hp + "  [" + mode_s + "]"
		_lob_status.modulate = Color(0.55, 0.85, 0.55)
		_lob_play_btn.text = "PLAY"
		if _hero != null:
			net_deployed.emit(hp, _hero, int(info.get("match_id", 0)))
	else:
		_lob_status.text = str(info.get("err", "room not found"))
		_lob_status.modulate = Color(0.9, 0.55, 0.5)

func _on_play_online() -> void:
	if _lob_in_queue:
		return
	if _hero == null:
		return
	_lob_in_queue = true
	var code: String = str(Regions.all()[_lob_region_idx].code)
	# D28: the queue rating derives from the profile's account level on the
	# shared curve - level 1 = 1000 (neutral), +40 per level above.
	var skill := 1000
	if profile != null:
		skill = 1000 + 40 * maxi(profile.level - 1, 0)
	_lob.join_queue(code, 1, skill, "P1")
	_lob_status.text = "joining queue…"
	_lob_status.modulate = Color(0.95, 0.8, 0.4)
	_lob_play_btn.text = "WAITING…"

## D24 mobile controls customization (Phase 6 deliverable: customizable HUD
## - position/size/sensitivity/opacity/aim settings). The CONTROLS button
## (bottom-right, mirrored from the online row) opens a centered panel with
## steppers; every edit persists immediately via the profile (same pattern
## as the D22 variant taps). The in-match TouchControls builds from
## ControlLayout (baseline) x ControlSettings (this panel) - pure
## resolution in ControlSettings.effective(), tested headless.
func _make_controls_row(vp: Vector2) -> void:
	if profile == null:
		return
	_ctl_settings = profile.control_settings()
	_ctl_btn = Button.new()
	_ctl_btn.text = "CONTROLS"
	_ctl_btn.position = Vector2(vp.x - 264.0, vp.y - 118.0)
	_ctl_btn.size = Vector2(252.0, 30.0)
	_ctl_btn.add_theme_font_size_override("font_size", 13)
	_ctl_btn.pressed.connect(_toggle_controls)
	add_child(_ctl_btn)
	_build_controls_panel(vp)
	_ctl_panel.visible = false

func _build_controls_panel(vp: Vector2) -> void:
	_ctl_panel = Control.new()
	_ctl_panel.name = "ControlsPanel"
	_ctl_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ctl_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ctl_panel)
	# Dim layer: tap outside the panel closes it.
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if _ctl_tap_pressed(ev):
			_close_controls()
	)
	_ctl_panel.add_child(dim)
	# Panel box.
	var pw := 620.0
	var ph := 430.0
	var px := vp.x * 0.5 - pw * 0.5
	var py := vp.y * 0.5 - ph * 0.5
	var box := Control.new()
	box.name = "Box"
	box.position = Vector2(px, py)
	box.size = Vector2(pw, ph)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.draw.connect(func() -> void: _draw_ctl_box(box))
	_ctl_panel.add_child(box)
	var title := Label.new()
	title.name = "Title"
	title.text = "CONTROLS"
	title.position = Vector2(0, 12)
	title.size = Vector2(pw, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	var x := Control.new()
	x.name = "Close"
	x.position = Vector2(pw - 46.0, 10.0)
	x.size = Vector2(36.0, 36.0)
	x.mouse_filter = Control.MOUSE_FILTER_STOP
	x.draw.connect(func() -> void:
		x.draw_rect(Rect2(Vector2.ZERO, x.size), Color(0.2, 0.24, 0.32, 1.0))
		var f := ThemeDB.fallback_font
		var sz := f.get_string_size("X", HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
		x.draw_string(f, Vector2((36.0 - sz.x) * 0.5, 24.0), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	)
	x.gui_input.connect(func(ev: InputEvent) -> void:
		if _ctl_tap_pressed(ev):
			_close_controls()
	)
	box.add_child(x)
	# Numeric stepper rows (panel-relative y = 56 + i * 62).
	var rows := [
		{title = "AIM SENSITIVITY", key = "aim_sens", min = ControlSettings.AIM_SENS_MIN,
				max = ControlSettings.AIM_SENS_MAX},
		{title = "BUTTON SIZE", key = "button_scale", min = ControlSettings.SCALE_MIN,
				max = ControlSettings.SCALE_MAX},
		{title = "BUTTON OPACITY", key = "button_opacity", min = ControlSettings.OPACITY_MIN,
				max = ControlSettings.OPACITY_MAX},
		{title = "JOYSTICK SIZE", key = "joystick_scale", min = ControlSettings.SCALE_MIN,
				max = ControlSettings.SCALE_MAX},
	]
	_ctl_vals = []
	for i in rows.size():
		var r: Dictionary = rows[i]
		var y := 56.0 + float(i) * 62.0
		var lab := Label.new()
		lab.text = str(r.title)
		lab.position = Vector2(20.0, y + 12.0)
		lab.size = Vector2(250.0, 30.0)
		lab.add_theme_font_size_override("font_size", 14)
		lab.modulate = Color(0.75, 0.8, 0.9)
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(lab)
		var val := Label.new()
		val.position = Vector2(330.0, y + 10.0)
		val.size = Vector2(130.0, 34.0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.add_theme_font_size_override("font_size", 18)
		val.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(val)
		_ctl_vals.append({label = val, key = str(r.key), min = float(r.min),
				max = float(r.max)})
		_ctl_step(box, Vector2(282.0, y + 8.0), "-", str(r.key), -1.0)
		_ctl_step(box, Vector2(466.0, y + 8.0), "+", str(r.key), 1.0)
	# FIRE SIDE row (position customization: mirror the action cluster).
	var sy := 56.0 + 4.0 * 62.0
	var sside := Label.new()
	sside.text = "FIRE SIDE"
	sside.position = Vector2(20.0, sy + 12.0)
	sside.size = Vector2(250.0, 30.0)
	sside.add_theme_font_size_override("font_size", 14)
	sside.modulate = Color(0.75, 0.8, 0.9)
	sside.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(sside)
	var bl := _ctl_side_box(Vector2(300.0, sy + 8.0), "LEFT", ControlSettings.FIRE_SIDE_LEFT)
	var br := _ctl_side_box(Vector2(430.0, sy + 8.0), "RIGHT", ControlSettings.FIRE_SIDE_RIGHT)
	_ctl_side = [bl, br]
	box.add_child(bl)
	box.add_child(br)
	# RESET row.
	_ctl_reset = Button.new()
	_ctl_reset.text = "RESET TO DEFAULTS"
	_ctl_reset.position = Vector2(20.0, sy + 74.0)
	_ctl_reset.size = Vector2(pw - 40.0, 36.0)
	_ctl_reset.add_theme_font_size_override("font_size", 13)
	_ctl_reset.pressed.connect(func() -> void:
		_ctl_settings = ControlSettings.new()
		_ctl_commit()
	)
	box.add_child(_ctl_reset)
	_ctl_refresh()

## One stepper pad: a tap moves the setting one step (ControlSettings.STEP)
## toward dir, clamps to the range, persists + refreshes the labels.
func _ctl_step(parent: Control, pos: Vector2, glyph: String, key: String,
		dir: float) -> void:
	var pad := Control.new()
	pad.position = pos
	pad.size = Vector2(44.0, 44.0)
	pad.mouse_filter = Control.MOUSE_FILTER_STOP
	pad.set_meta("glyph", glyph)
	pad.set_meta("key", key)
	pad.set_meta("dir", dir)
	pad.draw.connect(func() -> void: _draw_ctl_pad(pad))
	pad.gui_input.connect(func(ev: InputEvent) -> void:
		if _ctl_tap_pressed(ev):
			_ctl_bump(key, dir)
	)
	parent.add_child(pad)

func _ctl_side_box(pos: Vector2, label_text: String, side: int) -> Control:
	var b := Control.new()
	b.position = pos
	b.size = Vector2(110.0, 44.0)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.set_meta("side_label", label_text)
	b.set_meta("side", side)
	b.draw.connect(func() -> void: _draw_ctl_side(b))
	b.gui_input.connect(func(ev: InputEvent) -> void:
		if _ctl_tap_pressed(ev):
			_ctl_settings.fire_side = side
			_ctl_commit()
	)
	return b

var _ctl_last_bump_ms := -100000
## A physical tap reaches the panel as an InputEventScreenTouch AND a
## synthesized InputEventMouseButton (Godot touch->mouse emulation); without
## this guard one tap would move a stepper two steps. Desktop mouse clicks
## (no preceding touch) are unaffected.
func _ctl_tap_pressed(ev: InputEvent) -> bool:
	if not ((ev is InputEventScreenTouch and ev.pressed) or (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT)):
		return false
	var now := Time.get_ticks_msec()
	if now - _ctl_last_bump_ms < 80:
		return false
	_ctl_last_bump_ms = now
	return true

func _ctl_bump(key: String, dir: float) -> void:
	for row in _ctl_vals:
		if str(row.key) == key:
			var cur: float = _ctl_settings.value_of(key)
			var nv := clampf(cur + dir * ControlSettings.STEP, float(row.min), float(row.max))
			_ctl_settings.value_set(key, nv)
			_ctl_commit()
			return

func _ctl_commit() -> void:
	_ctl_settings.clamp_all()
	profile.set_control_settings(_ctl_settings)
	_ctl_refresh()

func _ctl_refresh() -> void:
	for row in _ctl_vals:
		(row.label as Label).text = ("%.2f" % _ctl_settings.value_of(str(row.key)))
	for b in _ctl_side:
		(b as Control).queue_redraw()

func _toggle_controls() -> void:
	if _ctl_panel != null:
		_ctl_panel.visible = not _ctl_panel.visible

func _close_controls() -> void:
	if _ctl_panel != null:
		_ctl_panel.visible = false

func _draw_ctl_box(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Color(0.08, 0.1, 0.14, 1.0))
	c.draw_rect(r.grow(-2.0), Color(0.3, 0.4, 0.55, 1.0), false, 2.0)

func _draw_ctl_pad(c: Control) -> void:
	c.draw_circle(Vector2(22.0, 22.0), 20.0, Color(0.16, 0.19, 0.26, 1.0))
	c.draw_circle(Vector2(22.0, 22.0), 20.0, Color(0.35, 0.5, 0.7, 1.0), false, 1.5)
	var f := ThemeDB.fallback_font
	var g: String = str(c.get_meta("glyph"))
	var sz := f.get_string_size(g, HORIZONTAL_ALIGNMENT_CENTER, -1, 22)
	c.draw_string(f, Vector2(22.0 - sz.x * 0.5, 29.0), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)

func _draw_ctl_side(c: Control) -> void:
	var sel: bool = int(c.get_meta("side")) == _ctl_settings.fire_side
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Color(0.35, 0.62, 1.0, 0.95) if sel else Color(0.16, 0.19, 0.26, 1.0))
	c.draw_rect(r.grow(-1.5), Color(0.4, 0.85, 0.5, 1.0) if sel else Color(0.3, 0.36, 0.46, 1.0), false, 1.5)
	var f := ThemeDB.fallback_font
	var t: String = str(c.get_meta("side_label"))
	var sz := f.get_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, 15)
	c.draw_string(f, Vector2((r.size.x - sz.x) * 0.5, 28.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)

## D31: the shop (monetization-ready, cosmetics-only). Bottom-left button,
## mirroring the CONTROLS row; the panel lists the data-driven catalog
## (ShopBank) with the GEAR balance. Purchases go through
## PlayerProfile.buy_item (currency-agnostic, one-shot, grants a cosmetic
## variant); the variant dots then reflect the grant via
## HeroVariantBank.variant_unlocked. No real money anywhere in this path.
func _make_shop_btn(vp: Vector2) -> void:
	if profile == null:
		return
	_shop_btn = Button.new()
	_shop_btn.text = "SHOP"
	_shop_btn.position = Vector2(vp.x - 352.0, vp.y - 118.0)
	_shop_btn.size = Vector2(84.0, 30.0)
	_shop_btn.add_theme_font_size_override("font_size", 13)
	_shop_btn.pressed.connect(_toggle_shop)
	add_child(_shop_btn)

var _shop_balance: Label = null
var _shop_rows: Array = []   # {id, btn}

func _toggle_shop() -> void:
	if _shop_panel != null and _shop_panel.visible:
		_close_shop()
	else:
		_show_shop()

func _close_shop() -> void:
	if _shop_panel != null:
		_shop_panel.visible = false

func _show_shop() -> void:
	if _ctl_panel != null and _ctl_panel.visible:
		_close_controls()
	var vp := Vector2(get_viewport().get_visible_rect().size)
	if _shop_panel == null:
		_build_shop_panel(vp)
	_refresh_shop()
	_shop_panel.visible = true

func _build_shop_panel(vp: Vector2) -> void:
	_shop_panel = Control.new()
	_shop_panel.name = "ShopPanel"
	_shop_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shop_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shop_panel)
	# Dim layer: tap outside the panel closes it (same pattern as controls).
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if _ctl_tap_pressed(ev):
			_close_shop()
	)
	_shop_panel.add_child(dim)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.10, 0.15, 1.0)
	bg.position = Vector2(vp.x * 0.5 - 210.0, vp.y * 0.5 - 240.0)
	bg.size = Vector2(420.0, 480.0)
	_shop_panel.add_child(bg)
	var t := Label.new()
	t.text = "SHOP  (cosmetic only)"
	t.position = Vector2(vp.x * 0.5 - 200.0, vp.y * 0.5 - 228.0)
	t.size = Vector2(400.0, 24.0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 20)
	t.modulate = Color(0.9, 0.95, 1.0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shop_panel.add_child(t)
	_shop_balance = Label.new()
	_shop_balance.position = Vector2(vp.x * 0.5 - 200.0, vp.y * 0.5 - 204.0)
	_shop_balance.size = Vector2(400.0, 20.0)
	_shop_balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_balance.add_theme_font_size_override("font_size", 15)
	_shop_balance.modulate = Color(1.0, 0.85, 0.4)
	_shop_balance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shop_panel.add_child(_shop_balance)
	var close := Button.new()
	close.text = "CLOSE"
	close.position = Vector2(vp.x * 0.5 + 140.0, vp.y * 0.5 + 204.0)
	close.size = Vector2(64.0, 26.0)
	close.add_theme_font_size_override("font_size", 12)
	close.pressed.connect(_close_shop)
	_shop_panel.add_child(close)
	var bank := ShopBank.load_bank()
	var x0 := vp.x * 0.5 - 210.0 + 10.0
	var y := vp.y * 0.5 - 178.0
	for e in bank.items:
		if not (e is ShopItemData):
			continue
		var it: ShopItemData = e
		var nl := Label.new()
		nl.text = it.display_name
		nl.position = Vector2(x0, y)
		nl.size = Vector2(240.0, 18.0)
		nl.add_theme_font_size_override("font_size", 14)
		nl.modulate = Color(0.92, 0.94, 1.0)
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shop_panel.add_child(nl)
		var el := Label.new()
		el.text = "Unlocks " + it.desc + "  (cosmetic)"
		el.position = Vector2(x0, y + 17.0)
		el.size = Vector2(260.0, 16.0)
		el.add_theme_font_size_override("font_size", 11)
		el.modulate = Color(0.62, 0.68, 0.8)
		el.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shop_panel.add_child(el)
		var btn := Button.new()
		btn.position = Vector2(x0 + 270.0, y + 2.0)
		btn.size = Vector2(132.0, 30.0)
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(func() -> void: _buy_shop_item(it))
		_shop_panel.add_child(btn)
		_shop_rows.append({"id": it.id, "btn": btn})
		y += 54.0

func _refresh_shop() -> void:
	if _shop_panel == null:
		return
	_shop_balance.text = "GEAR: " + str(profile.currency_of(ShopBank.CURRENCY)) \
			+ "   (earned in matches)"
	for row in _shop_rows:
		var owned: bool = profile.shop_owned.has(str(row.id))
		row.btn.text = "OWNED" if owned else "BUY"
		row.btn.disabled = owned

func _buy_shop_item(it: ShopItemData) -> void:
	if not profile.buy_item(it):
		_refresh_shop()   # not enough gear: the balance row is the answer
		return
	_refresh_shop()
	# The grant unlocks the variant dots (mastery OR grant).
	for d in _variant_dots:
		_refresh_dot_state(d.st, d.set, d.hero)
		d.ctrl.queue_redraw()

