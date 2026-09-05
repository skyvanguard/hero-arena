class_name NetHUD
extends CanvasLayer
## Minimal net-match HUD (Phase 5 v1): score, timer, own HP, latest kill,
## connection status. Every write is on-change (GL canvas memory rule from
## the Round 7 3v3 OOM bisect - see PERFORMANCE.md).
var _score_label: Label
var _timer_label: Label
var _hp_bg: ColorRect
var _hp_fg: ColorRect
var _feed_label: Label
var _state_label: Label
var _score_shown := ""
var _timer_shown := ""
var _hp_shown := -1.0
var _feed_shown := ""
var _state_shown := ""
var my_team := 0
var _ctl_bg: ColorRect
var _ctl_fg: ColorRect
var _ctl_label: Label
var _ctl_shown := ""
## D25: perk choice (level-up) panel + picked-perk badge.
signal perk_chosen(idx: int)
var _perk_panel: Control
var _perk_title: Label
var _perk_names: Array[Label] = []
var _perk_descs: Array[Label] = []
var _perk_cards: Array = []
var _perk_badge: Label
var _perk_shown := false

func _ready() -> void:
	layer = 5
	var vp := get_viewport().get_visible_rect().size
	_score_label = _mk_label(vp.x * 0.5 - 70.0, 12.0, 140.0, 26.0, 22)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label = _mk_label(vp.x * 0.5 - 70.0, 42.0, 140.0, 16.0, 13)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.modulate = Color(0.75, 0.8, 0.9)
	_feed_label = _mk_label(vp.x - 300.0, 14.0, 290.0, 20.0, 13)
	_feed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed_label.modulate = Color(0.9, 0.9, 0.95)
	_state_label = _mk_label(12.0, 14.0, 200.0, 18.0, 12)
	_state_label.modulate = Color(0.6, 0.7, 0.9)
	var bw := 160.0
	_hp_bg = ColorRect.new()
	_hp_bg.color = Color(0.1, 0.12, 0.16, 0.85)
	_hp_bg.position = Vector2(12.0, vp.y - 34.0)
	_hp_bg.size = Vector2(bw, 12.0)
	_hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_bg)
	_hp_fg = ColorRect.new()
	_hp_fg.color = Color(0.3, 0.85, 0.5)
	_hp_fg.position = Vector2(12.0, vp.y - 34.0)
	_hp_fg.size = Vector2(bw, 12.0)
	_hp_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_fg)
	# Control-mode objective bar (Phase 6 v1): under the score/timer column.
	# Hidden (empty) until a control snapshot arrives; writes are on-change.
	_ctl_bg = ColorRect.new()
	_ctl_bg.color = Color(0.1, 0.12, 0.16, 0.85)
	_ctl_bg.position = Vector2(vp.x * 0.5 - 70.0, 62.0)
	_ctl_bg.size = Vector2(140.0, 6.0)
	_ctl_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ctl_bg)
	_ctl_fg = ColorRect.new()
	_ctl_fg.color = Color(0.8, 0.8, 0.9, 0.9)
	_ctl_fg.position = Vector2(vp.x * 0.5 - 70.0, 62.0)
	_ctl_fg.size = Vector2(140.0, 6.0)
	_ctl_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ctl_fg)
	_ctl_label = _mk_label(vp.x * 0.5 - 70.0, 70.0, 140.0, 14.0, 11)
	_ctl_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ctl_label.modulate = Color(0.75, 0.8, 0.9)
	# D25: perk panel (fixed nodes; shown on level-up, picked perk -> badge).
	_perk_panel = Control.new()
	_perk_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_perk_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # only the cards block input
	_perk_panel.visible = false
	add_child(_perk_panel)
	var cw := 250.0
	var chh := 96.0
	var gap := 24.0
	var x0 := vp.x * 0.5 - cw - gap * 0.5
	var y0 := vp.y * 0.5 - chh * 0.5 - 14.0
	_perk_title = _mk_label(0, y0 - 30, vp.x, 24, 20)
	_perk_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_perk_title.modulate = Color(1.0, 0.92, 0.55)
	_perk_panel.add_child(_perk_title)
	for i in 2:
		var bg := ColorRect.new()
		bg.color = Color(0.08, 0.1, 0.16, 0.92)
		bg.position = Vector2(x0 + i * (cw + gap), y0)
		bg.size = Vector2(cw, chh)
		_perk_panel.add_child(bg)
		var nm := _mk_label(x0 + i * (cw + gap) + 12, y0 + 10, cw - 24, 22, 18)
		var ds := _mk_label(x0 + i * (cw + gap) + 12, y0 + 38, cw - 24, 48, 13)
		ds.modulate = Color(0.85, 0.88, 0.95)
		var hint := _mk_label(x0 + i * (cw + gap) + 12, y0 + chh - 22, cw - 24, 16, 11)
		hint.text = "[%d]  TAP" % (i + 1)
		hint.modulate = Color(0.6, 0.7, 0.9)
		_perk_panel.add_child(nm)
		_perk_panel.add_child(ds)
		_perk_panel.add_child(hint)
		_perk_names.append(nm)
		_perk_descs.append(ds)
		var card := Control.new()
		card.position = Vector2(x0 + i * (cw + gap), y0)
		card.size = Vector2(cw, chh)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		var ci := i
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventScreenTouch and ev.pressed:
				perk_chosen.emit(ci)
			elif ev is InputEventMouseButton and ev.pressed \
					and ev.button_index == MOUSE_BUTTON_LEFT:
					perk_chosen.emit(ci))
		_perk_cards.append(card)
		_perk_panel.add_child(card)
	_perk_badge = _mk_label(12.0, vp.y - 52.0, 200.0, 16.0, 13)
	_perk_badge.modulate = Color(1.0, 0.9, 0.5)

