class_name LobbyServer
extends Node
## Headless lobby / matchmaking service (Phase 5 v1 prototype).
##
## Role: a small UDP sidecar that (a) match servers register into (with
## region + reachable ip:port + live human count) and (b) clients queue in
## with a preferred region. The queue runs the directive's 4-stage strategy:
##   1. STRICT  (0..strict_until)        same region, open room
##   2. SKILL   (strict..skill_until)    + skill widen (v1: skill is always 0
##                                         so this stage is structurally
##                                         identical to strict - the field and
##                                         stage exist for the real ELO pass)
##   3. REGION  (skill_until..fill_after)+ region widen, LATAM-priority table
##                                         order (Regions.widen_order)
##   4. BOTFILL (t >= fill_after)        best open match anywhere (fewest
##                                         humans first) - the "bot fill"
##                                         guarantee: every match bot-fills,
##                                         so a solo waiter always lands by
##                                         fill_after if any match has room
## Party-aware v1: the party size is accepted and requires room >= party;
## group-join handshake (N clients assigned as one) is a follow-up.
##
## Transport: UDP (JSON lines, same protocol as the TCP v1 draft).
## Godot 4.7.2 note: the TCP stack (TCPServer / StreamPeerTCP.listen,
## take_connection, bind) does not create real system sockets in headless
## builds (verified: no /proc fds, ss-invisible, cross-process connect
## fails with STATUS_ERROR), while PacketPeerUDP is fully functional
## (discovery + ENet depend on it). The lobby traffic is tiny (queue
## progress <= 1/s, pings 1/s, state on change) so connectionless is fine:
##  - clients tag every message with a seq; the server dedupes per
##    (peer, type, seq)
##  - clients retransmit join/reg with the SAME seq until acked
##    (queue/assign, regack) - the server's join handler is idempotent
##  - "connected" = first pong; peers silent for reap_after are dropped
##
## Run: godot --headless --path game res://net/lobby.tscn \
##   -- --port=7790 --region=latam_saopaulo [--fill=60]

var peer: PacketPeerUDP
var time := 0.0
var region := "latam_saopaulo"
var fill_after := 60.0
var strict_until := 5.0
var skill_until := 15.0
var reap_after := 5.0
var next_id := 1
## peers: "ip:port" -> {buf: String, kind: "match"|"client", last_seen, last_seqs: {type: int}}
var _peers: Dictionary = {}
## matches: id -> {key, ip, port, region, team_size, humans, over, name,
##   last_seen, mode, votes {mode: count}, vote_source {peer: mode}, decided}
var matches: Dictionary = {}
## waiters: peer key -> {region, party, skill, name, joined_at, last_queue_sent}
var waiters: Dictionary = {}

signal match_registered(info: Dictionary)
signal match_dropped(match_id: int)
signal client_assigned(info: Dictionary)
signal client_dropped()

func setup(port: int, lobby_region: String, fill_after_s: float = 60.0) -> void:
	region = lobby_region
	if fill_after_s > 0.0:
		fill_after = fill_after_s
	peer = PacketPeerUDP.new()
	# 4.7: bind() (set_mode_server was removed) - one arg, all interfaces.
	var err: int = peer.bind(port)
	if err != 0:
		push_error("LOBBY bind udp/%d failed: %s" % [port, error_string(err)])
	else:
		print("LOBBY listening on udp/%d (region %s, fill %.0f s)" % [port, region, fill_after])

func _process(_delta: float) -> void:
	tick(1.0 / 60.0)

## Tick (the scene drives it at 60 Hz; tests may call it from any loop).
## The clock is wall-clock (ms -> s) so the stage windows advance in REAL
## time even if the tick rate drifts (headless physics can run > 60 Hz).
func tick(delta: float) -> void:
	time = Time.get_ticks_msec() / 1000.0
	_poll_packets()
	_reap()
	_run_queue()

