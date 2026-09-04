class_name Discovery
extends Node
## LAN discovery responder (Phase 5): listens on the UDP discovery port and
## replies to M_DISCOVER_PING (broadcast or unicast) with the live match
## state. ENet owns the game port's UDP socket, so discovery runs on its
## own port (MatchConfig.net_discovery_port) and can never collide.
## Headless-safe (no rendering).

## Live match state; must return {state, team_size, humans, target_score,
## time}. Wired by the server scene (closures over the server's vars).
var state_provider: Callable
var game_port := 7777
var server_name := "Hero Arena"

var _peer: PacketPeerUDP

func setup(port: int) -> void:
	_peer = PacketPeerUDP.new()
	# 4.7: bind() (set_mode_server() was removed); "*" = all interfaces.
	var err: int = _peer.bind(port)
	if err != OK:
		push_warning("DISCOVERY bind udp/%d failed (%d)" % [port, err])
		_peer = null
	else:
		print("DISCOVERY listening on udp/%d (game port %d)" % [port, game_port])

func _process(_delta: float) -> void:
	if _peer == null:
		return
	var n: int = _peer.get_available_packet_count()
	while n > 0:
		var pkt: PackedByteArray = _peer.get_packet()
		if pkt.size() > 1 and pkt[0] == NetProtocol.M_DISCOVER_PING:
			var ip: String = _peer.get_packet_ip()
			var port: int = _peer.get_packet_port()
			var st: Dictionary = {}
			if state_provider.is_valid():
				st = state_provider.call()
			var buf := NetProtocol.pack_discover_reply(
				int(st.get("state", NetProtocol.DISC_OPEN)),
				int(st.get("team_size", 3)),
				int(st.get("humans", 0)),
				int(st.get("target_score", 15)),
				game_port, server_name, float(st.get("time", 0.0)))
			_peer.set_dest_address(ip, port)
			_peer.put_packet(buf)
		n = _peer.get_available_packet_count()

func _exit_tree() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
