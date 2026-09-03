class_name DesktopInput
extends Node
## Desktop binding of the shared input contract (KB + mouse).

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		set_physics_process(false)

func _physics_process(_delta: float) -> void:
	Controls.move = Vector2(
			Input.get_axis("move_left", "move_right"),
			Input.get_axis("move_down", "move_up"))
	Controls.fire = Input.is_action_pressed("fire")
	if Input.is_action_just_pressed("jump"):
		Controls.jump = true
	if Input.is_action_just_pressed("reload"):
		Controls.reload = true
	if Input.is_action_just_pressed("ability1"):
		Controls.ability1 = true
	if Input.is_action_just_pressed("ability2"):
		Controls.ability2 = true
	if Input.is_action_just_pressed("ultimate"):
		Controls.ultimate = true