func _poll_packets() -> void:
	if peer == null:
		return
	var n: int = peer.get_available_packet_count()
	while n > 0:
		var pkt: PackedByteArray = peer.get_packet()
		var ip: String = peer.get_packet_ip()
		var pport: int = peer.get_packet_port()
		var key := ip + ":" + str(pport)
		if not _peers.has(key):
			_peers[key] = {buf = "", kind = "unknown", last_seen = time,
					last_seqs = {}}
			print("LOBBY client from " + key)
		var info: Dictionary = _peers[key]
		info.buf += pkt.get_string_from_utf8()
		var sp: Array = LobbyProtocol.split_lines(info.buf)
		info.buf = str(sp[1])
		for line in sp[0]:
			_dispatch(key, LobbyProtocol.unpack_line(str(line)))
		n = peer.get_available_packet_count()

## Per-(peer, type) seq dedupe: process only if seq > last seen for that
## type; retransmissions repeat the same seq and are dropped.
func _fresh(info: Dictionary, msg: Dictionary) -> bool:
	if not msg.has("seq"):
		return true
	var t: String = str(msg.get("t", ""))
	var seq: int = int(msg.get("seq", -1))
	var last: int = int(info.last_seqs.get(t, -1))
	if seq <= last:
		return false
	info.last_seqs[t] = seq
	return true

func _dispatch(key: String, msg: Dictionary) -> void:
	var info: Dictionary = _peers[key]
	if not _fresh(info, msg):
		return
	var t: String = LobbyProtocol.msg_type(msg)
	info.last_seen = time
	match t:
		LobbyProtocol.T_PING:
			# First ping from a new peer doubles as hello (UDP has no
			# connect event): the client learns region + live counts now.
			if info.kind == "unknown":
				_send(key, {t = LobbyProtocol.T_HELLO, region = region,
						matches = _open_match_count(), waiters = waiters.size()})
			_send(key, {t = LobbyProtocol.T_PONG, at = int(msg.get("at", 0))})
		LobbyProtocol.T_JOIN:
			var reg := Regions.by_code(str(msg.get("region", "")))
			if reg.is_empty():
				_send(key, {t = "err", reason = "bad region"})
				return
			info.kind = "client"
			var dbg := ""
			for mid in matches.keys():
				var mm: Dictionary = matches[mid]
				dbg += " [id=%s over=%s humans=%s/%s age=%.1f]" % [
					mid, str(mm.over), str(mm.humans), str(mm.team_size),
					time - float(mm.last_seen)]
			print("LOBBY join from %s region=%s party=%d (open: %d)%s" % [
					key, str(msg.get("region")), int(msg.get("party", 1)),
					_open_match_count(), dbg])
			waiters[key] = {
				region = str(msg.get("region")),
				party = clampi(int(msg.get("party", 1)), 1, 6),
				skill = int(msg.get("skill", 0)),
				name = str(msg.get("name", "P")),
				joined_at = time,
				last_queue_sent = -1.0,
			}
		LobbyProtocol.T_REG:
			info.kind = "match"
			var id := next_id
			next_id += 1
			var ip: String = str(msg.get("ip"))
			var gport: int = int(msg.get("port", 0))
			var game_key := ip + ":" + str(gport)
			# Re-registration from the same game ip:port replaces the old
			# entry (server restart with the same published address).
			for old_id in matches.keys():
				var old: Dictionary = matches[old_id]
				if str(old.ip) + ":" + str(int(old.port)) == game_key:
					matches.erase(old_id)
					match_dropped.emit(int(old_id))
			matches[id] = {
				key = key,
				ip = ip,
				port = gport,
				region = str(msg.get("region", region)),
				team_size = clampi(int(msg.get("team_size", 3)), 1, 6),
				humans = 0,
				over = false,
				name = str(msg.get("name", "match")),
				mode = str(msg.get("mode", "tdm")),
				last_seen = time,
				votes = {},
				vote_source = {},
				decided = false,
			}
			_send(key, {t = LobbyProtocol.T_REGACK, match_id = id})
			match_registered.emit(matches[id].duplicate())
			print("LOBBY match %d registered: %s:%d region=%s (%s)" % [
					id, ip, gport, str(matches[id].region), str(matches[id].name)])
		LobbyProtocol.T_STATE:
			var mid := _match_id_of(key)
			if mid != 0:
				var m: Dictionary = matches[mid]
				m.humans = clampi(int(msg.get("humans", m.humans)), 0, int(m.team_size))
				m.over = bool(msg.get("over", m.over))
				# D20: the server reports the mode it is actually running, so
				# the directory reflects the voted-mode swap at the next
				# in-place reset (the 2 s state heartbeat keeps this fresh).
				var new_mode := str(msg.get("mode", ""))
				if new_mode != "" and ModeRegistry.ids().has(new_mode):
					m.mode = new_mode
		LobbyProtocol.T_VOTE:
			_on_vote(key, msg)
		_:
			pass
	# Any message from a match server (ping included) keeps the match alive.
	var mid2 := _match_id_of(key)
	if mid2 != 0:
		matches[mid2].last_seen = time

