class_name Relay
extends Node
## NAT-traversal v1 relay (Phase 5, round 29, ARCHITECTURE D15): a match
## server behind a NAT registers here over an OUTBOUND UDP connection (the
## only direction a NAT mapping exists for) and gets a VIRTUAL PORT on this
## relay. Clients (anywhere) make a normal ENet connection to
## <relay_ip>:<virtual_port>; the relay transparently forwards raw datagrams
## to the server's NAT mapping and back. ENet's own reliability/flow control
## runs on the forwarded stream - the relay is a dumb per-(match, client)
## datagram pump with no payload knowledge.
##
## Per-link topology (why two sockets per client): the server must see each
## client from a DISTINCT source port, and the client must see the server AT
## the virtual port it dialed (ENet binds the connection to the dialed
## address - a reply from any other source port is dropped as an unknown
## peer). So each (match, client) gets one ephemeral socket:
##   client -> virtual-port socket -> forwarded via link socket (source =
##   the link's ephemeral port P) -> server;
##   server -> replies to P -> link socket -> forwarded via the VIRTUAL
##   socket (source = vport) -> client.
##
## Wire protocol (own, headerless forwarding; control datagrams only):
##   R_REG  [0x52 0x47, token u32 LE, game_port u16 LE]
##          server -> relay. token = future auth; game_port = the ENet port
##          the relay must forward to (the reg socket is a DIFFERENT socket
##          owned by RelayClient; the server ip = the reg source address,
##          i.e. the server's NAT mapping as the relay sees it).
##   R_OK   [0x52 0x4F, vport u16 LE]  relay -> server (virtual port granted)
##   R_PING [0x52 0x50]                server -> relay (keep-alive, no reply)
##
## Ports (infra table, AGENTS.md: justification below): control 7800
## (Relay.CONTROL_PORT; the relay scene takes --port=), virtual ports
## 7901..8156 (256 concurrent matches - far above the 2-core budget's
## single-match target; the range is wide so port collisions with other
## services on a VPS are easy to spot).
const CONTROL_PORT := 7800
const VBASE := 7901
const VCOUNT := 256
const MATCH_TIMEOUT_MS := 60000   # no R_PING/traffic from the server -> evict
const LINK_TIMEOUT_MS := 120000   # idle client link (ENet heartbeats every ~5 s)
const PING_INTERVAL_MS := 10000   # server keep-alive cadence (RelayClient)
const REG_RETRY_MS := 5000        # R_OK wait timeout before re-registering

var _reg: PacketPeerUDP
var _matches: Dictionary = {}  # vport -> {sip, sport, rsport, sock, last_ms}
var _links: Array = []         # [{vport, cip, cport, sip, sport, sock, vsock, last_ms}]
var evicted_matches := 0
var evicted_links := 0

func setup(port: int = CONTROL_PORT) -> void:
	_reg = PacketPeerUDP.new()
	var err := _reg.bind(port)
	if err != OK:
		push_error("RELAY bind udp/%d failed: %d" % [port, err])
		return
	print("RELAY listening on udp/%d (virtual ports %d..%d)" % [port, VBASE, VBASE + VCOUNT - 1])

func _process(_d: float) -> void:
	if _reg == null:
		return
	var now := Time.get_ticks_msec()
	_poll_reg(now)
	for vport in _matches.keys():
		var m: Dictionary = _matches[vport]
		if now - int(m.last_ms) > MATCH_TIMEOUT_MS:
			_evict_match(vport)
		else:
			_poll_virtual(vport, m, now)
	for i in range(_links.size() - 1, -1, -1):
		var l: Dictionary = _links[i]
		if now - int(l.last_ms) > LINK_TIMEOUT_MS:
			_links[i].sock.close()
			_links[i].sock = null
			_links.remove_at(i)
			evicted_links += 1
		else:
			_poll_link(l, now)