func _mk_label(x: float, y: float, w: float, h: float, fs: int) -> Label:
	var l := Label.new()
	l.position = Vector2(x, y)
	l.size = Vector2(w, h)
	l.add_theme_font_size_override("font_size", fs)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func set_score(s0: int, s1: int) -> void:
	var mine: int = s0 if my_team == 0 else s1
	var theirs: int = s1 if my_team == 0 else s0
	var t := "%d  -  %d" % [mine, theirs]
	if t != _score_shown:
		_score_shown = t
		_score_label.text = t

func set_time(remaining: int) -> void:
	var t := "FINAL" if remaining < 0 else "%d:%02d" % [remaining / 60, remaining % 60]
	if t != _timer_shown:
		_timer_shown = t
		_timer_label.text = t

func set_hp(ratio: float) -> void:
	# Quantize to 1/20 steps - a per-frame float write churns the GL canvas.
	var q := roundf(clampf(ratio, 0.0, 1.0) * 20.0) / 20.0
	if q != _hp_shown:
		_hp_shown = q
		var w: float = _hp_bg.size.x * q
		_hp_fg.size = Vector2(w, _hp_bg.size.y)
		_hp_fg.color = Color(0.3, 0.85, 0.5) if q > 0.4 else (Color(0.9, 0.7, 0.3) if q > 0.2 else Color(0.9, 0.3, 0.25))

func set_feed(line: String) -> void:
	if line != _feed_shown:
		_feed_shown = line
		_feed_label.text = line

func set_state(s: String) -> void:
	if s != _state_shown:
		_state_shown = s
		_state_label.text = s

## D25: show the level-up choice (names/descs come from the client's own
## perk pool — same resource the server loaded).
func set_perk_choices(names: Array, descs: Array, level: int) -> void:
	_perk_title.text = "LEVEL %d — CHOOSE A PERK" % level
	for i in 2:
		if i < names.size():
			_perk_names[i].text = str(names[i])
			_perk_descs[i].text = str(descs[i])
		else:
			_perk_names[i].text = "—"
			_perk_descs[i].text = ""
	_perk_panel.visible = true
	_perk_shown = true

## D25: pick confirmed (or a level-up the player missed) -> badge + hide.
func set_perk_picked(name: String, level: int) -> void:
	_perk_panel.visible = false
	_perk_shown = false
	_perk_badge.text = "LV%d · %s" % [level, name]

func _unhandled_key_input(event: InputEvent) -> void:
	if not _perk_shown:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			perk_chosen.emit(0)
			event.accept()
		elif event.keycode == KEY_2:
			perk_chosen.emit(1)
			event.accept()

## Control point state (Phase 6 v1, D16). owner: -1 neutral / 0 / 1; team:
## the team progress runs toward (-1 none); progress 0..1. Bar = fill toward
## the occupying team (full + owner color when held); label names the state.
func set_control(owner: int, team: int, progress: float,
		label_override: String = "") -> void:
	var q := roundf(clampf(progress, 0.0, 1.0) * 10.0) / 10.0
	var col := Color(0.8, 0.8, 0.9, 0.9)
	var who: int = owner if owner >= 0 else team
	if who == 0:
		col = Color(0.3, 0.55, 0.95, 0.95)
	elif who == 1:
		col = Color(0.95, 0.35, 0.3, 0.95)
	var t := label_override
	if t == "":
		if owner == 0:
			t = "POINT: %s" % ("YOURS" if my_team == 0 else "ENEMY")
		elif owner == 1:
			t = "POINT: %s" % ("YOURS" if my_team == 1 else "ENEMY")
		elif team >= 0:
			t = "CAPTURE %d%%" % int(q * 100.0)
	var key: Array = [owner, team, q, t]
	if str(key) != _ctl_shown:
		_ctl_shown = str(key)
		_ctl_fg.size = Vector2(140.0 * q, 6.0)
		_ctl_fg.color = col
		_ctl_label.text = t
