extends Node
## Central input state (ARCHITECTURE.md §3.2 input contract).
## Touch layer and desktop layer both write here; gameplay only reads here.
## move: x=right, y=forward. aim: per-frame look delta (x=yaw, y=pitch).

var move := Vector2.ZERO
var aim := Vector2.ZERO
var fire := false
var jump := false      # edge-triggered; consume_jump()
var reload := false    # edge-triggered; consume_reload()
var ability1 := false  # edge-triggered; consume_ability1() (Q / Q-btn)
var ability2 := false  # edge-triggered; consume_ability2() (E / E-btn)
var ultimate := false  # edge-triggered; consume_ultimate() (F / F-btn)

func consume_aim() -> Vector2:
	var v := aim
	aim = Vector2.ZERO
	return v

func consume_jump() -> bool:
	var v := jump
	jump = false
	return v

func consume_reload() -> bool:
	var v := reload
	reload = false
	return v

func consume_ability1() -> bool:
	var v := ability1
	ability1 = false
	return v

func consume_ability2() -> bool:
	var v := ability2
	ability2 = false
	return v

func consume_ultimate() -> bool:
	var v := ultimate
	ultimate = false
	return v
