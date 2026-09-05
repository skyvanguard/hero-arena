class_name NetProtocol
extends RefCounted
## Net codec v1 (Phase 5): pack/unpack for every wire message. Little-endian
## PackedByteArray payloads. Channels:
##   CH_RELIABLE   (0) - hello, slot ack, game events (game-meaningful)
##   CH_UNRELIABLE (1) - input frames, snapshots (latest wins)
## v1 tradeoffs (documented in NETWORKING.md): no prediction, no sequence
## reordering inside unreliable channel (drops are fine - 20 Hz refresh).

const CH_RELIABLE := 0
const CH_UNRELIABLE := 1
const SNAPSHOT_HZ := 20
const INPUT_HZ := 20
const MAX_CHARS := 6
const MAX_PROJS := 8

# Message magics (first byte).
const M_HELLO := 0x48   # 'H'
const M_SLOT := 0x53    # 'S'
const M_INPUT := 0x49   # 'I'
const M_SNAPSHOT := 0x50  # 'P'
const M_EVENT := 0x45    # 'E'
const M_STATS := 0x54    # 'T' (D19 results)
# LAN discovery (UDP discovery port, not the ENet game port).
const M_DISCOVER_PING := 0x44  # 'D'
const M_DISCOVER_REPLY := 0x46 # 'F'

# Join state reported by discovery replies.
const DISC_OPEN := 0
const DISC_FULL := 1
const DISC_OVER := 2

# Event types.
const E_HIT := 0
const E_KILL := 1
const E_RESPAWN := 2
const E_MATCH_OVER := 3
const E_HEAL := 4

# ---- little-endian builders ----

static func f32(v: float) -> PackedByteArray:
	# IEEE 754 float32 -> 4 little-endian bytes. Manual bit math because 4.7
	# dropped PackedFloat32Array.pack_bytes(); the inverse is _f32_at.
	var av := absf(v)
	var bits := 0
	if av == 0.0:
		bits = 0x80000000 if v < 0.0 else 0
	else:
		var exp := int(floorf(log(av) / log(2.0)))
		var mant_full := int((av / pow(2.0, float(exp))) * 8388608.0)
		if mant_full >= 16777216:
			mant_full = 8388608
			exp += 1
		var e2i := exp + 127
		if e2i <= 0:
			bits = 0x80000000 if v < 0.0 else 0  # subnormal: flush to signed zero
		elif e2i >= 255:
			bits = 0x7F800000 if v > 0.0 else 0xFF800000
		else:
			bits = (e2i << 23) | (mant_full & 8388607)
		if v < 0.0:
			bits |= 0x80000000
	return PackedByteArray([bits & 0xFF, (bits >> 8) & 0xFF, (bits >> 16) & 0xFF, (bits >> 24) & 0xFF])

static func f32s(v: Array) -> PackedByteArray:
	var b := PackedByteArray()
	for x in v:
		b.append_array(f32(float(x)))
	return b

static func u8(v: int) -> PackedByteArray:
	return PackedByteArray([v & 0xFF])

static func u16(v: int) -> PackedByteArray:
	return PackedByteArray([v & 0xFF, (v >> 8) & 0xFF])

static func i8(v: int) -> PackedByteArray:
	return u8(v & 0xFF)

static func s_bytes(s: String) -> PackedByteArray:
	var b := s.to_utf8_buffer()
	return u16(b.size()) + b

static func _f32_at(p: PackedByteArray, o: int) -> float:
	# Little-endian IEEE 754 decode.
	var i := p[o] | (p[o + 1] << 8) | (p[o + 2] << 16) | (p[o + 3] << 24)
	var sign := 1.0 if (i & 0x80000000) == 0 else -1.0
	var exp := (i >> 23) & 0xFF
	var mant := i & 0x7FFFFF
	if exp == 0:
		return 0.0
	var v := float(mant + 0x800000) / float(0x800000) * sign
	v = v * pow(2.0, float(exp - 127))
	return v

static func read_u8(p: PackedByteArray, o: int) -> int:
	return p[o]

static func read_u16(p: PackedByteArray, o: int) -> int:
	return p[o] | (p[o + 1] << 8)

static func u32(v: int) -> PackedByteArray:
	return PackedByteArray([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF])

static func read_u32(p: PackedByteArray, o: int) -> int:
	return p[o] | (p[o + 1] << 8) | (p[o + 2] << 16) | (p[o + 3] << 24)

static func read_str(p: PackedByteArray, o: int) -> String:
	var n := read_u16(p, o)
	var s := p.slice(o + 2, o + 2 + n).get_string_from_utf8()
	return s

# ---- messages ----

