class_name MatchServer
extends Node
## Dedicated headless match server (Phase 5 v1, ARCHITECTURE §1/§3.1):
## ENet transport on a SceneMultiplayer node (Godot 4.7: the 4.x
## NodeMultiplayer class was renamed; send_bytes/peer_packet replace the
## old set_packet/get_packet poll loop), 60 Hz authoritative World (stepped
## by the server scene), 20 Hz snapshots (unreliable) + reliable game-event
## relay. Humans join via hello/slot; every slot is bot-filled until a
## human takes it. Session tokens, reconnect, prediction: later rounds.
var world: World
var port := 7777
var team_size := 3
var mp: SceneMultiplayer
## peer_id -> {ch, input, team, hero_id, token, last_seq, delay}
var slots: Dictionary = {}
## token -> {ch, team, hero_id}: slots frozen on disconnect. A re-hello
## carrying the same token reattaches to the same character (Phase 5
## reconnect); a fresh join may still yield a bot behind it.
var _frozen: Dictionary = {}
## Emitted after reset_match(): the scene re-fills the bots (it owns the
## roster). v1 only resets when no human is connected, so no client sees
## the transition itself.
signal match_reset
## Net-sim transport (Phase 5): when set, send/recv bypass ENet entirely.
## sim_out carries this endpoint's latency/loss; sim_in is polled in tick().
var sim_out: SimLink = null
var sim_in: SimLink = null
## CharacterEntity -> stable match id (0..MAX_CHARS-1)
var char_ids: Dictionary = {}
var next_id := 0
var team_chars: Array = [[], []]  # team -> [CharacterEntity] (bots + humans)
var team_humans: Array = [0, 0]  # per-team human count (bots are replaceable)
var _snap_acc := 0.0
var _snap_seq := 0
var _snap_interval := 1.0 / NetProtocol.SNAPSHOT_HZ

var _started := false

## The map id this server runs (D18) — packed into M_SLOT as map_code so
## the client's mirror arena matches the server's geometry.
var map_id := "crossdocks"
## D20: the mode a lobby vote decided for the NEXT match ("" = keep the
## configured mode). Applied in reset_match() - the in-place new-match
## point, so no live match ever changes rules under its players.
var _pending_mode := ""
var _pending_map := ""  # D21: voted map, applied at the next in-place reset

func setup(w: World, p: int, ts: int) -> void:
	world = w
	port = p
	team_size = ts
	if is_inside_tree():
		_start()
	if world != null and MatchConfig != null:
		world.lag_comp_window = MatchConfig.lag_comp_window

func _ready() -> void:
	_start()

func _start() -> void:
	# Order-insensitive init: setup() may run before or after add_child().
	if _started or world == null:
		return
	_started = true
	mp = SceneMultiplayer.new()
	# 4.7: SceneMultiplayer is a RefCounted MultiplayerAPI (not a Node) and
	# needs a root path in the tree + explicit poll() calls.
	mp.set_root_path(get_path())
	if sim_out == null:
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_server(port, 8)
		if err != OK:
			push_error("MatchServer: create_server(%d) failed: %d" % [port, err])
		mp.multiplayer_peer = peer
		mp.peer_connected.connect(_on_peer_connected)
		mp.peer_disconnected.connect(_on_peer_disconnected)
		mp.peer_packet.connect(_on_peer_packet)
	world.world_event.connect(_on_world_event)
	var tag := " (sim transport)" if sim_out != null else ""
	print("SERVER listening on port %d (team size %d)" % [port, team_size] + tag)

func _on_peer_connected(id: int) -> void:
	print("SERVER peer %d connected (awaiting hello)" % id)