## D20 vote: one vote per peer per match, last write wins (a re-tap or a
## retransmit never inflates the tally). Strict majority with >= 2 votes
## decides; the decision updates the directory entry and is forwarded to
## the match server, which applies it at the next in-place reset.
func _on_vote(key: String, msg: Dictionary) -> void:
	var mid := int(msg.get("match_id", 0))
	var m: Dictionary = matches.get(mid, {})
	# Over matches are votable: the vote targets the NEXT match, and the
	# server runs it in-place on the next hello (the entry stays the same).
	if m.is_empty():
		_send(key, {t = "err", reason = "no such match " + str(mid)})
		return
	var opt := str(msg.get("mode", ""))
	if not ModeRegistry.ids().has(opt):
		_send(key, {t = "err", reason = "bad mode " + opt})
		return
	# Last write wins: retract the previous vote (if any) before counting
	# the new one - a same-mode re-vote is idempotent (net zero).
	var prev := str(m.vote_source.get(key, ""))
	if prev != "":
		m.votes[prev] = int(m.votes[prev]) - 1
	m.vote_source[key] = opt
	m.votes[opt] = int(m.votes.get(opt, 0)) + 1
	# Decide BEFORE acking: the voter who casts the deciding vote sees
	# decided=true in the very response that caused it.
	_try_decide(int(mid), m)
	_send(key, {
		t = LobbyProtocol.T_VOTERESULT, match_id = mid,
		tally = m.votes.duplicate(true), leading = _leading(m),
		decided = bool(m.decided), mode = str(m.mode),
	})

func _leading(m: Dictionary) -> String:
	var best := ""
	var best_n := 0
	for k in m.votes:
		if int(m.votes[k]) > best_n:
			best_n = int(m.votes[k])
			best = str(k)
	return best

func _try_decide(mid: int, m: Dictionary) -> void:
	if bool(m.decided):
		return
	var total := 0
	for v in m.votes.values():
		total += int(v)
	if total < 2:
		return
	var winner := _leading(m)
	if winner == "" or int(m.votes[winner]) * 2 <= total:
		return  # no strict majority
	m.decided = true
	m.mode = winner
	_send(str(m.key), {t = LobbyProtocol.T_SETMODE, match_id = mid, mode = winner})
	print("LOBBY match %d mode voted: %s (%d/%d votes)" % [
			mid, winner, int(m.votes[winner]), total])

func _match_id_of(key: String) -> int:
	for id in matches.keys():
		var m: Dictionary = matches[id]
		if str(m.key) == key:
			return int(id)
	return 0

