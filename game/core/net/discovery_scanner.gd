## Client-side scanner: pings the discovery port (always broadcast, plus an
## optional unicast — the unicast also works across the emulator's NAT to
## the host, where broadcasts do not reach) and collects replies, deduped by
## IP. Pump pump() every frame from UI code until finished.
class_name DiscoveryScanner
extends Node
signal found(info: Dictionary)
signal done(count: int)

const BROADCAST_IP := "255.255.255.255"

var timeout_s := 2.0
var finished := false
var _peer: PacketPeerUDP
var _deadline := 0.0
var _results := {}  # ip -> info (info.ip set)

func start(unicast_host := "") -> void:
	finished = false
	_results = {}
	_peer = PacketPeerUDP.new()
	_peer.bind(0)  # connectionless, ephemeral local port (4.7: no set_mode_client)
	_peer.set_broadcast_enabled(true)
	var port := MatchConfig.net_discovery_port
	var ping := NetProtocol.pack_discover_ping("heroarena-client")
	_peer.set_dest_address(BROADCAST_IP, port)
	_peer.put_packet(ping)
	if unicast_host != "":
		_peer.set_dest_address(unicast_host, port)
		_peer.put_packet(ping)
	_deadline = Time.get_ticks_msec() / 1000.0 + timeout_s

func pump() -> void:
	if finished or _peer == null:
		return
	var n: int = _peer.get_available_packet_count()
	while n > 0:
		var pkt: PackedByteArray = _peer.get_packet()
		if pkt.size() > 8 and pkt[0] == NetProtocol.M_DISCOVER_REPLY:
			var d: Dictionary = NetProtocol.unpack_discover_reply(pkt)
			d.ip = str(_peer.get_packet_ip())
			if not _results.has(d.ip):
				_results[d.ip] = d
				found.emit(d)
		n = _peer.get_available_packet_count()
	if Time.get_ticks_msec() / 1000.0 >= _deadline:
		finished = true
		if _peer != null:
			_peer.close()
			_peer = null
		done.emit(_results.size())

func results() -> Array:
	return _results.values()
