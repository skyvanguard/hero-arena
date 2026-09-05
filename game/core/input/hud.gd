class_name HUD
extends CanvasLayer
## In-match HUD (directive §11/§27): HP, ammo, respawn, kill feed, score,
## hit marker, damage flash, perk choice (D25). Glanceable, no
## monetization noise.

signal perk_chosen(idx: int)  # D25: card tapped / 1-2 key (-> Controls.perk_pick)
##
## MEMORY NOTE (Phase 4, verified on the Android emulator / GL renderer):
## every canvas invalidation from a Control write churns a 2D canvas
## texture and RSS grows through allocator fragmentation. Per-frame
## writes OOM'd a 3v3 match in ~20 s (3.2 GB). Rules applied here:
##  - label .text is written only when the string changes;
##  - bars/flash are written on coarse steps only;
##  - the kill feed is a FIXED pool of labels (round-robin .text
##    overwrite) — creating/freeing Label controls per kill was the
##    biggest single churn source (bisect: +feed alone -> 2.6 GB in 30 s).

var world: World
var player: CharacterEntity
var _hp_bar: ProgressBar
var _hp_label: Label
var _ammo_label: Label
var _respawn_label: Label
var _score_label: Label
var _timer_label: Label
var _timer_shown := -1
var _feed: VBoxContainer
var _feed_lines: Array[Label] = []
var _feed_next := 0
var _hitmark: Label
var _flash_rect: ColorRect
var _ult_bar: ProgressBar
var _flash_t := 0.0
var _hp := 100.0
var _score_txt := ""
var _respawn_txt := ""
var _ult_shown := -1.0
var _ult_ready := false
var _hp_shown := -1.0
const FEED_LINES := 6
var _perk_panel: Control
var _perk_title: Label
var _perk_names: Array[Label] = []
var _perk_descs: Array[Label] = []
var _perk_badge: Label
var _perk_shown := false

func setup(world_: World, player_: CharacterEntity) -> void:
	world = world_
	player = player_
	_build()
	world.world_event.connect(_on_world_event)