func _send(key: String, msg: Dictionary) -> void:
	if peer == null:
		return
	var parts: PackedStringArray = key.split(":")
	if parts.size() != 2:
		return
	peer.set_dest_address(str(parts[0]), int(str(parts[1])))
	peer.put_packet(LobbyProtocol.pack(msg))

func _open_match_count() -> int:
	var n := 0
	for id in matches.keys():
		if not matches[id].over:
			n += 1
	return n

func _reap() -> void:
	for key in _peers.keys():
		var info: Dictionary = _peers[key]
		if time - float(info.last_seen) > reap_after:
			print("LOBBY reaping silent peer " + str(key))
			_drop(str(key))
	for id in matches.keys():
		var m: Dictionary = matches[id]
		if time - float(m.last_seen) > reap_after:
			print("LOBBY match %d reaped (no updates)" % id)
			matches.erase(id)
			match_dropped.emit(int(id))

func _drop(key: String) -> void:
	var mid := _match_id_of(key)
	if mid != 0:
		matches.erase(mid)
		match_dropped.emit(mid)
	if waiters.has(key):
		waiters.erase(key)
		client_dropped.emit()
	_peers.erase(key)

func _stage_of(w: Dictionary) -> int:
	var t: float = time - float(w.joined_at)
	if t < strict_until:
		return LobbyProtocol.QUEUE_STAGE_STRICT
	if t < skill_until:
		return LobbyProtocol.QUEUE_STAGE_SKILL
	if t < fill_after:
		return LobbyProtocol.QUEUE_STAGE_REGION
	return LobbyProtocol.QUEUE_STAGE_BOTFILL

## Candidate matches for a waiter at its current stage, best first.
func _candidates(w: Dictionary) -> Array:
	var order: Array = Regions.widen_order(str(w.region))
	var stage := _stage_of(w)
	var cands: Array = []
	for id in matches.keys():
		var m: Dictionary = matches[id]
		if m.over:
			continue
		var room: int = int(m.team_size) - int(m.humans)
		if room < int(w.party):
			continue
		var rank := Regions.rank_in_order(order, str(m.region))
		if stage == LobbyProtocol.QUEUE_STAGE_STRICT or stage == LobbyProtocol.QUEUE_STAGE_SKILL:
			if str(m.region) != str(w.region):
				continue
		cands.append({id = int(id), rank = rank, humans = int(m.humans), m = m})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if stage == LobbyProtocol.QUEUE_STAGE_BOTFILL:
			if a.humans != b.humans:
				return a.humans < b.humans
			return a.rank < b.rank
		if a.rank != b.rank:
			return a.rank < b.rank
		return a.humans < b.humans
	)
	return cands

func _run_queue() -> void:
	for key in waiters.keys():
		var w: Dictionary = waiters[key]
		var cands := _candidates(w)
		if cands.size() > 0:
			var pick: Dictionary = cands[0]
			var m: Dictionary = pick.m
			waiters.erase(str(key))
			var stage := _stage_of(w)
			_send(str(key), {
				t = LobbyProtocol.T_ASSIGN,
				host = str(m.ip), port = int(m.port), match_id = int(pick.id),
				region = str(m.region), name = str(m.name), mode = str(m.mode),
				tally = m.votes.duplicate(true), leading = _leading(m),
				decided = bool(m.decided),
				stage = stage, waited = time - float(w.joined_at),
			})
			client_assigned.emit({host = str(m.ip), port = int(m.port),
					region = str(w.region), stage = stage})
			print("LOBBY assigned -> %s:%d (stage %d, waited %.1f s)" % [
					str(m.ip), int(m.port), stage, time - float(w.joined_at)])
		elif time - float(w.last_queue_sent) >= 1.0:
			w.last_queue_sent = time
			_send(str(key), {
				t = LobbyProtocol.T_QUEUE,
				stage = _stage_of(w),
				waited = time - float(w.joined_at),
				open = _open_match_count(),
			})