func _on_peer_disconnected(id: int) -> void:
	# The slot FREEZES in place: the body stays (controller removed, so no
	# stale input), and its token lets the peer reattach via a token hello.
	var s: Dictionary = slots.get(id, {})
	var ch: CharacterEntity = s.get("ch", null)
	if ch != null and is_instance_valid(ch):
		ch.controller = null
		ch.net_comp_delay = 0.0
		if s.has('team'):
			team_humans[int(s.team)] = maxi(0, int(team_humans[int(s.team)]) - 1)
		if s.has("token"):
			_frozen[int(s.token)] = {ch = ch, team = int(s.team),
				hero_id = str(s.hero_id)}
		if s.has("input"):
			var inp: NetInput = s.input
			inp.fire = false
			inp.move = Vector2.ZERO
	slots.erase(id)
	print("SERVER peer %d disconnected" % id)

## Call from the server scene after world.step(): poll the transport
## (peer_packet delivers) and emit snapshots at 20 Hz.
func tick(dt: float) -> void:
	if sim_in != null:
		sim_in.poll()
	else:
		var n := 0
		while mp.poll() == OK and n < 64:
			n += 1
	_snap_acc += dt
	if _snap_acc >= _snap_interval:
		_snap_acc = fmod(_snap_acc, _snap_interval)
		_send_snapshot()

func _on_peer_packet(id: int, buf: PackedByteArray) -> void:
	if buf.size() < 2:
		return
	var m: int = buf[0]
	if m == NetProtocol.M_HELLO:
		_on_hello(id, NetProtocol.unpack_hello(buf))
	elif m == NetProtocol.M_INPUT:
		_on_input(id, buf)

func _on_hello(from: int, d: Dictionary) -> void:
	var session := int(d.get("session", 0))
	if world.match_over:
		if slots.is_empty():
			# Finished match with no active humans left: this join (fresh,
			# or a returning token holder) starts a fresh match in place.
			# The reset clears _frozen, so a returning owner fresh-joins
			# the new match (their old token is invalidated).
			reset_match()
		else:
			# Other humans are still connected (watching the final): v1 has
			# no mid-observation reset - reject with the over code.
			_send_to(from, NetProtocol.pack_slot(-2, 0, 0, team_size, world.time,
					world.target_score, world.match_duration, 0, _mode_code(), _map_code()))
			print("SERVER peer %d rejected: match over" % from)
			return
	if session != 0 and _frozen.has(session) and not world.match_over:
		if _reattach(from, session):
			return
		# Slot died in the meantime (e.g. yielded to a fresh join): fall
		# through to a fresh join.
	# D30 (reconnect reliability): the client sends exactly one hello per
	# transport connection, so a hello from a peer that ALREADY holds a slot
	# is a re-hello whose earlier slot reply was lost on a lossy link (the
	# client's watchdog re-sent it). Re-announce the slot instead of
	# fresh-joining - a second character would orphan the first.
	if slots.has(from) and (session == 0 \
				or int(slots[from].get("token", 0)) == session):
		_send_slot(from, slots[from])
		return
	var hero_data: HeroData = HeroRegistry.by_id(str(d.hero_id))
	if hero_data == null:
		hero_data = HeroRegistry.default_hero()
	# Team pick: side with fewer HUMANS (bots replaceable; frozen slots do
	# not count - a returning owner re-claims its spot).
	var team := 0 if team_humans[0] <= team_humans[1] else 1
	if team_humans[team] >= team_size:
		_send_to(from, NetProtocol.pack_slot(-1, 0, 0, team_size, world.time,
				world.target_score, world.match_duration, 0, _mode_code(), _map_code()))
		print("SERVER peer %d rejected: team full" % from)
		return
	# A bot-filled slot yields to the human (bot fill is pre-spawned).
	var pts: Array = world.spawn_points.get(team, [])
	var spawn: Vector3
	if pts.size() > 0:
		spawn = pts[team_chars[team].size() % pts.size()]
	else:
		spawn = Vector3(16.0 if team == 0 else -16.0, 0.9, 0.0)
	if team_chars[team].size() >= team_size:
		# Yield a spot: PREFER the bot standing at the spawn point itself -
		# spawning a human exactly coincident with a live bot makes the two
		# capsules push each other straight up at ~66 m/s (Godot 4.7 resolves
		# exact overlaps vertically; verified by probe). A live body must
		# never share a spawn. A frozen human's slot is only taken when no
		# bot can yield (its token is invalidated either way).
		var to_free: CharacterEntity = null
		for c in team_chars[team]:
			if c != null and is_instance_valid(c) and not _is_frozen(c) 					and (c.global_position - spawn).length() < 0.5:
				to_free = c
				break
		if to_free == null:
			for i in range(team_chars[team].size() - 1, -1, -1):
				var c: CharacterEntity = team_chars[team][i]
				if not _is_frozen(c):
					to_free = c
					break
		if to_free == null and team_chars[team].size() > 0:
			to_free = team_chars[team].back()
		_free_character(to_free)
	var ch := _spawn_character(team, hero_data, spawn, true)
	var inp := NetInput.new()
	var nc := NetPlayerController.new()
	ch.add_child(nc)
	nc.setup(ch, null, world, null)
	nc.input = inp
	ch.controller = nc
	team_humans[team] += 1
	var token := randi_range(1, 0x7FFFFFFE)
	slots[from] = {ch = ch, input = inp, team = team, hero_id = hero_data.id,
		token = token, last_seq = -1, delay = 0.0}
	print("SERVER peer %d -> %s slot %d team %d" % [from, hero_data.id, int(char_ids[ch]), team])
	_send_to(from, NetProtocol.pack_slot(0, int(char_ids[ch]), team, team_size,
			world.time, world.target_score, world.match_duration, token, _mode_code(), _map_code()))