## hello: client -> server (reliable). hero_id is the pick from the select;
## D19 results: per-character stats in world.characters order (same index
## convention as the snapshot char list): [team u8, kills u8, deaths u8,
## damage u16] per row.
static func pack_stats(rows: Array) -> PackedByteArray:
	var b := u8(M_STATS) + u8(rows.size())
	for r in rows:
		b += u8(int(r[0])) + u8(clampi(int(r[1]), 0, 255)) + u8(clampi(int(r[2]), 0, 255))
		b += u16(clampi(int(r[3]), 0, 65535))
	return b

static func unpack_stats(p: PackedByteArray) -> Array:
	var rows: Array = []
	var o := 1
	var n := read_u8(p, o); o += 1
	for i in n:
		var team := read_u8(p, o); o += 1
		var k := read_u8(p, o); o += 1
		var d := read_u8(p, o); o += 1
		var dmg := read_u16(p, o); o += 2
		rows.append([team, k, d, dmg])
	return rows

## session = 0 for a fresh join, or the slot token from M_SLOT to reconnect
## to a frozen slot (Phase 5 reconnect).
static func pack_hello(team_size: int, hero_id: String, session: int = 0) -> PackedByteArray:
	var b := u8(M_HELLO) + u8(team_size) + s_bytes(hero_id) + u32(session)
	return b

static func unpack_hello(p: PackedByteArray) -> Dictionary:
	var o := 1
	var ts := read_u8(p, o); o += 1
	var hid := read_str(p, o)
	o += hid.to_utf8_buffer().size() + 2
	var session := 0
	if p.size() >= o + 4:
		session = read_u32(p, o)
	return {"team_size": ts, "hero_id": hid, "session": session}

## slot: server -> client (reliable). result 0 = accepted, -1 = team full,
## -2 = match already over. Carries pacing values (target_score,
## match_duration) for the client HUD + the session token (M_HELLO.session
## on reconnect keeps the frozen slot) + mode_code (D16/D17) and map_code
## (D18: index into MapRegistry.ids() — the client builds its MIRROR arena
## from the same Map data the server uses, so spawns/geometry agree).
static func pack_slot(result: int, ch_id: int, team: int, team_size: int,
		time: float, target_score: int, match_duration: float, token: int = 0,
		mode_code: int = 0, map_code: int = 0) -> PackedByteArray:
	var b := u8(M_SLOT) + i8(result) + u8(ch_id) + u8(team) + u8(team_size)
	b += f32(time) + u8(target_score) + f32(match_duration) + u32(token) + u8(mode_code) + u8(map_code)
	return b

static func unpack_slot(p: PackedByteArray) -> Dictionary:
	var o := 1
	var r := read_u8(p, o)
	r = r - 256 if r > 127 else r
	o += 1
	var ch := read_u8(p, o); o += 1
	var team := read_u8(p, o); o += 1
	var ts := read_u8(p, o); o += 1
	var t := _f32_at(p, o); o += 4
	var target := read_u8(p, o); o += 1
	var dur := _f32_at(p, o); o += 4
	var token := 0
	if p.size() >= o + 4:
		token = read_u32(p, o)
		o += 4
	var mode_code := 0
	if p.size() >= o + 1:
		mode_code = read_u8(p, o)
		o += 1
	var map_code := 0
	if p.size() >= o + 1:
		map_code = read_u8(p, o)
	return {"result": r, "ch_id": ch, "team": team, "team_size": ts, "time": t,
			"target_score": target, "match_duration": dur, "token": token,
			"mode_code": mode_code, "map_code": map_code}

## input: client -> server (unreliable), INPUT_HZ.
## edges bitfield: 1 jump, 2 reload, 4 ability1, 8 ability2, 16 ultimate.
## time_est = the client's estimate of current server time (s); the server
## measures one-way latency from it and drives lag compensation.
static func pack_input(seq: int, move: Vector2, yaw: float, pitch: float,
		fire: bool, edges: int, time_est: float = 0.0) -> PackedByteArray:
	var b := u8(M_INPUT) + u16(seq) + f32s([move.x, move.y, yaw, pitch]) + u8(1 if fire else 0) + u8(edges)
	b += f32(time_est)
	return b

static func unpack_input(p: PackedByteArray) -> Dictionary:
	var o := 1
	var seq := read_u16(p, o); o += 2
	var mx := _f32_at(p, o); o += 4
	var my := _f32_at(p, o); o += 4
	var yaw := _f32_at(p, o); o += 4
	var pitch := _f32_at(p, o); o += 4
	var fire := read_u8(p, o) != 0; o += 1
	var edges := read_u8(p, o); o += 1
	var te := 0.0
	if p.size() >= o + 4:
		te = _f32_at(p, o)
	return {"seq": seq, "move": Vector2(mx, my), "yaw": yaw, "pitch": pitch,
			"fire": fire, "edges": edges, "time_est": te}

