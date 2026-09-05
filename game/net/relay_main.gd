extends Node
## Dedicated relay scene (Phase 5, round 29): NAT traversal for match
## servers. Run (hosted, one relay per region is plenty for v1):
##   godot --headless --path game res://net/relay.tscn -- --port=7800
## Docker (same image as the server, different scene + port):
##   docker run -d -p 7800:7800/udp -p 7901-8156:7901-8156/udp \
##       heroarena/server -- res://net/relay.tscn -- --port=7800
## (the virtual-port range must be published; see core/net/relay.gd)
func _ready() -> void:
	var port := Relay.CONTROL_PORT
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.substr(7))
	var r := Relay.new()
	add_child(r)
	r.setup(port)
