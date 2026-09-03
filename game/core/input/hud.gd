class_name HUD
extends CanvasLayer
## In-match HUD (directive §11/§27): HP, ammo, respawn, kill feed, score,
## hit marker, damage flash. Glanceable, no monetization noise.

var world: World
var player: CharacterEntity
var _hp_bar: ProgressBar
var _hp_label: Label
var _ammo_label: Label
var _respawn_label: Label
var _score_label: Label
var _feed: VBoxContainer
var _hitmark: Label
var _flash_rect: ColorRect
var _ult_bar: ProgressBar
var _flash_t := 0.0
var _hp := 100.0

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

	_feed = VBoxContainer.new()
	_feed.position = Vector2(vp.x - 320, 16)
	_feed.size = Vector2(300, 200)
	root.add_child(_feed)

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

func _on_world_event(name: String, data: Dictionary) -> void:
	match name:
		"hp_changed":
			var ch: CharacterEntity = data.ch
			if ch == player:
				_hp = float(data.hp)
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
		"respawn":
			pass

func _update_ammo() -> void:
	if player != null and is_instance_valid(player) and player.weapon != null:
		var w: Weapon = player.weapon
		if w.reserve_infinite:
			_ammo_label.text = "%d / ∞" % w.ammo
		else:
			_ammo_label.text = "%d" % w.ammo

func _add_feed_line(line: String) -> void:
	var l := Label.new()
	l.text = line
	l.add_theme_font_size_override("font_size", 15)
	_feed.add_child(l)
	while _feed.get_child_count() > 6:
		_feed.get_child(0).queue_free()

func _process(delta: float) -> void:
	if player != null and player.ability != null:
		_ult_bar.value = player.ability.charge
		_ult_bar.modulate = Color(1.8, 1.5, 0.9) if player.ability.can_activate_ult() else Color.WHITE

	if _hitmark.modulate.a > 0.0:
		_hitmark.modulate.a = maxf(0.0, _hitmark.modulate.a - delta * 6.0)
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash_rect.color.a = clampf(_flash_t / 0.35, 0.0, 0.5)
	else:
		_flash_rect.color.a = 0.0
	if player != null and is_instance_valid(player):
		var s0: int = world.score.get(player.team, 0)
		var enemy_team := 1 - player.team
		var s1: int = world.score.get(enemy_team, 0)
		_score_label.text = "%d  —  %d" % [s0, s1]
		if not player.alive:
			var left := maxf(0.0, player.respawn_time - (world.time - player.death_time))
			_respawn_label.text = "RESPAWNING  %d" % int(ceilf(left))
		else:
			_respawn_label.text = ""
