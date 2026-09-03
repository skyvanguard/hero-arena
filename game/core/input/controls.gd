extends Node
## Central input state (ARCHITECTURE.md §3.2 input contract).
## Touch layer and desktop layer both write here; gameplay only reads here.
## move: x=right, y=forward. aim: per-frame look delta (x=yaw, y=pitch).

var move := Vector2.ZERO
var aim := Vector2.ZERO
var fire := false
var jump := false      # edge-triggered; consume_jump()
var reload := false    # edge-triggered; consume_reload()

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
