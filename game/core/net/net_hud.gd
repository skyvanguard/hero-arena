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