func _on_input(from: int, buf: PackedByteArray) -> void:
	var s: Dictionary = slots.get(from, {})
	if s.is_empty():
		return
	var d: Dictionary = NetProtocol.unpack_input(buf)
	# Seq gate (u16, wrap-aware): stale or replayed frames must not clobber
	# state (property tests: "client lies rejected").
	var diff := (int(d.seq) - int(s.last_seq) + 32768) % 65536 - 32768
	if diff <= 0:
		return
	s.last_seq = int(d.seq)
	var inp: NetInput = s.input
	inp.seq = int(d.seq)
	# Server clamps everything the client claims (move magnitude, aim bounds).
	inp.move = (d.move as Vector2).limit_length(1.0)
	inp.yaw = wrapf(float(d.yaw), -PI, PI)
	inp.pitch = clampf(float(d.pitch), -1.25, 0.9)
	inp.fire = bool(d.fire)
	inp.edges |= int(d.edges)
	# Latency measurement: the client tags each input with its estimate of
	# server time; the age is the one-way delay, clamped to the lag-comp
	# window. Drives World.hitscan rewind for this shooter.
	var te := float(d.get("time_est", 0.0))
	if te > 0.0:
		var dl := clampf(world.time - te, 0.0, world.lag_comp_window)
		s.delay = dl
		var ch: CharacterEntity = s.ch
		if ch != null and is_instance_valid(ch):
			ch.net_comp_delay = dl

## Creates a character in world with a stable id; humans get a
## NetPlayerController attached by the caller, bots by spawn_bot.
func _spawn_character(team: int, hero_data: HeroData, spawn: Vector3,
		is_human: bool) -> Hero:
	var ch := HeroFactory.create(team, false, hero_data.color, hero_data)
	if is_human:
		ch.display_name = "P%d" % (next_id)
	else:
		ch.display_name = "Bot %d" % (next_id)
	ch.position = spawn
	ch.rotation.y = PI if team == 0 else 0.0
	world.add_child(ch)
	world.register_character(ch)
	char_ids[ch] = next_id
	next_id += 1
	team_chars[team].append(ch)
	return ch

