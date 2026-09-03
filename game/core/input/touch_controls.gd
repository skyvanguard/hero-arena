class_name TouchControls
extends CanvasLayer
## Mobile-first touch layer (directive §11): left virtual joystick (move),
## right-side drag (aim), FIRE / JUMP / RELOAD buttons.
## Layout is fixed for Phase 1; per-button position/size/opacity customization
## lands in Phase 6 (persisted layout, per ARCHITECTURE.md §3.9).

const JOY_RADIUS := 90.0
const AIM_SENS := 0.0032
const BTN_R := 46.0

var active := false
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
	_build()

func _build() -> void:
	var vp := get_viewport().get_visible_rect().size
	# Aim zone: right 55% of screen.
	_aim_root = Control.new()
	_aim_root.name = "AimZone"
	_aim_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_aim_root.offset_left = vp.x * 0.45
	_aim_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_aim_root.input_event.connect(_on_aim_input)
	add_child(_aim_root)
	# Joystick zone: left 45% (joystick appears where the finger lands).
	_joy_root = Control.new()
	_joy_root.name = "JoyZone"
	_joy_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_joy_root.offset_right = vp.x * 0.45
	_joy_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_joy_root.input_event.connect(_on_joy_input)
	add_child(_joy_root)
	# Buttons.
	_fire_btn = _make_button("FIRE", Vector2(vp.x - 150.0, vp.y - 130.0), 64.0, Color(0.9, 0.35, 0.3, 0.55))
	_make_button("JUMP", Vector2(vp.x - 150.0, vp.y - 240.0), BTN_R, Color(0.4, 0.8, 1.0, 0.45)).touched.connect(func() -> void: Controls.jump = true)
	_make_button("RELOAD", Vector2(vp.x - 60.0, vp.y - 240.0), BTN_R, Color(1.0, 0.8, 0.3, 0.45)).touched.connect(func() -> void: Controls.reload = true)

func _make_button(label_text: String, pos: Vector2, radius: float, color: Color) -> Control:
	var c := Control.new()
	c.name = "Btn_" + label_text
	c.position = pos - Vector2(radius, radius)
	c.size = Vector2(radius * 2.0, radius * 2.0)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.set_meta("label", label_text)
	c.set_meta("color", color)
	c.set_meta("radius", radius)
	c.draw.connect(func() -> void: _draw_button(c))
	c.input_event.connect(func(_ev_owner, event: InputEvent, _shp) -> void:
		if event is InputEventScreenTouch and event.pressed:
			c.touched.emit()
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

func _on_aim_input(_owner: Control, event: InputEvent, _shp) -> void:
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
		Controls.aim += d * AIM_SENS

func _on_joy_input(_owner: Control, event: InputEvent, _shp) -> void:
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
		var v := (drag.position - _joy_center).limit_length(JOY_RADIUS)
		_joy_vec = v
		Controls.move = Vector2(v.x / JOY_RADIUS, -v.y / JOY_RADIUS)
		queue_redraw_zone()

func queue_redraw_zone() -> void:
	if _joy_root:
		_joy_root.queue_redraw()
		_joy_root.draw.connect(func() -> void: _draw_joy(), CONNECT_ONE_SHOT)

func _draw_joy() -> void:
	if _joy_id == -1:
		return
	_joy_root.draw_circle(_joy_center, JOY_RADIUS, Color(1, 1, 1, 0.12))
	_joy_root.draw_circle(_joy_center + _joy_vec, 34.0, Color(1, 1, 1, 0.35))
