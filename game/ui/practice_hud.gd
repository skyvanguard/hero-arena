class_name PracticeHUD
extends CanvasLayer
## Practice range HUD (render-side only): session timer, cumulative damage,
## per-dummy HP bars, RESET + BACK buttons. Reads from the authoritative
## PracticeManager; never mutates sim state itself (buttons emit signals).

signal reset_pressed
signal back_pressed

var manager: PracticeManager
var dummies: Array = []

var _time_label: Label
var _dmg_label: Label
var _bars: Array = []   # {fill: ColorRect, label: Label, ch: CharacterEntity}
var _reset_btn: Control
var _back_btn: Control

func setup(mgr: PracticeManager, dummy_list: Array) -> void:
	manager = mgr
	dummies = dummy_list
	layer = 10  # buttons must sit above the touch aim zone for input priority
	_build()

func _build() -> void:
	var vp := Vector2(get_viewport().get_visible_rect().size)

	var panel := Panel.new()
	panel.position = Vector2(12, 12)
	panel.size = Vector2(250, 96)
	add_child(panel)

	_time_label = Label.new()
	_time_label.position = Vector2(12, 14)
	_time_label.size = Vector2(240, 26)
	_time_label.add_theme_font_size_override("font_size", 20)
	add_child(_time_label)

	_dmg_label = Label.new()
	_dmg_label.position = Vector2(12, 44)
	_dmg_label.size = Vector2(240, 26)
	_dmg_label.add_theme_font_size_override("font_size", 18)
	add_child(_dmg_label)

	var hint := Label.new()
	hint.text = "Dummies reset when untouched"
	hint.position = Vector2(12, 72)
	hint.size = Vector2(240, 18)
	hint.modulate = Color(0.6, 0.65, 0.75)
	hint.add_theme_font_size_override("font_size", 12)
	add_child(hint)

	# Per-dummy HP bars (bottom-left stack).
	var by := vp.y - 140.0
	for i in dummies.size():
		var d: CharacterEntity = dummies[i]
		var lbl := Label.new()
		lbl.text = "dummy %d" % (i + 1)
		lbl.position = Vector2(12, by)
		lbl.size = Vector2(120, 20)
		lbl.add_theme_font_size_override("font_size", 13)
		add_child(lbl)
		var bg := Panel.new()
		bg.position = Vector2(136, by)
		bg.size = Vector2(220, 20)
		add_child(bg)
		var fill := ColorRect.new()
		fill.color = Color(0.3, 0.85, 0.4)
		fill.position = Vector2(138, by + 2)
		fill.size = Vector2(216, 16)
		add_child(fill)
		_bars.append({fill = fill, ch = d, label = lbl})
		by += 28.0

	_reset_btn = _make_button("RESET", Vector2(vp.x - 240, vp.y - 56), reset_pressed)
	_back_btn = _make_button("BACK", Vector2(vp.x - 128, vp.y - 56), back_pressed)

func _make_button(text: String, pos: Vector2, sig: Signal) -> Control:
	var c := Control.new()
	c.position = pos
	c.size = Vector2(116, 40)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.draw.connect(_draw_button.bind(c, text))
	c.gui_input.connect(func(ev: InputEvent) -> void:
		if (ev is InputEventScreenTouch and ev.pressed) or (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
			sig.emit()
	)
	add_child(c)
	return c

func _draw_button(c: Control, text: String) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.2, 0.3, 0.45, 1.0))
	c.draw_rect(Rect2(Vector2.ZERO, c.size).grow(-2.0), Color(0.5, 0.7, 1.0, 1.0), false, 2.0)
	var tw := _approx_text_width(text, 20)
	c.draw_string(ThemeDB.fallback_font, Vector2((c.size.x - tw) * 0.5, 26), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.95, 0.97, 1.0))

func _approx_text_width(text: String, font_size: int) -> float:
	return float(text.length()) * font_size * 0.6

func _process(_delta: float) -> void:
	if manager == null:
		return
	var mm := int(manager.elapsed) / 60
	var ss := int(manager.elapsed) % 60
	_time_label.text = "TIME  %02d:%02d" % [mm, ss]
	_dmg_label.text = "DMG   %d" % int(manager.session_damage())
	for b in _bars:
		var ch: CharacterEntity = b.ch
		if ch == null or not is_instance_valid(ch):
			continue
		var frac := clampf(ch.hp / float(ch.max_hp), 0.0, 1.0)
		b.fill.size.x = 216.0 * frac
		b.label.text = "%d/%d" % [int(ch.hp), int(ch.max_hp)]