func spawn_bot(team: int, hero_data: HeroData, spawn: Vector3) -> Hero:
	var ch := _spawn_character(team, hero_data, spawn, false)
	var bc := BotController.new()
	ch.add_child(bc)
	bc.setup(ch, null, world, MatchConfig.difficulty)
	ch.controller = bc
	return ch

## New match in place (Phase 5 lifecycle v1): frees every character,
## projectile and zone, clears slot/frozen state (frozen tokens are
## invalidated) and re-arms the world via World.reset(). Bots are
## re-spawned by the scene through the match_reset signal. Server authority
## is untouched: this only happens on a hello, between physics ticks.
func reset_match() -> void:
	for ch in world.characters.duplicate():
		_free_character(ch)
	for pr in world.projectiles.duplicate():
		if is_instance_valid(pr):
			pr.free()
	for z in world.zones.duplicate():
		if is_instance_valid(z):
			z.free()
	_frozen.clear()
	slots.clear()
	team_humans = [0, 0]
	next_id = 0
	world.reset()
	if _pending_mode != "":
		# D20: apply the voted mode to the fresh match. Mode setup is pure
		# world data (no nodes), so a swap here is always safe.
		var vm: Mode = ModeRegistry.get_mode(_pending_mode)
		world.mode = vm
		vm.setup(world)
		print("SERVER next match mode from lobby vote: " + _pending_mode)
		_pending_mode = ""
	_snap_acc = 0.0
	print("SERVER match reset (fresh match in place, next_id=0)")
	match_reset.emit()

## D20: the lobby forwarded a decided mode vote (setmode). The server is
## authoritative about itself: validate the id and defer application to
## the next reset (a live match never changes rules mid-fight).
func set_mode_from_lobby(mode_id: String) -> void:
	if not ModeRegistry.ids().has(mode_id):
		print("SERVER setmode ignored (unknown mode " + mode_id + ")")
		return
	if mode_id == _pending_mode:
		return
	var current := "tdm"
	if world != null and world.mode != null:
		current = str(world.mode.mode_id)
	_pending_mode = mode_id
	print("SERVER voted mode accepted: " + mode_id + " (next match; current " + current + ")")

## D21: the lobby decided the map for the NEXT match. The scene (which
## owns the arena nodes) applies it via take_pending_map() on the next
## reset; like the mode, the running match never changes rules mid-fight.
func set_map_from_lobby(map_id: String) -> void:
	if map_id == "" or not MapRegistry.ids().has(map_id):
		return
	if map_id == _pending_map:
		return
	_pending_map = map_id
	print("SERVER voted map accepted: " + map_id + " (next match; current " + self.map_id + ")")

func take_pending_map() -> String:
	var pm := _pending_map
	_pending_map = ""
	return pm

func _is_frozen(ch: CharacterEntity) -> bool:
	for f in _frozen.values():
		if f.get("ch", null) == ch:
			return true
	return false

func _invalidates_frozen(ch: CharacterEntity) -> void:
	for k in _frozen.keys():
		if (_frozen[k] as Dictionary).get("ch", null) == ch:
			_frozen.erase(k)

## Token reattach: re-home the frozen character to the returning peer.
func _reattach(from: int, token: int) -> bool:
	var f: Dictionary = _frozen[token]
	_frozen.erase(token)
	var ch: CharacterEntity = f.get("ch", null)
	if ch == null or not is_instance_valid(ch):
		return false
	var inp := NetInput.new()
	var nc := NetPlayerController.new()
	ch.add_child(nc)
	nc.setup(ch, null, world, null)
	nc.input = inp
	ch.controller = nc
	ch.net_comp_delay = 0.0
	team_humans[int(f.team)] += 1
	slots[from] = {ch = ch, input = inp, team = int(f.team),
		hero_id = str(f.hero_id), token = token, last_seq = -1, delay = 0.0}
	print("SERVER peer %d reattached (token %d) -> slot %d team %d" % [from, token,
		int(char_ids.get(ch, -1)), int(f.team)])
	_send_to(from, NetProtocol.pack_slot(0, int(char_ids.get(ch, 0)), int(f.team),
			team_size, world.time, world.target_score, world.match_duration, token,
			_mode_code(), _map_code()))
	return true

