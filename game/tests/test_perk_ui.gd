extends Node

# D25 (Phase 7): perk UI headless smoke — the choice panel, the tap ->
# pick signal flow, and the picked-perk badge, for both HUDs (local and
# net). No rendering is exercised (headless); the emu session that shows
# the pixels is tracked separately (PERFORMANCE.md).

var ok := 0
var fail := 0

func check(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		ok += 1
		print("  ok  " + name)
	else:
		fail += 1
		print("  FAIL " + name + ("  [" + extra + "]" if extra != "" else ""))

func _ready() -> void:
	var w := World.new()
	w.name = "World"
	add_child(w)
	w.perk_system = PerkSystem.new()
	w.add_child(w.perk_system)
	w.perk_system.setup(w, load("res://content/perks/perks.tres"), 7)
	var hd: HeroData = null
	for h in HeroRegistry.HEROES:
		if (h as HeroData).id == "kestrel":
			hd = h
	var me := HeroFactory.create(0, false, hd.color, hd)
	me.position = Vector3(0, 0, 0)
	me.protected_until = -1.0
	w.add_child(me)
	w.register_character(me)
	var foe := HeroFactory.create(1, false, hd.color, hd)
	foe.position = Vector3(2, 0, 0)
	foe.protected_until = -1.0
	w.add_child(foe)
	w.register_character(foe)

	# ---- local HUD ----
	var hud := HUD.new()
	add_child(hud)
	var picked: Array = []
	hud.perk_chosen.connect(func(i: int) -> void: picked.append(i))
	hud.setup(w, me)
	# level up through the real event pipeline
	for i in 81:
		foe.hp = 150.0
		w.damage(foe, 10.0, me, false, foe.global_position)
	check("local: level-up shows the choice panel", hud._perk_panel.visible)
	check("local: the title names the level", hud._perk_title.text.to_upper().find("LEVEL 2") >= 0,
		hud._perk_title.text)
	var c0: PerkData = w.perk_system._pending[me][0]
	check("local: card 0 shows the offered perk name", hud._perk_names[0].text == c0.name,
		"got '" + hud._perk_names[0].text + "' want '" + c0.name + "'")
	# tap card 0 (real InputEvent through the card's gui_input)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	hud._perk_cards[0].gui_input.emit(ev)
	check("local: tapping a card emits perk_chosen(0)", picked == [0])
	# the pick flows through the Controls contract like every other action
	Controls.perk_pick = int(picked[0])
	w.perk_system.pick(me, int(picked[0]))
	check("local: after the pick the panel hides", not hud._perk_panel.visible)
	check("local: the badge shows the picked perk", hud._perk_badge.text.find(c0.name) >= 0,
		hud._perk_badge.text)

	# ---- net HUD ----
	var nhud := NetHUD.new()
	add_child(nhud)
	var npicked: Array = []
	nhud.perk_chosen.connect(func(i: int) -> void: npicked.append(i))
	# the net HUD builds its fixed nodes in _ready (already run: added above)
	var c1: PerkData = c0
	if w.perk_system.has_pending(me):
		c1 = w.perk_system._pending[me][1]
	var choices: Array = [c0, c1]
	var names: Array = []
	var descs: Array = []
	for d in choices:
		names.append((d as PerkData).name)
		descs.append((d as PerkData).desc)
	nhud.set_perk_choices(names, descs, 2)
	check("net: set_perk_choices shows the panel", nhud._perk_panel.visible)
	check("net: the badge is empty while picking", nhud._perk_badge.text == "", nhud._perk_badge.text)
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_LEFT
	ev2.pressed = true
	nhud._perk_cards[1].gui_input.emit(ev2)
	check("net: tapping card 1 emits perk_chosen(1)", npicked == [1])
	nhud.set_perk_picked(c1.name, 2)
	check("net: set_perk_picked hides the panel", not nhud._perk_panel.visible)
	check("net: the badge shows the picked perk", nhud._perk_badge.text.find(c1.name) >= 0,
		nhud._perk_badge.text)

	# keys 1/2 on desktop drive the same signal (local HUD)
	var picked2: Array = []
	hud.perk_chosen.connect(func(i: int) -> void: picked2.append(i))
	for i in 119:
		foe.hp = 150.0
		w.damage(foe, 10.0, me, false, foe.global_position)
	if hud._perk_panel.visible:
		var kev := InputEventKey.new()
		kev.keycode = KEY_2
		kev.pressed = true
		hud._unhandled_key_input(kev)
		check("local: key 2 emits perk_chosen(1)", picked2 == [1])
	else:
		check("local: key 2 emits perk_chosen(1)", false, "panel not visible for the key test")

	print("PERK-UI SUITE: %d passed, %d failed" % [ok, fail])
	get_tree().quit(fail)
