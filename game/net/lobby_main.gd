extends Node
## Headless lobby service scene (Phase 5 v1). Run:
##   godot --headless --path game res://net/lobby.tscn \
##     -- --port=7790 --region=latam_saopaulo [--fill=60]
var lobby: LobbyServer

func _ready() -> void:
	var port := 7790
	var region := "latam_saopaulo"
	var fill := 60.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.substr(7))
		elif a.begins_with("--region="):
			region = a.substr(9)
		elif a.begins_with("--fill="):
			fill = float(a.substr(7))
	lobby = LobbyServer.new()
	add_child(lobby)
	lobby.setup(port, region, fill)

func _physics_process(delta: float) -> void:
	lobby.tick(delta)
