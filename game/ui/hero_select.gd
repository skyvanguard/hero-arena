class_name HeroSelect
extends CanvasLayer
## Hero select screen (Phase 2): roster cards from HeroRegistry + DEPLOY.
## Emits hero_deployed(HeroData). Render-side only (skipped headless).

signal hero_deployed(hero: HeroData)

var _deploy_btn: Control
var _hero: HeroData = null

func _ready() -> void:
	_hero = HeroRegistry.default_hero()
	_build()

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
	var total_w := float(HeroRegistry.HEROES.size()) * 220.0
	var cards_x := vp.x * 0.5 - total_w * 0.5
	var i := 0
	for h in HeroRegistry.HEROES:
		var hd: HeroData = h
		var card := Panel.new()
		card.position = Vector2(cards_x + i * 220.0, vp.y * 0.5 - 140.0)
		card.size = Vector2(200, 280)
		add_child(card)

		var ic := ColorRect.new()
		ic.color = hd.color
		ic.position = Vector2(40, 20)
		ic.size = Vector2(120, 90)
		card.add_child(ic)

		var nm := Label.new()
		nm.text = hd.display_name
		nm.position = Vector2(10, 120)
		nm.size = Vector2(180, 30)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_font_size_override("font_size", 24)
		card.add_child(nm)

		var role := Label.new()
		role.text = _role_text(hd)
		role.position = Vector2(10, 152)
		role.size = Vector2(180, 20)
		role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		role.add_theme_font_size_override("font_size", 14)
		role.modulate = Color(0.75, 0.8, 0.9)
		card.add_child(role)

		var kit := Label.new()
		kit.text = _kit_text(hd)
		kit.position = Vector2(10, 178)
		kit.size = Vector2(180, 92)
		kit.add_theme_font_size_override("font_size", 12)
		kit.modulate = Color(0.65, 0.7, 0.8)
		card.add_child(kit)
		i += 1

	var hint := Label.new()
	hint.text = "TAP DEPLOY  (or ENTER)"
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position.y = -150.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.modulate = Color(0.6, 0.65, 0.75)
	add_child(hint)

	_make_deploy(vp)

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
