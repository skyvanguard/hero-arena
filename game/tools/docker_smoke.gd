extends Node
## Phase 8 release smoke test (D33): a REAL ENet client on the host
## connecting to the dedicated server published by docker (127.0.0.1:7777
## = the container's published UDP port). Proves the one-command release
## claim end-to-end: docker run image -> a client from another process
## gets a slot and receives snapshots.
##
## Runs as a SCENE (not --script): the client's dependency chain uses
## autoloads (MatchConfig & co), which only exist when the project boots
## normally with its main scene.
var client: MatchClient
var waited := 0.0
var got_snapshot := false

func _ready() -> void:
	client = MatchClient.new()
	add_child(client)
	client.setup("127.0.0.1:7777", HeroRegistry.default_hero())

func _process(delta: float) -> void:
	waited += delta
	if client.my_id >= 0 and client._ring.size() >= 3:
		got_snapshot = true
	if got_snapshot and waited > 8.0:
		print("SMOKE PASS: docker-published server -> external ENet client"
				+ " (slot + snapshots, my_id=%d after %.1f s)"
				% [client.my_id, waited])
		get_tree().quit(0)
	if waited > 25.0:
		print("SMOKE FAIL: no slot/snapshots in 25 s (my_id=%d ring=%d)"
				% [client.my_id, client._ring.size()])
		get_tree().quit(1)