func _free_character(ch: CharacterEntity) -> void:
	if ch == null or not is_instance_valid(ch):
		return
	_invalidates_frozen(ch)
	world.unregister_character(ch)
	team_chars[int(ch.team)].erase(ch)
	char_ids.erase(ch)
	# Immediate free (not queue_free): a yielding bot must leave its
	# spawn before the human is placed there - a frame of exact overlap
	# pushes the fresh human up ~1 m on join (Godot 4.7 overlap MTV).
	ch.free()

func _id_of(ch: CharacterEntity) -> int:
	if ch == null:
		return 0
	return int(char_ids.get(ch, 0))

func _send_snapshot() -> void:
	var chars: Array = []
	for ch in world.characters:
		var hd: HeroData = (ch as Hero).hero_data
		var idx := 0
		if hd != null:
			for i in HeroRegistry.HEROES.size():
				if (HeroRegistry.HEROES[i] as HeroData).id == hd.id:
					idx = i
					break
		var ex: Array = [1, 255, 255, 255, 255]
		if world.perk_system != null:
			ex = world.perk_system.char_extra(ch)  # D25 (v1.6)
		chars.append({
			id = _id_of(ch), team = ch.team, alive = ch.alive, hero_idx = idx,
			pos = ch.global_position, rot_y = ch.rotation.y,
			hp = ch.hp, max_hp = ch.max_hp, perk_extra = ex,
		})
	var projs: Array = []
	for pr in world.projectiles:
		if projs.size() >= NetProtocol.MAX_PROJS:
			break
		if not is_instance_valid(pr.shooter):
			continue  # shooter was freed (bot yield); the projectile expires soon
		projs.append({owner = _id_of(pr.shooter), pos = pr.global_position,
				dir = pr.dir.normalized()})
	var sc: Array = [int(world.score.get(0, 0)), int(world.score.get(1, 0))]
	if world.mode != null:
		sc = world.mode.score_of(world)  # HUD score = the mode's score
	var buf := NetProtocol.pack_snapshot(_snap_seq, world.time,
			int(sc[0]), int(sc[1]), world.winner, chars, projs,
			world.control_owner, world.control_progress_team, world.control_progress,
			_objective_ext())
	_snap_seq = (_snap_seq + 1) % 65536
	_tx(0, buf, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, NetProtocol.CH_UNRELIABLE)

## M_SLOT mode_code (Phase 6, D16/D17): 0 = TDM, 1 = Control, 2 = Capture,
## 3 = Escort. The client builds its HUD + world mirror for the mode from
## this byte.
func _mode_code() -> int:
	if world.mode == null:
		return 0
	match (world.mode as Mode).mode_id:
		"control":
			return 1
		"capture":
			return 2
		"escort":
			return 3
		_, _:
			return 0

## The 4 mode-specific snapshot bytes (wire §2, D17): flag carrier codes for
## Capture, payload progress/speed for Escort, zeros otherwise.
func _objective_ext() -> Array:
	var ext: Array = [0, 0, 0, 0]
	if world.mode == null:
		return ext
	match (world.mode as Mode).mode_id:
		"capture":
			ext[0] = _flag_carrier_code(0)
			ext[1] = _flag_carrier_code(1)
		"escort":
			ext[0] = int(clampf((world.mode as EscortMode).progress_of(world), 0.0, 1.0) * 255.0)
			ext[1] = int(clampf(world.payload_speed / maxf(0.001, (world.mode as EscortMode).max_speed), 0.0, 1.0) * 255.0)
	return ext

