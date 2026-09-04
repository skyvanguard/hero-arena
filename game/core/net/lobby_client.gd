class_name LobbyClient
extends Node
## UDP client for the lobby (Phase 5 v1). Two usage modes:
##  - app (hero-select "PLAY"): connect -> ping (RTT display) -> join queue
##    -> progress (queue) -> assign (auto-join the matched game server)
##  - match server (registration): connect -> reg -> state updates
## pump() runs in _process: poll the socket, read lines, dispatch.
##
## Godot 4.7.2 note: the lobby is UDP because the 4.7 TCP stack does not
## create real system sockets in headless builds (see lobby_server.gd).
## Reliability model:
##  - every client->server message carries a seq; the server dedupes
##    per (peer, type, seq)
##  - join and reg are RETRANSMITTED with the same seq until acked
##    (assign/queue / regack); the server handlers are idempotent
##  - "connected" = first pong received (we ping from the start);
##    5 s of silence -> disconnected (we keep pinging and can recover)

signal connected_ok
signal disconnected
signal hello(info: Dictionary)
signal pong(rtt_ms: float)
signal queue(info: Dictionary)
signal assign(info: Dictionary)
signal regack(info: Dictionary)

var host := ""
var port := 0
var _peer: PacketPeerUDP
var _buf := ""
var _last_ping_at := -1.0
var _last_pong_at := -1.0
var _ping_acc := 0.0
var _ping_every := 1.0
var _seq_ping := 0
var _seq_join := 0
var _seq_reg := 0
var _connected := false
## Any lobby message (ping/pong/queue/...) refreshes this; the connect state
## machine must use RECEIVED time, not the last pong (a stale pong re-fires
## the connect branch forever once the lobby goes silent).
var _last_rx_at := -1.0
## join session: {msg, next_at, last_ack_at, started_at, params}
var _pending_join: Dictionary = {}
var _pending_reg: Dictionary = {}
var _retry_in := 2500
## Rejoin (fresh seq) if the server has been silent this long: covers a
## lost assign (the server dedupes same-seq join retransmits, so a stuck
## client must start a new join session to be re-added to the queue).
var _rejoin_after := 4000

func setup(h: String, p: int) -> void:
	host = h
	port = p
	_peer = PacketPeerUDP.new()
	# 4.7: bind(0) = ephemeral local port (no set_mode_client).
	var err: int = _peer.bind(0)
	if err != 0:
		push_warning("LOBBY-CLIENT bind failed: %s" % error_string(err))
		_peer = null
		return
	_peer.set_dest_address(h, p)
	# Kick off liveness immediately: the first pong means "lobby up".
	_ping_acc = _ping_every  # force a ping on the first pump

## Start the match-server registration (with retransmit until regack).
func register_match(ip: String, game_port: int, region: String,
		team_size: int, name: String) -> void:
	if _seq_reg > 0 and not _pending_reg.is_empty():
		return  # already registered / in flight
	_seq_reg += 1
	var m := {t = LobbyProtocol.T_REG, seq = _seq_reg, ip = ip,
			port = game_port, region = region, team_size = team_size, name = name}
	_pending_reg = {msg = m, next_at = Time.get_ticks_msec()}
	_put(m)

## Join the match queue (retransmit until queue/assign arrives).
func join_queue(region: String, party: int, skill: int, name: String) -> void:
	var now := Time.get_ticks_msec()
	_seq_join += 1
	var m := {t = LobbyProtocol.T_JOIN, seq = _seq_join, region = region,
			party = party, skill = skill, name = name}
	_pending_join = {msg = m, next_at = now, last_ack_at = now,
			started_at = now, params = [region, party, skill, name]}
	_put(m)

func send_state(humans: int, over: bool) -> void:
	_put({t = LobbyProtocol.T_STATE, humans = humans, over = over})

func ping() -> void:
	_seq_ping += 1
	_last_ping_at = Time.get_ticks_msec()
	_put({t = LobbyProtocol.T_PING, seq = _seq_ping, at = _last_ping_at})

func _process(_delta: float) -> void:
	pump(1.0 / 60.0)

func pump(delta: float) -> void:
	if _peer == null:
		return
	var n: int = _peer.get_available_packet_count()
	while n > 0:
		var pkt: PackedByteArray = _peer.get_packet()
		var from_port: int = _peer.get_packet_port()
		if from_port == port:
			_buf += pkt.get_string_from_utf8()
			var sp: Array = LobbyProtocol.split_lines(_buf)
			_buf = str(sp[1])
			for line in sp[0]:
				_dispatch(LobbyProtocol.unpack_line(str(line)))
		n = _peer.get_available_packet_count()
	# Periodic ping: liveness + RTT (this is the keep-alive).
	_ping_acc += delta
	if _ping_acc >= _ping_every:
		_ping_acc = 0.0
		ping()
	# Connection state machine (fresh message = connected; 5 s of silence =
	# down). Uses _last_rx_at (any message), so a stale pong can't re-fire it.
	var now_ms := Time.get_ticks_msec()
	if not _connected:
		if _last_rx_at > 0.0 and now_ms - _last_rx_at <= 2000:
			_connected = true
			print("LOBBY-CLIENT connected to %s:%d (udp)" % [host, port])
			connected_ok.emit()
	elif now_ms - _last_rx_at > 5000:
		_connected = false
		print("LOBBY-CLIENT %s:%d went silent" % [host, port])
		disconnected.emit()
	# Retransmit pending join/reg.
	_retransmit()

func _retransmit() -> void:
	var now := Time.get_ticks_msec()
	if not _pending_join.is_empty():
		if now - int(_pending_join.last_ack_at) > _rejoin_after:
			# Server silent (assign lost or never queued): fresh session.
			var p: Array = _pending_join.params
			join_queue(str(p[0]), int(p[1]), int(p[2]), str(p[3]))
		elif now >= int(_pending_join.next_at):
			_put(_pending_join.msg)
			_pending_join.next_at = now + _retry_in
	if not _pending_reg.is_empty():
		if now >= int(_pending_reg.next_at):
			_put(_pending_reg.msg)
			_pending_reg.next_at = now + _retry_in

func _put(msg: Dictionary) -> void:
	if _peer == null:
		return
	_peer.set_dest_address(host, port)
	_peer.put_packet(LobbyProtocol.pack(msg))

func exit_tree_cleanup() -> void:
	_peer = null

func _exit_tree() -> void:
	exit_tree_cleanup()

func _dispatch(msg: Dictionary) -> void:
	_last_rx_at = Time.get_ticks_msec()
	var t: String = LobbyProtocol.msg_type(msg)
	if t == LobbyProtocol.T_PONG:
		_last_pong_at = Time.get_ticks_msec()
		var rtt: float = float(Time.get_ticks_msec() - _last_ping_at)
		pong.emit(rtt)
	elif t == LobbyProtocol.T_HELLO:
		hello.emit(msg)
	elif t == LobbyProtocol.T_QUEUE:
		# acked: server is tracking our wait - refresh the rejoin timer
		if not _pending_join.is_empty():
			_pending_join.last_ack_at = Time.get_ticks_msec()
		queue.emit(msg)
	elif t == LobbyProtocol.T_ASSIGN:
		_pending_join = {}
		assign.emit(msg)
	elif t == LobbyProtocol.T_REGACK:
		_pending_reg = {}
		regack.emit(msg)
	elif t == "err":
		print("LOBBY-CLIENT error: %s" % str(msg.get("reason", "?")))
