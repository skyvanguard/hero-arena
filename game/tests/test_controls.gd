extends Node
## Controls customization suite (Phase 6, round 38, D24): the touch layout
## is now data (ControlLayout baseline in content/settings) x user
## settings (ControlSettings persisted in the profile) resolved by the pure
## ControlSettings.effective(). 19 checks: baseline content sanity,
## default-resolution == the old hard-coded Phase 1 layout (lossless
## migration), every setting knob (scale/opacity/side/sens), clamping,
## dict round-trip, profile persistence (old save = stock), the headless
## TouchControls build (buttons/zones from the resolved layout), aim +
## joystick input through the layer (with sensitivity + scale), and the
## hero-select panel (steppers persist, reset works).
const VP := Vector2(1280.0, 720.0)

var passed := 0
var failed := 0
var _old_save := ""
var _had_save := false

func _ready() -> void:
	_run()

func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		passed += 1
		print("  ok  " + name)
	else:
		failed += 1
		printerr("  FAIL " + name + ("  [" + detail + "]" if detail != "" else ""))

func _near(a: float, b: float, tol := 0.6) -> bool:
	return absf(a - b) <= tol

func _btn(eff: Dictionary, id: String) -> Dictionary:
	for b in eff.buttons:
		if str(b.id) == id:
			return b
	return {}