func _flag_carrier_code(flag_team: int) -> int:
	var ch: CharacterEntity = world.flag_carrier[flag_team]
	if ch == null or not is_instance_valid(ch):
		return 0
	return int(char_ids.get(ch, 0)) + 1

## M_SLOT map_code (D18): index into MapRegistry.ids() for the client's
## mirror arena.
func _map_code() -> int:
	var ids: Array = MapRegistry.ids()
	var i := ids.find(map_id)
	return i if i >= 0 else 0

func _on_world_event(name: String, data: Dictionary) -> void:
	var buf: PackedByteArray
	match name:
		"hit":
			var tgt: CharacterEntity = data.target
			var src: CharacterEntity = data.source
			buf = NetProtocol.pack_event_hit(_id_of(tgt), _id_of(src),
					float(data.amount), bool(data.is_head), bool(data.prot),
					Vector3(data.pos))
		"kill":
			buf = NetProtocol.pack_event_kill(str(data.killer), str(data.victim),
					int(data.killer_team), int(data.victim_team), bool(data.headshot))
		"respawn":
			var ch: CharacterEntity = data.ch
			if ch != null:
				buf = NetProtocol.pack_event_respawn(_id_of(ch), ch.global_position)
		"match_over":
			var sc: Array = data.score
			buf = NetProtocol.pack_event_match_over(int(data.winner), int(sc[0]),
					int(sc[1]), float(data.time))
			# D19: results stats BEFORE the over event (separate reliable
			# datagram; the client stores them for the results screen).
			_send_all(NetProtocol.pack_stats(world.stats_rows()))
		"heal":
			buf = NetProtocol.pack_event_heal(_id_of(data.target),
					_id_of(data.source), float(data.amount))
		"perk_level_up":
			var ch: CharacterEntity = data.ch
			var c: Array = data.choices
			buf = NetProtocol.pack_event_perk(_id_of(ch), int(data.level),
					_perk_idx(c[0] if c.size() > 0 else null),
					_perk_idx(c[1] if c.size() > 1 else null), 255)
		"perk_picked":
			var ch2: CharacterEntity = data.ch
			var pd: PerkData = data.perk
			buf = NetProtocol.pack_event_perk(_id_of(ch2), int(data.level),
					_perk_idx(pd), 255, int(data.choice_idx))
		_:
			return
	_send_all(buf)

## D25: perk pool index for the wire (255 = unknown/absent).
func _perk_idx(d: PerkData) -> int:
	if d == null or world == null or world.perk_system == null:
		return 255
	var pool: PerkPool = world.perk_system.pool
	return pool.index_of(d.id)

func _send_all(buf: PackedByteArray) -> void:
	_tx(0, buf, MultiplayerPeer.TRANSFER_MODE_RELIABLE, NetProtocol.CH_RELIABLE)

## D30: (re-)announce a slot to its peer (shared by the reattach and the
## idempotent re-hello paths).
func _send_slot(from: int, s: Dictionary) -> void:
	var ch: CharacterEntity = s.get("ch", null)
	_send_to(from, NetProtocol.pack_slot(0, int(char_ids.get(ch, 0)),
			int(s.get("team", 0)), team_size, world.time, world.target_score,
			world.match_duration, int(s.get("token", 0)), _mode_code(),
			_map_code()))

func _send_to(id: int, buf: PackedByteArray) -> void:
	_tx(id, buf, MultiplayerPeer.TRANSFER_MODE_RELIABLE, NetProtocol.CH_RELIABLE)

## Transport boundary: ENet, or the net-sim link when one is wired.
func _tx(id: int, buf: PackedByteArray, mode: int, ch: int) -> void:
	if sim_out != null:
		sim_out.send(id, buf, mode, ch)
	elif mp != null:
		mp.send_bytes(buf, id, mode, ch)

func exit() -> void:
	if mp != null and mp.multiplayer_peer != null:
		mp.multiplayer_peer.close()
