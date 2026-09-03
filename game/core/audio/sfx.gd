class_name Sfx
extends Node
## Original procedural SFX playback (Phase 2). Render-side: created only when
## not headless (ARCHITECTURE: gameplay must run headless). Maps world events
## to generated WAVs in assets/audio/sfx/ (tools/gen_sfx.gd).

const SOUNDS := {
	"fire": preload("res://assets/audio/sfx/sfx_fire.wav"),
	"dash": preload("res://assets/audio/sfx/sfx_dash.wav"),
	"burst": preload("res://assets/audio/sfx/sfx_burst.wav"),
	"ult": preload("res://assets/audio/sfx/sfx_ult.wav"),
	"hit": preload("res://assets/audio/sfx/sfx_hit.wav"),
	"kill": preload("res://assets/audio/sfx/sfx_kill.wav"),
	"jump": preload("res://assets/audio/sfx/sfx_jump.wav"),
	"reload": preload("res://assets/audio/sfx/sfx_reload.wav"),
	"respawn": preload("res://assets/audio/sfx/sfx_respawn.wav"),
}

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var player_ref: CharacterEntity = null

func setup(world: World, player: CharacterEntity) -> void:
	player_ref = player
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	world.world_event.connect(_on_event)

func play(id: String, volume_db: float = 0.0) -> void:
	if _players.is_empty():
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	var stream: AudioStream = SOUNDS.get(id)
	if stream == null:
		return
	var pos := Vector3.ZERO
	if player_ref != null:
		pos = player_ref.global_position
	var dist := 1.0
	if id == "fire" or id == "hit" or id == "burst":
		dist = 1.0  # positional distance handled by caller via volume_db
	p.stream = stream
	p.volume_db = volume_db
	p.play()

func _on_event(name: String, data: Dictionary) -> void:
	match name:
		"shot":
			var shooter: CharacterEntity = data.get("shooter")
			var vol := -8.0 if shooter == player_ref else -14.0
			play("fire", vol)
		"hit":
			var target: CharacterEntity = data.get("target")
			var vol2 := -6.0 if target == player_ref else -16.0
			play("hit", vol2)
		"kill":
			play("kill", -6.0)
		"jump":
			var ch: CharacterEntity = data.get("ch")
			if ch == player_ref:
				play("jump", -10.0)
		"reload_start":
			var ch2: CharacterEntity = data.get("ch")
			if ch2 == player_ref:
				play("reload", -10.0)
		"respawn":
			play("respawn", -10.0)
		"ability_cast":
			var id: String = str(data.get("id"))
			var hero: CharacterEntity = data.get("hero")
			var vol3 := -6.0 if hero == player_ref else -14.0
			match id:
				"glide_burst": play("dash", vol3)
				"wingfire": play("burst", vol3)
				"kestrel_dive": play("ult", -4.0)