func _run() -> void:
	# Preserve the host's save (if any) and start from a clean profile.
	var sp := "user://profile.save"
	if FileAccess.file_exists(sp):
		var f := FileAccess.open(sp, FileAccess.READ)
		_old_save = f.get_as_text()
		f.close()
		_had_save = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sp))

	# 1: baseline content loads with sane values.
	var layout: ControlLayout = ControlLayout.load_layout()
	var defs := layout.button_defs()
	check("layout: baseline loads (6 buttons, stock values)",
			layout.aim_sens == 0.0032 and layout.joy_radius == 90.0
			and _near(layout.aim_zone_split, 0.45) and defs.size() == 6,
			"sens=%s joy=%s defs=%d" % [str(layout.aim_sens), str(layout.joy_radius), defs.size()])
	var ids_ok := true
	for d in defs:
		var p: Vector2 = d.pos
		if p.x < 0.0 or p.x > 1.0 or p.y < 0.0 or p.y > 1.0:
			ids_ok = false
	check("layout: every button position is a viewport fraction in [0,1]", ids_ok)

	# 2: default resolution reproduces the old hard-coded Phase 1 layout.
	var stock := ControlSettings.new()
	var e0: Dictionary = ControlSettings.effective(layout, stock, VP)
	var ef := _btn(e0, "FIRE")
	var ej := _btn(e0, "JUMP")
	var eu := _btn(e0, "ULT")
	check("effective: defaults == the Phase 1 hard-coded layout (FIRE/JUMP/ULT)",
			_near((ef.center as Vector2).x, 1130.0) and _near((ef.center as Vector2).y, 590.0)
			and _near(float(ef.radius), 64.0)
			and _near((ej.center as Vector2).x, 1130.0) and _near((ej.center as Vector2).y, 480.0)
			and _near(float(eu.radius), 34.0) and _near(float(eu.color.a), 0.55, 0.01),
			"FIRE=%s r=%s ULT r=%s a=%s" % [str(ef.center), str(ef.radius), str(eu.radius), str(eu.color.a)])
	check("effective: defaults keep the stock sensitivity + joystick",
			_near(float(e0.aim_sens), 0.0032, 1e-6) and _near(float(e0.joy_radius), 90.0),
			"sens=%s joy=%s" % [str(e0.aim_sens), str(e0.joy_radius)])

	# 3-7: the five knobs.
	var big := ControlSettings.new()
	big.button_scale = 1.25
	var e3: Dictionary = ControlSettings.effective(layout, big, VP)
	check("setting: button_scale 1.25 scales every button radius",
			_near(float(_btn(e3, "FIRE").radius), 80.0)
			and _near(float(_btn(e3, "ULT").radius), 42.5)
			and _near(float(_btn(e3, "AB1").radius), 37.5),
			"FIRE=%s" % str(_btn(e3, "FIRE").radius))
	var dim := ControlSettings.new()
	dim.button_opacity = 0.5
	var e4: Dictionary = ControlSettings.effective(layout, dim, VP)
	check("setting: button_opacity 0.5 halves every button alpha",
			_near(float(_btn(e4, "FIRE").color.a), 0.275, 0.01)
			and _near(float(_btn(e4, "RELOAD").color.a), 0.225, 0.01),
			"FIRE a=%s" % str(_btn(e4, "FIRE").color.a))
	var jbig := ControlSettings.new()
	jbig.joystick_scale = 1.5
	var e5: Dictionary = ControlSettings.effective(layout, jbig, VP)
	check("setting: joystick_scale 1.5 scales the joystick radius",
			_near(float(e5.joy_radius), 135.0), str(e5.joy_radius))
	var sens2 := ControlSettings.new()
	sens2.aim_sens = 2.0
	var e6: Dictionary = ControlSettings.effective(layout, sens2, VP)
	check("setting: aim_sens 2.0 doubles the touch aim sensitivity",
			_near(float(e6.aim_sens), 0.0064, 1e-6), str(e6.aim_sens))
	var left := ControlSettings.new()
	left.fire_side = ControlSettings.FIRE_SIDE_LEFT
	var e7: Dictionary = ControlSettings.effective(layout, left, VP)
	check("setting: fire_side LEFT mirrors the action cluster across the screen",
			_near(float(_btn(e7, "FIRE").center.x), 150.0)
			and _near(float(_btn(e7, "ULT").center.x), 80.0)
			and _near(float(_btn(e7, "FIRE").center.y), 590.0),
			"FIRE=%s" % str(_btn(e7, "FIRE").center))

	# 8: clamping + defaults from a partial/empty dict.
	var wild := ControlSettings.new()
	wild.aim_sens = 5.0
	wild.button_opacity = 0.1
	wild.joystick_scale = 0.1
	wild.fire_side = 9
	wild.clamp_all()
	check("clamp: out-of-range values land on the range edges",
			wild.aim_sens == 3.0 and wild.button_opacity == 0.3
			and wild.joystick_scale == 0.75 and wild.fire_side == 1,
			"%s" % str(wild.to_dict()))
	var part := ControlSettings.from_dict({"aim_sens": 2.0})
	check("from_dict: a partial dict keeps the other stock defaults",
			part.aim_sens == 2.0 and part.button_scale == 1.0
			and part.fire_side == ControlSettings.FIRE_SIDE_RIGHT
			and ControlSettings.from_dict({}).aim_sens == 1.0)

	# 9: dict round-trip.
	var rt := ControlSettings.from_dict(wild.to_dict())
	check("round-trip: from_dict(to_dict()) is identical",
			rt.to_dict() == wild.to_dict())

	# 10-11: profile persistence (old save = stock; edits persist).
	var prof := PlayerProfile.load(load("res://content/progression.tres"))
	check("profile: a fresh save has stock control settings",
			prof.control_settings().aim_sens == 1.0
			and prof.control_settings().fire_side == ControlSettings.FIRE_SIDE_RIGHT)
	var cs := ControlSettings.new()
	cs.aim_sens = 1.5
	cs.fire_side = 0
	prof.set_control_settings(cs)
	var reloaded := PlayerProfile.load(load("res://content/progression.tres"))
	check("profile: control settings survive save/load",
			reloaded.control_settings().aim_sens == 1.5
			and reloaded.control_settings().fire_side == 0)

	# 12-13: headless TouchControls build from the resolved layout.
	var tc := TouchControls.new()
	add_child(tc)
	tc.layout = layout
	tc.settings = big  # button_scale 1.25
	tc.build()
	var kids := tc.get_children()
	var n_btns := 0
	var fire_c: Control = null
	for c in kids:
		if (c as Control).name.begins_with("Btn_"):
			n_btns += 1
			if (c as Control).name == "Btn_FIRE":
				fire_c = c
	check("touch: headless build produces zones + 6 resolved buttons",
			kids.size() == 8 and n_btns == 6 and fire_c != null,
			"kids=%d" % kids.size())
	var aim_zone: Control = tc.get_node_or_null("AimZone")
	check("touch: zones split at the layout's aim_zone_split",
			aim_zone != null and _near(aim_zone.offset_left, 1280.0 * 0.45, 0.6)
			and fire_c.size == Vector2(160.0, 160.0),
			"off=%s size=%s" % [str(aim_zone.offset_left if aim_zone else -1.0), str(fire_c.size if fire_c else Vector2.ZERO)])

	# 14-15: aim input through the layer honors the sensitivity setting.
	Controls.aim = Vector2.ZERO
	tc._aim_id = 7
	tc._aim_prev = Vector2(100.0, 100.0)
	var drag := InputEventScreenDrag.new()
	drag.index = 7
	drag.position = Vector2(200.0, 100.0)
	tc._on_aim_input(drag)
	check("touch: an aim drag adds px x sensitivity to Controls.aim",
			_near(Controls.aim.x, 100.0 * 0.0032, 1e-6), str(Controls.aim))
	Controls.aim = Vector2.ZERO
	tc.settings = sens2
	tc.build()
	tc._aim_id = 7
	tc._aim_prev = Vector2(100.0, 100.0)
	drag.position = Vector2(200.0, 100.0)
	tc._on_aim_input(drag)
	check("touch: aim_sens 2.0 doubles the same drag",
			_near(Controls.aim.x, 100.0 * 0.0064, 1e-6), str(Controls.aim))

	# 16-17: joystick input normalizes at the (scaled) radius.
	Controls.move = Vector2(0.5, 0.5)
	var jt := InputEventScreenTouch.new()
	jt.index = 3
	jt.position = Vector2(50.0, 300.0)
	jt.pressed = true
	tc._on_joy_input(jt)
	var jd := InputEventScreenDrag.new()
	jd.index = 3
	jd.position = Vector2(50.0 + 180.0, 300.0)  # 2x the stock radius
	tc._on_joy_input(jd)
	check("touch: a 2x overshoot clamps to move magnitude 1 at the radius",
			absf(Controls.move.length() - 1.0) < 1e-4
			and absf(tc._joy_vec.length() - 90.0) < 1e-3,
			"move=%s vec=%s" % [str(Controls.move), str(tc._joy_vec)])
	# Release the previous finger before re-pressing (same index re-press
	# reads as a release, then a re-press).
	var jrel := InputEventScreenTouch.new()
	jrel.index = 3
	jrel.pressed = false
	tc._on_joy_input(jrel)
	Controls.move = Vector2(0.5, 0.5)
	# 0.5 is below SCALE_MIN - the clamp lands it on 0.75 (90 x 0.75 = 67.5).
	var js := ControlSettings.new()
	js.joystick_scale = 0.5
	tc.settings = js
	tc.build()
	jt.position = Vector2(50.0, 300.0)
	tc._on_joy_input(jt)
	jd.position = Vector2(50.0 + 180.0, 300.0)
	tc._on_joy_input(jd)
	check("touch: an out-of-range scale clamps and clamps at the scaled radius (67.5)",
			absf(tc._joy_vec.length() - 67.5) < 1e-3
			and _near(Controls.move.x, 1.0, 1e-4),
			"vec=%s move=%s" % [str(tc._joy_vec), str(Controls.move)])
	tc.queue_free()

	# 18-19: the hero-select panel (headless build + persistence).
	var hs := HeroSelect.new()
	hs.profile = PlayerProfile.load(load("res://content/progression.tres"))
	hs.progression = load("res://content/progression.tres")
	add_child(hs)
	var panel: Control = hs.get_node_or_null("ControlsPanel")
	check("panel: built hidden behind the CONTROLS button",
			panel != null and not panel.visible and hs._ctl_btn != null)
	# The persistence check above left aim_sens 1.5 on disk - commit stock
	# first so the stepper check starts from defaults.
	hs._ctl_settings = ControlSettings.new()
	hs._ctl_commit()
	hs._ctl_bump("aim_sens", 1.0)
	var after_bump := hs.profile.control_settings()
	var lab_ok := true
	for row in hs._ctl_vals:
		if str(row.key) == "aim_sens":
			lab_ok = (row.label as Label).text == "1.25"
	check("panel: a +stepper tap bumps aim_sens to 1.25 and persists + labels",
			after_bump.aim_sens == 1.25 and lab_ok,
			"%s / labels=%s" % [str(after_bump.aim_sens), str(lab_ok)])
	# One physical tap = a ScreenTouch press + a synthesized MouseButton
	# press (Godot touch->mouse emulation): the dedup guard must collapse
	# that pair into a single step (1.25, not 1.50).
	hs._ctl_settings = ControlSettings.new()
	hs._ctl_commit()
	var tp := InputEventScreenTouch.new()
	tp.pressed = true
	if hs._ctl_tap_pressed(tp):
		hs._ctl_bump("aim_sens", 1.0)
	var mp := InputEventMouseButton.new()
	mp.pressed = true
	mp.button_index = MOUSE_BUTTON_LEFT
	if hs._ctl_tap_pressed(mp):
		hs._ctl_bump("aim_sens", 1.0)
	check("panel: a tap's synthesized mouse press does not double-step",
			hs.profile.control_settings().aim_sens == 1.25,
			str(hs.profile.control_settings().aim_sens))
	hs._ctl_settings.fire_side = ControlSettings.FIRE_SIDE_LEFT
	hs._ctl_commit()
	check("panel: the FIRE SIDE toggle persists to the profile",
			hs.profile.control_settings().fire_side == ControlSettings.FIRE_SIDE_LEFT)
	hs._ctl_reset.pressed.emit()
	var after_reset := hs.profile.control_settings()
	check("panel: RESET restores the stock settings",
			after_reset.aim_sens == 1.0 and after_reset.fire_side
			== ControlSettings.FIRE_SIDE_RIGHT
			and after_reset.button_opacity == 1.0,
			"%s" % str(after_reset.to_dict()))
	hs.queue_free()

	# Restore the host's save.
	if _had_save:
		var f2 := FileAccess.open(sp, FileAccess.WRITE)
		if f2 != null:
			f2.store_string(_old_save)
			f2.close()

	print("CONTROLS SUITE: %d passed, %d failed" % [passed, failed])
	get_tree().quit(failed)
