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
## peer_id -> {ch, input, team, hero_id}
var slots: Dictionary = {}
## CharacterEntity -> stable match id (0..MAX_CHARS-1)
var char_ids: Dictionary = {}
var next_id := 0
var team_chars: Array = [[], []]  # team -> [CharacterEntity] (bots + humans)
var team_humans: Array = [0, 0]  # per-team human count (bots are replaceable)
var _snap_acc := 0.0
var _snap_seq := 0
var _snap_interval := 1.0 / NetProtocol.SNAPSHOT_HZ

var _started := false

func setup(w: World, p: int, ts: int) -> void:
	world = w
	port = p
	team_size = ts
	if is_inside_tree():
		_start()

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
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 8)
	if err != OK:
		push_error("MatchServer: create_server(%d) failed: %d" % [port, err])
	mp.multiplayer_peer = peer
	mp.peer_connected.connect(_on_peer_connected)
	mp.peer_disconnected.connect(_on_peer_disconnected)
	mp.peer_packet.connect(_on_peer_packet)
	world.world_event.connect(_on_world_event)
	print("SERVER listening on port %d (team size %d)" % [port, team_size])

func _on_peer_connected(id: int) -> void:
	print("SERVER peer %d connected (awaiting hello)" % id)

func _on_peer_disconnected(id: int) -> void:
	# v1: the slot freezes in place (controller removed); reconnect lands in
	# a later Phase 5 round and will replace the frozen slot with a bot.
	var s: Dictionary = slots.get(id, {})
	var ch: CharacterEntity = s.get("ch", null)
	if ch != null and is_instance_valid(ch):
		ch.controller = null
		if s.has('team'):
			team_humans[int(s.team)] = maxi(0, int(team_humans[int(s.team)]) - 1)
	slots.erase(id)
	print("SERVER peer %d disconnected" % id)

## Call from the server scene after world.step(): poll the transport
## (peer_packet delivers) and emit snapshots at 20 Hz.
func tick(dt: float) -> void:
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
	var hero_data: HeroData = HeroRegistry.by_id(str(d.hero_id))
	if hero_data == null:
		hero_data = HeroRegistry.default_hero()
	# V1 team pick: join the side with fewer HUMANS (bots are replaceable).
	var team := 0 if team_humans[0] <= team_humans[1] else 1
	if team_humans[team] >= team_size:
		_send_to(from, NetProtocol.pack_slot(-1, 0, 0, team_size, world.time,
				world.target_score, world.match_duration))
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
		_free_character(team_chars[team].back())
	var ch := _spawn_character(team, hero_data, spawn, true)
	var inp := NetInput.new()
	var nc := NetPlayerController.new()
	ch.add_child(nc)
	nc.setup(ch, null, world, null)
	nc.input = inp
	ch.controller = nc
	team_humans[team] += 1
	slots[from] = {ch = ch, input = inp, team = team, hero_id = hero_data.id}
	print("SERVER peer %d -> %s slot %d team %d" % [from, hero_data.id, int(char_ids[ch]), team])
	_send_to(from, NetProtocol.pack_slot(0, int(char_ids[ch]), team, team_size,
			world.time, world.target_score, world.match_duration))

func _on_input(from: int, buf: PackedByteArray) -> void:
	var s: Dictionary = slots.get(from, {})
	if s.is_empty():
		return
	var inp: NetInput = s.input
	var d: Dictionary = NetProtocol.unpack_input(buf)
	inp.apply(d)

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

func _free_character(ch: CharacterEntity) -> void:
	if ch == null or not is_instance_valid(ch):
		return
	world.unregister_character(ch)
	team_chars[int(ch.team)].erase(ch)
	char_ids.erase(ch)
	ch.queue_free()

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
		chars.append({
			id = _id_of(ch), team = ch.team, alive = ch.alive, hero_idx = idx,
			pos = ch.global_position, rot_y = ch.rotation.y,
			hp = ch.hp, max_hp = ch.max_hp,
		})
	var projs: Array = []
	for pr in world.projectiles:
		if projs.size() >= NetProtocol.MAX_PROJS:
			break
		projs.append({owner = _id_of(pr.shooter), pos = pr.global_position,
				dir = pr.dir.normalized()})
	var buf := NetProtocol.pack_snapshot(_snap_seq, world.time,
			int(world.score.get(0, 0)), int(world.score.get(1, 0)), world.winner,
			chars, projs)
	_snap_seq = (_snap_seq + 1) % 65536
	mp.send_bytes(buf, 0, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, NetProtocol.CH_UNRELIABLE)

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
		"heal":
			buf = NetProtocol.pack_event_heal(_id_of(data.target),
					_id_of(data.source), float(data.amount))
		_:
			return
	_send_all(buf)

func _send_all(buf: PackedByteArray) -> void:
	mp.send_bytes(buf, 0, MultiplayerPeer.TRANSFER_MODE_RELIABLE, NetProtocol.CH_RELIABLE)

func _send_to(id: int, buf: PackedByteArray) -> void:
	mp.send_bytes(buf, id, MultiplayerPeer.TRANSFER_MODE_RELIABLE, NetProtocol.CH_RELIABLE)

func exit() -> void:
	if mp != null:
		mp.multiplayer_peer.close()