func _poll_reg(now: int) -> void:
	while _reg.get_available_packet_count() > 0:
		var pkt: PackedByteArray = _reg.get_packet()
		var sip := _reg.get_packet_ip()
		var sport := _reg.get_packet_port()
		if pkt.size() < 2:
			continue
		if pkt[0] == 0x52 and pkt[1] == 0x47:  # R_REG
			if pkt.size() < 8:
				continue
			var gport := int(pkt[6]) | (int(pkt[7]) << 8)
			var vport := _alloc_match(sip, gport, sport, now)
			if vport > 0:
				var r := PackedByteArray([0x52, 0x4F, vport & 0xFF, (vport >> 8) & 0xFF])
				_reg.set_dest_address(sip, sport)
				_reg.put_packet(r)
				print("RELAY registered server %s:%d (reg from :%d) -> vport %d" % [sip, gport, sport, vport])
		elif pkt[0] == 0x52 and pkt[1] == 0x50:  # R_PING
			for vport in _matches.keys():
				var m: Dictionary = _matches[vport]
				if str(m.sip) == sip and int(m.rsport) == sport:
					m.last_ms = now
					break

## Assigns a free virtual port + binds its socket for the server. sport =
## the ENet game port (forward target); rsport = the reg source port (used
## only to attribute R_PING keep-alives).
func _alloc_match(sip: String, sport: int, rsport: int, now: int) -> int:
	for i in VCOUNT:
		var vport := VBASE + i
		if not _matches.has(vport):
			var sock := PacketPeerUDP.new()
			if sock.bind(vport) != OK:
				continue  # port taken outside the relay - skip
			_matches[vport] = {sip = sip, sport = sport, rsport = rsport,
				sock = sock, last_ms = now}
			return vport
	return -1

func _evict_match(vport: int) -> void:
	var m: Dictionary = _matches[vport]
	m.sock.close()
	# Its links die with the match.
	for i in range(_links.size() - 1, -1, -1):
		var l: Dictionary = _links[i]
		if int(l.vport) == vport:
			l.sock.close()
			l.sock = null
			_links.remove_at(i)
			evicted_links += 1
	_matches.erase(vport)
	evicted_matches += 1
	print("RELAY evicted match vport %d (server silent)" % vport)

## A datagram at the virtual-port socket = a client packet: find/create the
## (match, client) link and forward it to the server via the link socket.
func _poll_virtual(vport: int, m: Dictionary, now: int) -> void:
	var sock: PacketPeerUDP = m.sock
	while sock.get_available_packet_count() > 0:
		var data: PackedByteArray = sock.get_packet()
		var cip := sock.get_packet_ip()
		var cport := sock.get_packet_port()
		var l := _find_link(vport, cip, cport, m)
		l.last_ms = now
		l.sock.set_dest_address(str(m.sip), int(m.sport))
		l.sock.put_packet(data)
		l.vsock = sock  # server replies come back via the virtual port

## Links are keyed by (vport, client addr): the SAME client may hold relayed
## connections to two different matches at once.
func _find_link(vport: int, cip: String, cport: int, m: Dictionary) -> Dictionary:
	for l in _links:
		if int(l.vport) == vport and str(l.cip) == cip and int(l.cport) == cport:
			return l
	var l := {vport = vport, cip = cip, cport = cport, sip = m.sip,
			sport = m.sport, sock = PacketPeerUDP.new(), vsock = null,
			last_ms = Time.get_ticks_msec()}
	l.sock.bind(0)  # ephemeral local port = this client's "identity" to the server
	_links.append(l)
	return l

## A datagram at a link socket = a server reply: forward to the client VIA
## THE VIRTUAL SOCKET, so the client sees it coming from the vport it dialed.
func _poll_link(l: Dictionary, now: int) -> void:
	var sock: PacketPeerUDP = l.sock
	while sock.get_available_packet_count() > 0:
		var data: PackedByteArray = sock.get_packet()
		if l.vsock != null:
			l.vsock.set_dest_address(str(l.cip), int(l.cport))
			l.vsock.put_packet(data)
		l.last_ms = now
