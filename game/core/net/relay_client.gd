class_name RelayClient
extends Node
## Server-side relay registration (Phase 5, round 29): outbound UDP to the
## relay (the one direction a NAT mapping exists for). Sends R_REG, waits
## for R_OK (virtual port), then R_PING keep-alives every 10 s so the NAT
## mapping stays open even with no clients. The relay address doubles as the
## advertised address: the match registers itself in the lobby as
## <relay_ip>:<virtual_port> (see server_main --relay=).
signal registered(vport: int)
signal failed(reason: String)

var relay_ip := ""
var relay_port := Relay.CONTROL_PORT
var game_port := 0
var vport := 0
var _sock: PacketPeerUDP
var _last_send := 0
var _registered_at := 0
var _fail_count := 0
## Max silent R_OK wait before re-registering (5 s) and the give-up count
## (10 x 5 s = 50 s: a relay that never answers is not retried forever).
const OK_TIMEOUT_MS := 5000
const MAX_RETRIES := 10
const PING_MS := Relay.PING_INTERVAL_MS

func setup(host: String, port: int, gport: int) -> void:
	relay_ip = host
	relay_port = port
	game_port = gport
	_sock = PacketPeerUDP.new()
	var err := _sock.bind(0)
	if err != OK:
		failed.emit("bind(0) failed: %d" % err)
		return
	_sock.set_dest_address(host, port)
	_send_reg()
	print("RELAY-CLIENT registering at %s:%d (game port %d)" % [host, port, gport])

func _send_reg() -> void:
	# Token 0 for now (future: lobby-issued match secret for relay auth).
	var buf := PackedByteArray([0x52, 0x47, 0, 0, 0, 0,
		game_port & 0xFF, (game_port >> 8) & 0xFF])
	_sock.put_packet(buf)
	_last_send = Time.get_ticks_msec()

func _process(_d: float) -> void:
	if _sock == null:
		return
	var now := Time.get_ticks_msec()
	if vport > 0:
		if now - _last_send >= PING_MS:
			var ping := PackedByteArray([0x52, 0x50])
			_sock.put_packet(ping)
			_last_send = now
		return
	# Awaiting R_OK.
	while _sock.get_available_packet_count() > 0:
		var pkt: PackedByteArray = _sock.get_packet()
		if pkt.size() >= 4 and pkt[0] == 0x52 and pkt[1] == 0x4F:
			vport = int(pkt[2]) | (int(pkt[3]) << 8)
			_registered_at = now
			print("RELAY-CLIENT registered: virtual port %d (advertise %s:%d)" %
					[vport, relay_ip, vport])
			registered.emit(vport)
			return
	if now - _last_send >= OK_TIMEOUT_MS:
		_fail_count += 1
		if _fail_count > MAX_RETRIES:
			_sock.close()
			_sock = null
			failed.emit("no R_OK from %s:%d after %d retries" %
					[relay_ip, relay_port, MAX_RETRIES])
			return
		_send_reg()