## snapshot: server -> all clients (unreliable), SNAPSHOT_HZ.
## char dict: {id, team, alive, hero_idx, pos(Vector3), rot_y, hp, max_hp}
## proj dict: {owner(id), pos(Vector3), dir(Vector3)}
## control (Phase 6 v1, D16): owner_code u8 (0=none, 1=team0, 2=team1) +
## team_code u8 (the team progress runs toward: 0, 1, 2=none) + progress
## u8 (0..255). The control POINT POSITION is not sent: v1 fixes it at the
## arena center, which the client's mirror arena already knows.
## ext (Phase 6 v2, D17): 4 mode-specific u8 bytes (0 for tdm/control):
##   capture: ext0/ext1 = the carrier of each team's flag (0 = none, else
##            snapshot char id + 1); a flag whose code is 0 sits at its base
##            or is dropped (v1 clients draw the base marker only).
##   escort:  ext0 = payload progress q8 (0..1 along the lane),
##            ext1 = payload speed q8 (fraction of the mode's max_speed).
## score0/score1 carry the MODE'S score (kills in TDM, captures in
## Control/Capture, 0-0 in Escort - the winner carries the result).
static func pack_snapshot(seq: int, time: float, score0: int, score1: int,
		winner: int, chars: Array, projs: Array,
		control_owner: int = -1, control_progress_team: int = -1,
		control_progress: float = 0.0, ext: Array = [0, 0, 0, 0]) -> PackedByteArray:
	var b := u8(M_SNAPSHOT) + u16(seq) + f32(time) + u8(score0) + u8(score1) + u8(winner + 1)
	b += u8(0 if control_owner < 0 else control_owner + 1)
	b += u8(2 if control_progress_team < 0 else control_progress_team)
	b += u8(int(clampf(control_progress, 0.0, 1.0) * 255.0))
	for i in 4:
		b += u8(int(clampi(int(ext[i]), 0, 255)))
	b += u8(chars.size())
	for c in chars:
		b += u8(int(c.id)) + u8(int(c.team)) + u8(1 if c.alive else 0) + u8(int(c.hero_idx))
		var p: Vector3 = c.pos
		b += f32s([p.x, p.y, p.z])
		b += f32(float(c.rot_y)) + f32(float(c.hp)) + f32(float(c.max_hp))
	b += u8(projs.size())
	for pr in projs:
		b += u8(int(pr.owner))
		var pp: Vector3 = pr.pos
		var dd: Vector3 = pr.dir
		b += f32s([pp.x, pp.y, pp.z, dd.x, dd.y, dd.z])
	return b

static func unpack_snapshot(p: PackedByteArray) -> Dictionary:
	var o := 1
	var seq := read_u16(p, o); o += 2
	var time := _f32_at(p, o); o += 4
	var s0 := read_u8(p, o); o += 1
	var s1 := read_u8(p, o); o += 1
	var winner := read_u8(p, o) - 1; o += 1
	var owner_code := read_u8(p, o); o += 1
	var team_code := read_u8(p, o); o += 1
	var progress_q := read_u8(p, o); o += 1
	var ext: Array = []
	for i in 4:
		ext.append(read_u8(p, o))
		o += 1
	var n := read_u8(p, o); o += 1
	var chars: Array = []
	for i in n:
		var c := {}
		c.id = read_u8(p, o); o += 1
		c.team = read_u8(p, o); o += 1
		c.alive = read_u8(p, o) != 0; o += 1
		c.hero_idx = read_u8(p, o); o += 1
		c.pos = Vector3(_f32_at(p, o), _f32_at(p, o + 4), _f32_at(p, o + 8)); o += 12
		c.rot_y = _f32_at(p, o); o += 4
		c.hp = _f32_at(p, o); o += 4
		c.max_hp = _f32_at(p, o); o += 4
		chars.append(c)
	var m := read_u8(p, o); o += 1
	var projs: Array = []
	for i in m:
		var pr := {}
		pr.owner = read_u8(p, o); o += 1
		pr.pos = Vector3(_f32_at(p, o), _f32_at(p, o + 4), _f32_at(p, o + 8)); o += 12
		pr.dir = Vector3(_f32_at(p, o), _f32_at(p, o + 4), _f32_at(p, o + 8)); o += 12
		projs.append(pr)
	return {"seq": seq, "time": time, "score": [s0, s1], "winner": winner,
			"control": [owner_code - 1, 2 if team_code > 1 else team_code,
				progress_q / 255.0],
			"ext": ext,
			"chars": chars, "projs": projs}

