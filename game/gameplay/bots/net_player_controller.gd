class_name NetPlayerController
extends Node
## Human input over the wire, expressed through the shared controller
## interface (AGENTS.md: anything a human does, a bot does through the same
## entry points). The server feeds it from NetInput each tick; the aim is
## ABSOLUTE camera yaw/pitch (the client accumulates look deltas locally),
## which keeps the server stateless about the client's camera.
var hero: Hero = null
var world_: World = null
var input: NetInput = null

func setup(h: Hero, _target: CharacterEntity, w: World, _diff: Resource) -> void:
	hero = h
	world_ = w

func step(_world: World, _dt: float) -> void:
	if hero == null or not hero.alive:
		return
	if input == null:
		hero.move_input = Vector2.ZERO
		hero.want_fire = false
		return
	hero.move_input = input.move.limit_length(1.0)
	hero.want_fire = input.fire
	# Aim: absolute yaw/pitch -> world direction. The render camera is
	# rotated PI on Y inside the rig (HeroFactory), so at yaw=0/pitch=0 it
	# looks along the rig +Z == the character's forward. With rig rotation
	# (yaw around Y, camera pitch around X): dir = (cos p sin y, sin p,
	# cos p cos y). Verified: yaw=0,pitch=0 -> +Z (project forward).
	var d := Vector3(
		cos(input.pitch) * sin(input.yaw),
		sin(input.pitch),
		cos(input.pitch) * cos(input.yaw))
	hero.aim_target = hero.global_position + d * 10.0
	# Face the aim even while not firing (a player turns with the camera).
	hero.face_toward(hero.global_position + d)
	var e := input.consume_edges()
	if (e & 1) != 0:
		hero.buffer_jump()
	if (e & 2) != 0 and hero.weapon != null:
		hero.weapon.start_reload()
	if (e & 4) != 0 and hero.ability != null:
		hero.ability.cast(0)
	if (e & 8) != 0 and hero.ability != null:
		hero.ability.cast(1)
	if (e & 16) != 0 and hero.ability != null:
		hero.ability.activate_ult()
	# D25: perk picks (edge bits 32/64); the server validates through the
	# same pick() entry point a bot uses (server authority: a wrong index is
	# simply rejected, the cards stay up).
	if (e & 32) != 0 and world_ != null and world_.perk_system != null:
		world_.perk_system.pick(hero, 0)
	if (e & 64) != 0 and world_ != null and world_.perk_system != null:
		world_.perk_system.pick(hero, 1)