func _build() -> void:
	var vp := get_viewport().get_visible_rect().size
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_hp_bar = ProgressBar.new()
	_hp_bar.position = Vector2(24, vp.y - 64)
	_hp_bar.size = Vector2(280, 22)
	_hp_bar.max_value = 100.0
	_hp_bar.show_percentage = false
	root.add_child(_hp_bar)
	_hp_label = Label.new()
	_hp_label.position = Vector2(24, vp.y - 92)
	_hp_label.add_theme_font_size_override("font_size", 16)
	root.add_child(_hp_label)

	_ult_bar = ProgressBar.new()
	_ult_bar.position = Vector2(24, vp.y - 78)
	_ult_bar.size = Vector2(280, 8)
	_ult_bar.max_value = 100.0
	_ult_bar.show_percentage = false
	root.add_child(_ult_bar)

	_ammo_label = Label.new()
	_ammo_label.position = Vector2(vp.x * 0.5 - 40, vp.y - 56)
	_ammo_label.add_theme_font_size_override("font_size", 26)
	root.add_child(_ammo_label)

	_respawn_label = Label.new()
	_respawn_label.set_anchors_preset(Control.PRESET_CENTER)
	_respawn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_respawn_label.add_theme_font_size_override("font_size", 34)
	_respawn_label.text = ""
	root.add_child(_respawn_label)

	_score_label = Label.new()
	_score_label.position = Vector2(vp.x * 0.5 - 80, 16)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 24)
	root.add_child(_score_label)
	_timer_label = Label.new()
	_timer_label.position = Vector2(vp.x * 0.5 - 80, 44)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 15)
	_timer_label.modulate = Color(0.85, 0.9, 1.0, 0.9)
	root.add_child(_timer_label)

	_feed = VBoxContainer.new()
	_feed.position = Vector2(vp.x - 320, 16)
	_feed.size = Vector2(300, 200)
	root.add_child(_feed)
	# Fixed label pool (see MEMORY NOTE): round-robin overwrite, no
	# per-kill node add/free.
	for i in FEED_LINES:
		var l := Label.new()
		l.text = ""
		l.add_theme_font_size_override("font_size", 15)
		_feed.add_child(l)
		_feed_lines.append(l)

	_hitmark = Label.new()
	_hitmark.set_anchors_preset(Control.PRESET_CENTER)
	_hitmark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hitmark.text = "✕"
	_hitmark.add_theme_font_size_override("font_size", 40)
	_hitmark.modulate = Color(1, 1, 1, 0)
	root.add_child(_hitmark)

	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(0.8, 0.05, 0.05, 0.0)
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash_rect)

	# D25: perk choice panel — built once (fixed nodes, memory rule), shown
	# on level-up. Two cards (tap or keys 1/2); the pick flows through the
	# Controls contract like every other action.
	_perk_panel = Control.new()
	_perk_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_perk_panel.visible = false
	root.add_child(_perk_panel)
	var cw := 250.0
	var ch := 96.0
	var gap := 24.0
	var x0 := vp.x * 0.5 - cw - gap * 0.5
	var y0 := vp.y * 0.5 - ch * 0.5 - 14.0
	_perk_title = Label.new()
	_perk_title.position = Vector2(0, y0 - 30)
	_perk_title.size = Vector2(vp.x, 24)
	_perk_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_perk_title.add_theme_font_size_override("font_size", 20)
	_perk_title.modulate = Color(1.0, 0.92, 0.55)
	_perk_panel.add_child(_perk_title)
	for i in 2:
		var bg := ColorRect.new()
		bg.color = Color(0.08, 0.1, 0.16, 0.92)
		bg.position = Vector2(x0 + i * (cw + gap), y0)
		bg.size = Vector2(cw, ch)
		_perk_panel.add_child(bg)
		var nm := Label.new()
		nm.position = Vector2(x0 + i * (cw + gap) + 12, y0 + 10)
		nm.size = Vector2(cw - 24, 22)
		nm.add_theme_font_size_override("font_size", 18)
		_perk_panel.add_child(nm)
		var ds := Label.new()
		ds.position = Vector2(x0 + i * (cw + gap) + 12, y0 + 38)
		ds.size = Vector2(cw - 24, 48)
		ds.add_theme_font_size_override("font_size", 13)
		ds.modulate = Color(0.85, 0.88, 0.95)
		_perk_panel.add_child(ds)
		var hint := Label.new()
		hint.text = "[%d]  TAP" % (i + 1)
		hint.position = Vector2(x0 + i * (cw + gap) + 12, y0 + ch - 22)
		hint.size = Vector2(cw - 24, 16)
		hint.add_theme_font_size_override("font_size", 11)
		hint.modulate = Color(0.6, 0.7, 0.9)
		_perk_panel.add_child(hint)
		_perk_names.append(nm)
		_perk_descs.append(ds)
		# The card itself eats the touch (the bg is a child, STOP filter).
		var card := Control.new()
		card.position = Vector2(x0 + i * (cw + gap), y0)
		card.size = Vector2(cw, ch)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		var ci := i
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventScreenTouch and ev.pressed:
				perk_chosen.emit(ci)
			elif ev is InputEventMouseButton and ev.pressed \
					and ev.button_index == MOUSE_BUTTON_LEFT:
					perk_chosen.emit(ci))
		_perk_panel.add_child(card)
	_perk_badge = Label.new()
	_perk_badge.position = Vector2(24, vp.y - 112)
	_perk_badge.size = Vector2(280, 16)
	_perk_badge.add_theme_font_size_override("font_size", 13)
	_perk_badge.modulate = Color(1.0, 0.9, 0.5)
	_perk_badge.text = ""
	root.add_child(_perk_badge)

func _on_world_event(name: String, data: Dictionary) -> void:
	match name:
		"hp_changed":
			var ch: CharacterEntity = data.ch
			if ch == player:
				_hp = float(data.hp)
				if int(_hp) != int(_hp_shown):
					_hp_shown = _hp
					_hp_bar.max_value = float(data.max)
					_hp_bar.value = _hp
					_hp_label.text = "%d / %d" % [int(_hp), int(float(data.max))]
		"reload_start":
			if data.ch == player:
				_ammo_label.text = "RELOADING…"
		"reload_done":
			if data.ch == player:
				_update_ammo()
		"shot":
			if data.shooter == player:
				_update_ammo()
				_hitmark.modulate = Color(1, 1, 1, 0.9)
		"hit":
			if data.target == player:
				_flash_t = 0.35
		"kill":
			_add_feed_line("%s ✕ %s%s" % [
					str(data.killer), str(data.victim), " (HS)" if data.headshot else ""])
		"perk_level_up":
			var chp: CharacterEntity = data.ch
			if chp == player:
				_show_perk_cards(data.choices, int(data.level))
			else:
				_add_feed_line("%s leveled up" % str(chp.display_name))
		"perk_picked":
			var ch2: CharacterEntity = data.ch
			var pd: PerkData = data.perk
			if ch2 == player:
				_perk_panel.visible = false
				_perk_shown = false
				_perk_badge.text = "LV%d · %s" % [int(data.level), str(pd.name)]
			else:
				_add_feed_line("%s → %s" % [str(ch2.display_name), str(pd.name)])
		"respawn":
			pass