# ---- LAN discovery (UDP, best-effort) ----

## ping: client -> server (broadcast or unicast on the discovery port).
static func pack_discover_ping(client_name: String) -> PackedByteArray:
	return u8(M_DISCOVER_PING) + s_bytes(client_name)

## reply: server -> pinger. game_port is where the ENet match listens;
## state is DISC_OPEN / DISC_FULL / DISC_OVER for a fresh join.
static func pack_discover_reply(state: int, team_size: int, humans: int,
		target_score: int, game_port: int, name: String, time: float) -> PackedByteArray:
	var b := u8(M_DISCOVER_REPLY) + u8(state) + u8(team_size) + u8(humans) + u8(target_score)
	b += u16(game_port) + s_bytes(name) + f32(time)
	return b

static func unpack_discover_reply(p: PackedByteArray) -> Dictionary:
	var o := 1
	var st := read_u8(p, o); o += 1
	var ts := read_u8(p, o); o += 1
	var hu := read_u8(p, o); o += 1
	var tg := read_u8(p, o); o += 1
	var gp := read_u16(p, o); o += 2
	var nm := read_str(p, o)
	o += nm.to_utf8_buffer().size() + 2
	var tm := _f32_at(p, o)
	return {"state": st, "team_size": ts, "humans": hu, "target_score": tg,
			"game_port": gp, "name": nm, "time": tm}

# ---- events (reliable) ----

static func pack_event_hit(victim: int, source: int, amount: float,
		is_head: bool, prot: bool, pos: Vector3) -> PackedByteArray:
	var b := u8(M_EVENT) + u8(E_HIT) + u8(victim) + u8(source) + f32(amount) + u8(1 if is_head else 0) + u8(1 if prot else 0)
	b += f32s([pos.x, pos.y, pos.z])
	return b

static func pack_event_kill(killer_name: String, victim_name: String,
		killer_team: int, victim_team: int, headshot: bool) -> PackedByteArray:
	var b := u8(M_EVENT) + u8(E_KILL) + s_bytes(killer_name) + s_bytes(victim_name)
	b += u8(killer_team) + u8(victim_team) + u8(1 if headshot else 0)
	return b

static func pack_event_respawn(ch_id: int, pos: Vector3) -> PackedByteArray:
	var b := u8(M_EVENT) + u8(E_RESPAWN) + u8(ch_id)
	b += f32s([pos.x, pos.y, pos.z])
	return b

static func pack_event_match_over(winner: int, score0: int, score1: int, time: float) -> PackedByteArray:
	return u8(M_EVENT) + u8(E_MATCH_OVER) + u8(winner + 1) + u8(score0) + u8(score1) + f32(time)

static func pack_event_heal(target: int, source: int, amount: float) -> PackedByteArray:
	return u8(M_EVENT) + u8(E_HEAL) + u8(target) + u8(source) + f32(amount)

static func unpack_event(p: PackedByteArray) -> Dictionary:
	var t := read_u8(p, 1)
	var o := 2
	var d := {"type": t}
	match t:
		E_HIT:
			d.victim = read_u8(p, o); o += 1
			d.source = read_u8(p, o); o += 1
			d.amount = _f32_at(p, o); o += 4
			d.is_head = read_u8(p, o) != 0; o += 1
			d.prot = read_u8(p, o) != 0; o += 1
			d.pos = Vector3(_f32_at(p, o), _f32_at(p, o + 4), _f32_at(p, o + 8))
		E_KILL:
			var klen := read_u16(p, o); o += 2
			d.killer = p.slice(o, o + klen).get_string_from_utf8(); o += klen
			var vlen := read_u16(p, o); o += 2
			d.victim = p.slice(o, o + vlen).get_string_from_utf8(); o += vlen
			d.killer_team = read_u8(p, o); o += 1
			d.victim_team = read_u8(p, o); o += 1
			d.headshot = read_u8(p, o) != 0
		E_RESPAWN:
			d.ch_id = read_u8(p, o); o += 1
			d.pos = Vector3(_f32_at(p, o), _f32_at(p, o + 4), _f32_at(p, o + 8))
		E_MATCH_OVER:
			d.winner = read_u8(p, o) - 1; o += 1
			d.score = [read_u8(p, o), read_u8(p, o + 1)]; o += 2
			d.time = _f32_at(p, o)
		E_HEAL:
			d.target = read_u8(p, o); o += 1
			d.source = read_u8(p, o); o += 1
			d.amount = _f32_at(p, o)
	return d
