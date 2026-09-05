extends Node
## Capture (CTF) mode suite (Phase 6, round 31, D17): 10 deterministic
## checks over the flag state machine (setup, steal, carry-follow, drop on
## death, own-team re-secure, capture + return, 2nd capture wins, timeout
## tiebreaks, in-place reset) + a bot decision check.
const FIXED_DT := 1.0 / 60.0

var passes := 0
var fails := 0
var world: World
var mode: CaptureMode
var chars: Array = []
var last: Dictionary = {}

func check(name: String, cond: bool, detail := "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		fails += 1
		print("FAIL ", name, ("  [" + detail + "]" if detail != "" else ""))

func frames(n: int):
	for i in n:
		await get_tree().physics_frame

func _new_world() -> World:
	if world != null:
		world.queue_free()
	for c in chars:
		c.queue_free()
	chars = []
	await frames(2)  # freed bodies leave the physics space first
	world = World.new()
	world.name = "World"
	world.target_score = 999
	world.match_duration = 300.0
	add_child(world)
	add_child(Arena.build(world))
	mode = CaptureMode.new()
	world.mode = mode
	mode.setup(world)
	world.world_event.connect(_on_event)
	return world

func _on_event(name: String, data: Dictionary) -> void:
	last = data

func _char(team: int, pos: Vector3) -> Hero:
	var h := HeroFactory.create(team, false)
	h.position = pos
	add_child(h)
	world.register_character(h)
	chars.append(h)
	return h

func _step(seconds: float) -> void:
	var n := int(ceilf(seconds / FIXED_DT))
	for i in n:
		world.step(FIXED_DT)

func _ready() -> void:
	randomize()
	# 1) Registry.
	var capm := ModeRegistry.get_mode("capture")
	var escm := ModeRegistry.get_mode("escort")
	check("registry: capture/escort resolve, ids complete",
			capm is CaptureMode and escm is EscortMode
			and ModeRegistry.ids().has("capture") and ModeRegistry.ids().has("escort"),
			str(ModeRegistry.ids()))
	# 2) Setup: flags at the CENTRAL spawn of each team (the bases).
	await _new_world()
	var base0: Vector3 = world.spawn_points[0][1]
	var base1: Vector3 = world.spawn_points[1][1]
	check("capture: setup places flags at team bases",
			world.flags[0] == base0 and world.flags[1] == base1
			and world.flag_bases[0] == base0 and world.flag_carrier[0] == null,
			"f0=%s f1=%s" % [world.flags[0], world.flags[1]])
	# 3) Steal: an enemy character in the steal radius takes the flag.
	var thief := _char(1, base0 + Vector3(1.0, 0.0, 0.0))
	last = {}
	_step(0.1)
	check("capture: enemy in radius steals the flag",
			world.flag_carrier[0] == thief and last.get("flag", -1) == 0
			and int(last.get("carrier", -1)) == 1,
			"carrier=%s ev=%s" % [str(world.flag_carrier[0] != null), str(last)])
	# 4) The carried flag follows the carrier.
	thief.position = Vector3(0.0, 0.9, 0.0)
	_step(0.1)
	check("capture: carried flag follows the carrier",
			world.flags[0].distance_to(thief.global_position) < 0.01,
			"flag=%s thief=%s" % [world.flags[0], thief.global_position])
	# 5) The carrier dies -> the flag drops where they fell. (kill(target,
	# source): the thief is the target; the killer stays far enough away to
	# not re-steal the drop.)
	var killer := _char(0, Vector3(8.0, 0.9, 0.0))
	var drop_pos: Vector3 = thief.global_position
	world.kill(thief, killer, false)
	check("capture: carrier death drops the flag",
			world.flag_carrier[0] == null
			and world.flags[0].distance_to(drop_pos) < 0.5
			and not thief.alive,
			"carrier=%s flag=%s drop=%s" % [str(world.flag_carrier[0] != null), world.flags[0], drop_pos])
	# 6) The flag's OWN team can re-carry a dropped flag (re-secure).
	var saver := _char(0, drop_pos + Vector3(0.5, 0.0, 0.0))
	_step(0.1)
	check("capture: own team re-secures a dropped flag",
			world.flag_carrier[0] == saver,
			"carrier=%s" % str(world.flag_carrier[0] != null))
	# 7) The re-secured flag is dropped again, and an enemy carries it home:
	# scores a capture + the flag returns to its base (no win at 1).
	world.kill(saver, killer, false)
	var thief2 := _char(1, drop_pos + Vector3(0.5, 0.0, 0.0))
	_step(0.1)
	thief2.position = base1 + Vector3(0.5, 0.0, 0.0)
	last = {}
	_step(0.1)
	check("capture: enemy flag home scores and returns",
			int(world.captures[1]) == 1 and world.flag_carrier[0] == null
			and world.flags[0] == base0 and not world.match_over,
			"cap=%s flag=%s over=%s" % [str(world.captures), world.flags[0], world.match_over])
	# 8) The second capture ends the match for that team.
	var thief3 := _char(1, base0 + Vector3(0.5, 0.0, 0.0))
	_step(0.1)
	thief3.position = base1 + Vector3(0.5, 0.0, 0.0)
	last = {}
	_step(0.1)
	check("capture: 2nd capture wins the match",
			world.match_over and world.winner == 1
			and int(last.get("score", [0, 0])[1]) == 2,
			"over=%s w=%d score=%s" % [world.match_over, world.winner, str(last.get("score"))])
	# 9) Timeout tiebreaks: 1-1 -> the holder of the ENEMY flag wins;
	#    1-1 with both flags free -> draw.
	await _new_world()
	world.captures = {0: 1, 1: 1}
	world.time = 299.5
	var holder := _char(1, base0 + Vector3(0.5, 0.0, 0.0))
	_step(0.1)  # thief steals team0's flag
	_step(0.6)
	check("capture: tied timeout goes to the enemy-flag holder",
			world.match_over and world.winner == 1, "w=%d" % world.winner)
	await _new_world()
	world.captures = {0: 1, 1: 1}
	world.time = 299.5
	_step(0.6)
	check("capture: tied timeout with both flags free is a draw",
			world.match_over and world.winner == -1, "w=%d" % world.winner)
	# 10) In-place reset clears the flag state (D14 compatibility).
	await _new_world()
	var t4 := _char(1, base0 + Vector3(0.5, 0.0, 0.0))
	_step(0.1)
	check("capture: pre-reset flag was stolen", world.flag_carrier[0] == t4, "")
	world.reset()
	check("capture: reset returns flags to bases, clears carriers/captures",
			world.flags[0] == world.flag_bases[0] and world.flags[1] == world.flag_bases[1]
			and world.flag_carrier[0] == null and world.flag_carrier[1] == null
			and int(world.captures[0]) == 0 and int(world.captures[1]) == 0
			and not world.match_over,
			"flags=%s cap=%s" % [str(world.flags), str(world.captures)])
	# 11) Bot: an unengaged bot's CAPTURE goal targets the enemy flag.
	await _new_world()
	var bot := _char(0, Vector3(-6.0, 0.9, 0.0))
	var perc := BotPerception.new()
	add_child(perc)
	perc.setup(bot, world, BotDifficulties.by_id("normal"))
	var dec := BotDecision.new()
	add_child(dec)
	dec.setup(BotDifficulties.by_id("normal"), 0)
	dec.decide(world, perc, bot)
	var dg: Vector3 = dec.goal - world.flags[1]
	dg.y = 0.0
	check("bot: unengaged bot heads for the enemy flag (CAPTURE)",
			dec.intent == BotDecision.Intent.CAPTURE and dg.length() <= 2.0,
			"intent=%d dist=%.2f" % [dec.intent, dg.length()])
	_done()

func _done() -> void:
	print("MODE-CAPTURE SUITE: %d passed, %d failed" % [passes, fails])
	get_tree().quit(fails)
