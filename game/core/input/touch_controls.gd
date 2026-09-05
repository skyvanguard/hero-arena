class_name TouchControls
extends CanvasLayer
## Mobile-first touch layer (directive §11): left virtual joystick (move),
## right-side drag (aim), action buttons. D24: the layout resolves from
## the ControlLayout baseline (content data) x the user's ControlSettings
## (persisted in the profile) via the pure ControlSettings.effective() -
## position (fire side), size (button/joystick scale), opacity and aim
## sensitivity are all customizable in the hero-select CONTROLS panel.
## Defaults reproduce the Phase 1 hard-coded layout exactly.

var active := false
var layout: ControlLayout = null
var settings: ControlSettings = null
## Final resolved layout (ControlSettings.effective) - populated by build().
var eff := {}
var _aim_id := -1
var _aim_prev := Vector2.ZERO
var _joy_id := -1
var _joy_center := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _fire_btn: Control
var _joy_root: Control
var _aim_root: Control

func _ready() -> void:
	var has_touch := DisplayServer.has_feature(DisplayServer.FEATURE_TOUCHSCREEN)
	active = has_touch and OS.has_feature("mobile")
	if not active:
		set_process_input(false)
		return
	build()

## (Re)build the whole touch layer from layout x settings x viewport.
## Public so headless tests (and a future in-game settings entry) can
## rebuild without a device.
func build() -> void:
	if layout == null:
		layout = ControlLayout.load_layout()
	if settings == null:
		settings = ControlSettings.new()
	var vp := get_viewport().get_visible_rect().size
	eff = ControlSettings.effective(layout, settings, vp)
	for c in get_children():
		c.queue_free()
	_aim_root = Control.new()
	_aim_root.name = "AimZone"
	_aim_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_aim_root.offset_left = vp.x * float(eff.aim_zone_split)
	_aim_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_aim_root.gui_input.connect(_on_aim_input)
	add_child(_aim_root)
	# Joystick zone: left side (joystick appears where the finger lands).
	_joy_root = Control.new()
	_joy_root.name = "JoyZone"
	_joy_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_joy_root.offset_right = vp.x * float(eff.aim_zone_split)
	_joy_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_joy_root.gui_input.connect(_on_joy_input)
	add_child(_joy_root)
	# Buttons from the resolved layout.
	for b in eff.buttons:
		var id := str(b.id)
		var c := _make_button(id, (b.center as Vector2), float(b.radius),
				b.color as Color, _action_of(id))
		if id == "FIRE":
			_fire_btn = c
	queue_redraw_zone()

## Button id -> Controls action (the shared input contract).
func _action_of(id: String) -> Callable:
	match id:
		"FIRE":
			return func() -> void: pass  # fire is level-triggered on the touch itself
		"JUMP":
			return func() -> void: Controls.jump = true
		"RELOAD":
			return func() -> void: Controls.reload = true
		"AB1":
			return func() -> void: Controls.ability1 = true
		"AB2":
			return func() -> void: Controls.ability2 = true
		"ULT":
			return func() -> void: Controls.ultimate = true
	return func() -> void: pass

func _make_button(label_text: String, center: Vector2, radius: float, color: Color,
		on_touched: Callable) -> Control:
	var c := Control.new()
	c.name = "Btn_" + label_text
	c.position = center - Vector2(radius, radius)
	c.size = Vector2(radius * 2.0, radius * 2.0)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.set_meta("label", label_text)
	c.set_meta("color", color)
	c.set_meta("radius", radius)
	c.draw.connect(func() -> void: _draw_button(c))
	c.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenTouch and event.pressed:
			on_touched.call()
		if label_text == "FIRE" and event is InputEventScreenTouch:
			Controls.fire = event.pressed
	)
	add_child(c)
	return c

func _draw_button(c: Control) -> void:
	var r: float = c.get_meta("radius")
	var col: Color = c.get_meta("color")
	var lab: String = c.get_meta("label")
	c.draw_circle(Vector2(r, r), r, col)
	var font := ThemeDB.fallback_font
	var ts := font.get_string_size(lab, HORIZONTAL_ALIGNMENT_CENTER, -1, r * 0.5)
	c.draw_string(font, Vector2(r - ts.x * 0.5, r + ts.y * 0.35), lab,
			HORIZONTAL_ALIGNMENT_LEFT, -1, r * 0.5, Color.WHITE)

func _on_aim_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_aim_id = t.index
			_aim_prev = t.position
		elif t.index == _aim_id:
			_aim_id = -1
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index != _aim_id:
			return
		var d := drag.position - _aim_prev
		_aim_prev = drag.position
		Controls.aim += d * float(eff.aim_sens)

func _on_joy_input(event: InputEvent) -> void:
	var jr := float(eff.joy_radius)
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _joy_id == -1:
			_joy_id = t.index
			_joy_center = t.position
			_joy_vec = Vector2.ZERO
		elif t.index == _joy_id:
			_joy_id = -1
			_joy_vec = Vector2.ZERO
			Controls.move = Vector2.ZERO
		queue_redraw_zone()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index != _joy_id:
			return
		var v := (drag.position - _joy_center).limit_length(jr)
		_joy_vec = v
		Controls.move = Vector2(v.x / jr, -v.y / jr)
		queue_redraw_zone()

func queue_redraw_zone() -> void:
	if _joy_root != null:
		_joy_root.queue_redraw()
		_joy_root.draw.connect(func() -> void: _draw_joy(), CONNECT_ONE_SHOT)

func _draw_joy() -> void:
	if _joy_id == -1:
		return
	_joy_root.draw_circle(_joy_center, float(eff.joy_radius), Color(1, 1, 1, 0.12))
	_joy_root.draw_circle(_joy_center + _joy_vec, float(eff.joy_radius) * 0.38,
			Color(1, 1, 1, 0.35))
