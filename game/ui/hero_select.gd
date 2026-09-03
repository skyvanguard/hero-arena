class_name HeroSelect
extends CanvasLayer
## Hero select screen (Phase 2): roster cards from HeroRegistry + DEPLOY.
## Emits hero_deployed(HeroData). Render-side only (skipped headless).

signal hero_deployed(hero: HeroData)
signal range_deployed(hero: HeroData)

var _deploy_btn: Control
var _practice_btn: Control
var _hero: HeroData = null
var _cards: Array = []
var _diff_btns: Array = []

func _ready() -> void:
	_hero = HeroRegistry.default_hero()
	_build()

func _select(hd: HeroData) -> void:
	if _hero == hd:
		return
	_hero = hd
	for c in _cards:
		c.control.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
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
	_make_difficulty_row(vp)

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
		c.draw.connect(_draw_diff)
		c.gui_input.connect(func(ev: InputEvent) -> void:
			if (ev is InputEventScreenTouch and ev.pressed) or (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
				MatchConfig.set_difficulty(String(c.get_meta("diff_id")))
				for b in _diff_btns:
					b.queue_redraw()
		)
		add_child(c)
		_diff_btns.append(c)

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