func _update_ammo() -> void:
	if player != null and is_instance_valid(player) and player.weapon != null:
		var w: Weapon = player.weapon
		if w.reserve_infinite:
			_ammo_label.text = "%d / ∞" % w.ammo
		else:
			_ammo_label.text = "%d" % w.ammo

func _show_perk_cards(choices: Array, level: int) -> void:
	_perk_title.text = "LEVEL %d — CHOOSE A PERK" % level
	for i in 2:
		if i < choices.size():
			var d: PerkData = choices[i]
			_perk_names[i].text = d.name
			_perk_descs[i].text = d.desc
		else:
			_perk_names[i].text = "—"
			_perk_descs[i].text = ""
	_perk_panel.visible = true
	_perk_shown = true

func _unhandled_key_input(event: InputEvent) -> void:
	# D25 desktop: keys 1/2 pick the perk card (only while the panel is up;
	# the event is then consumed so it never reaches gameplay input too).
	if not _perk_shown:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			perk_chosen.emit(0)
			event.accept()
		elif event.keycode == KEY_2:
			perk_chosen.emit(1)
			event.accept()

func _add_feed_line(line: String) -> void:
	# Overwrite the oldest pooled label in place (see MEMORY NOTE).
	var l: Label = _feed_lines[_feed_next]
	_feed_next = (_feed_next + 1) % _feed_lines.size()
	l.text = line

func _process(delta: float) -> void:
	if player != null and is_instance_valid(player) and player.ability != null:
		# Quantized: 0.5 steps keep the bar smooth without per-frame writes.
		var charge: float = player.ability.charge
		if absf(charge - _ult_shown) >= 0.5 or player.ability.can_activate_ult() != _ult_ready:
			_ult_shown = charge
			_ult_ready = player.ability.can_activate_ult()
			_ult_bar.value = charge
			_ult_bar.modulate = Color(1.8, 1.5, 0.9) if _ult_ready else Color.WHITE

	if _hitmark.modulate.a > 0.0:
		_hitmark.modulate.a = maxf(0.0, _hitmark.modulate.a - delta * 6.0)
	# Damage flash: write on 0.05 steps only (see MEMORY NOTE).
	var target_a: float
	if _flash_t > 0.0:
		_flash_t -= delta
		target_a = clampf(_flash_t / 0.35, 0.0, 0.5)
	else:
		target_a = 0.0
	if absf(_flash_rect.color.a - target_a) >= 0.05:
		_flash_rect.color.a = target_a
	if player != null and is_instance_valid(player):
		var s0: int = world.score.get(player.team, 0)
		var enemy_team := 1 - player.team
		var s1: int = world.score.get(enemy_team, 0)
		var stxt := "%d  —  %d" % [s0, s1]
		if stxt != _score_txt:
			_score_txt = stxt
			_score_label.text = stxt
		# Match timer: write only when the displayed second changes.
		var remain: int
		if world.match_over:
			remain = -1
		else:
			remain = int(ceilf(maxf(0.0, world.match_duration - world.time)))
		if remain != _timer_shown:
			_timer_shown = remain
			if remain < 0:
				_timer_label.text = "FINAL"
			else:
				_timer_label.text = "%d:%02d" % [remain / 60, remain % 60]
		var rtxt := ""
		if not player.alive:
			var left := maxf(0.0, player.respawn_time - (world.time - player.death_time))
			rtxt = "RESPAWNING  %d" % int(ceilf(left))
		if rtxt != _respawn_txt:
			_respawn_txt = rtxt
			_respawn_label.text = rtxt
