class_name MatchClient
extends Node
## LAN match client (Phase 5 v1, ARCHITECTURE §3.1): joins a MatchServer via
## ENet (Godot 4.7 SceneMultiplayer API), sends 20 Hz input frames (absolute
## camera yaw/pitch + edges), renders ALL characters from interpolated
## snapshots (100 ms delay ring), drives a local camera for the player slot.
## No client prediction yet (later Phase 5 round) - at LAN latency the
## interpolation delay masks the round trip.
signal ended(winner: int, score: Array, wtime: float, lost: bool, title: String)
var my_id := -1
var my_team := 0
var my_hero_id := ""
var mp: SceneMultiplayer
var world: World
var hud: NetHUD
var _hero_data: HeroData
var _host := ""
var _port := 7777
var _in_match := false
var _ended := false
var _acc := 0.0
var _input_interval := 1.0 / NetProtocol.INPUT_HZ
var _seq := 0
var _cam_yaw := 0.0
var _cam_pitch := -0.18
var _views: Dictionary = {}   # ch_id(int) -> CharacterEntity
var _ring: Array = []         # last 4 snapshots
var _ring_times: Array = []   # parallel server-times
var _rx_ms := 0
var _match_duration := 300.0
var _proj_views: Array = []   # pooled MeshInstance3D (cosmetic)

func setup(host_port: String, hero_data: HeroData) -> void:
	_hero_data = hero_data
	var parts: PackedStringArray = host_port.strip_edges().split(":")
	_host = parts[0] if parts.size() > 0 else "127.0.0.1"
	_port = int(parts[1]) if parts.size() > 1 else 7777
	if is_inside_tree():
		_start()

var _started := false

func _ready() -> void:
	_start()

func _start() -> void:
	# Order-insensitive init: setup() may run before or after add_child().
	if _started or _hero_data == null:
		return
	_started = true
	mp = SceneMultiplayer.new()
	# 4.7: SceneMultiplayer is a RefCounted MultiplayerAPI (not a Node) and
	# needs a root path in the tree + explicit poll() calls.
	mp.set_root_path(get_path())
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(_host, _port)
	if err != OK:
		_finish(-1, [0, 0], 0.0, true, "CONNECT FAILED (%d)" % err)
		return
	mp.multiplayer_peer = peer
	mp.connected_to_server.connect(_on_connected)
	mp.connection_failed.connect(_on_conn_failed)
	mp.server_disconnected.connect(_on_disconnected)
	mp.peer_packet.connect(_on_peer_packet)

func _on_connected() -> void:
	print("CLIENT connected to %s:%d" % [_host, _port])
	var buf := NetProtocol.pack_hello(MatchConfig.team_size, _hero_data.id)
	mp.send_bytes(buf, 0, MultiplayerPeer.TRANSFER_MODE_RELIABLE, NetProtocol.CH_RELIABLE)

func _on_conn_failed() -> void:
	_finish(-1, [0, 0], 0.0, true, "CONNECT FAILED")

func _on_disconnected() -> void:
	if _in_match and not _ended:
		_finish(-1, [0, 0], 0.0, true, "CONNECTION LOST")

func _process(delta: float) -> void:
	var n := 0
	while mp.poll() == OK and n < 64:
		n += 1
	if _in_match:
		_acc += delta
		while _acc >= _input_interval:
			_sample_input()
			_acc -= _input_interval
		_apply_views()

func _on_peer_packet(_id: int, buf: PackedByteArray) -> void:
	if buf.size() < 2:
		return
	var m: int = buf[0]
	if m == NetProtocol.M_SLOT:
		var d: Dictionary = NetProtocol.unpack_slot(buf)
		if int(d.result) != 0:
			_finish(-1, [0, 0], 0.0, true, "TEAM FULL")
			return
		my_id = int(d.ch_id)
		my_team = int(d.team)
		_match_duration = float(d.match_duration)
		_enter()
	elif m == NetProtocol.M_SNAPSHOT:
		_on_snapshot(NetProtocol.unpack_snapshot(buf))
	elif m == NetProtocol.M_EVENT:
		_on_event(NetProtocol.unpack_event(buf))

func _enter() -> void:
	_in_match = true
	my_hero_id = _hero_data.id
	world = World.new()
	world.name = "World"
	add_child(world)
	var arena := Arena.build(world)
	add_child(arena)
	_make_proj_pool()
	hud = NetHUD.new()
	add_child(hud)
	hud.my_team = my_team
	hud.set_state("IN MATCH  ·  slot %d" % my_id)
	print("CLIENT slot %d team %d (%s)" % [my_id, my_team, my_hero_id])

func _on_event(d: Dictionary) -> void:
	if not _in_match:
		return
	match int(d.type):
		NetProtocol.E_KILL:
			var line: String = str(d.killer) + " x " + str(d.victim)
			if bool(d.headshot):
				line += " (HS)"
			hud.set_feed(line)
		NetProtocol.E_MATCH_OVER:
			_finish(int(d.winner), d.score, float(d.time), false, "")

func _on_snapshot(d: Dictionary) -> void:
	_ring.append(d)
	_ring_times.append(float(d.time))
	if _ring.size() > 4:
		_ring.remove_at(0)
		_ring_times.remove_at(0)
	_rx_ms = Time.get_ticks_msec()
	if _in_match:
		var sc: Array = d.score
		hud.set_score(int(sc[0]), int(sc[1]))
		var remaining := int(ceilf(maxf(0.0, _match_duration - float(d.time))))
		hud.set_time(-1 if int(d.winner) != -1 else remaining)

## 20 Hz input sample: shared Controls contract + local absolute camera.
func _sample_input() -> void:
	if my_id < 0:
		return
	var aim: Vector2 = Controls.consume_aim()
	if aim == Vector2.ZERO:
		aim = Input.get_last_mouse_velocity() * 0.16
	_cam_yaw -= aim.x
	_cam_pitch = clampf(_cam_pitch - aim.y, -1.25, 0.9)
	var edges := 0
	if Controls.consume_jump():
		edges |= 1
	if Controls.consume_reload():
		edges |= 2
	if Controls.consume_ability1():
		edges |= 4
	if Controls.consume_ability2():
		edges |= 8
	if Controls.consume_ultimate():
		edges |= 16
	var buf := NetProtocol.pack_input(_seq, Controls.move, _cam_yaw, _cam_pitch,
			Controls.fire, edges)
	_seq = (_seq + 1) % 65536
	mp.send_bytes(buf, 0, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, NetProtocol.CH_UNRELIABLE)

## Interpolate every character between the two snapshots bracketing
## (latest server time - 100 ms) and write the view nodes.
func _apply_views() -> void:
	if _ring.size() == 0:
		return
	var now_ms := Time.get_ticks_msec()
	var latest_t: float = _ring_times.back()
	var rt: float = latest_t + (now_ms - _rx_ms) / 1000.0 - 0.1
	var latest: Dictionary = _ring.back()
	var chars: Array = latest.chars
	var seen: Dictionary = {}
	for c in chars:
		seen[c.id] = true
		var view: CharacterEntity = _ensure_view(int(c.id), int(c.hero_idx), int(c.team))
		if view == null:
			continue
		var pos: Vector3
		var rot_y: float
		if _ring.size() >= 2 and rt > _ring_times[_ring_times.size() - 2]:
			var prev: Dictionary = _ring[_ring.size() - 2]
			var pc: Variant = _find_char(prev, int(c.id))
			if pc != null:
				var t0: float = _ring_times[_ring_times.size() - 2]
				var span := latest_t - t0
				var f := clampf((rt - t0) / span, 0.0, 1.0) if span > 0.001 else 1.0
				pos = (pc.pos as Vector3).lerp(c.pos, f)
				rot_y = lerp_angle(float(pc.rot_y), float(c.rot_y), f)
			else:
				pos = c.pos
				rot_y = float(c.rot_y)
		else:
			pos = c.pos
			rot_y = float(c.rot_y)
		view.global_position = pos
		view.rotation.y = rot_y
		if bool(c.alive):
			view.show_visual()
		else:
			view.hide_visual()
		if int(c.id) == my_id:
			hud.set_hp(float(c.hp) / float(c.max_hp) if float(c.max_hp) > 0.0 else 1.0)
			_update_camera(view)
	# Stale views (character left the match: bot replaced by a human) free
	# after they stop appearing in snapshots.
	for k in _views.keys():
		if not seen.has(k):
			(_views[k] as CharacterEntity).queue_free()
			_views.erase(k)
	_apply_proj_views(latest)

func _find_char(snap: Dictionary, id: int) -> Variant:
	for c in snap.chars:
		if int(c.id) == id:
			return c
	return null

func _ensure_view(id: int, hero_idx: int, team: int) -> CharacterEntity:
	var v: CharacterEntity = _views.get(id, null)
	if v != null:
		return v
	var hd: HeroData = HeroRegistry.HEROES[hero_idx] if hero_idx < HeroRegistry.HEROES.size() else null
	var is_me := id == my_id
	var ch := HeroFactory.create(team, is_me, (hd.color if hd != null else Color.WHITE), hd)
	# View nodes are not simulated: zero physics participation, the transform
	# comes from snapshots. This includes nested bodies (the head sensor):
	# in a loopback test the client world shares the process physics space
	# with the server world, and a view sensor on the server character's head
	# blocks its LOS/weapon rays (bots never see each other).
	# Views are visual-only: zero ALL physics bodies (the body itself and
	# every nested body, e.g. the head sensor). The client world shares the
	# process physics space with the server world in loopback: a view body
	# on a server character would push it and block its LOS/weapon rays.
	# (find_children() with a type filter returns nothing on 4.7, so walk
	# the tree by hand, receiver included.)
	var stack: Array = [ch]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is PhysicsBody3D:
			(n as PhysicsBody3D).collision_layer = 0
			(n as PhysicsBody3D).collision_mask = 0
		for k in n.get_children():
			stack.append(k)
	if is_me:
		ch.display_name = "You"
	# First frame starts from the latest known server state, not (0,0,0).
	var c: Variant = _find_char(_ring.back(), id)
	if c != null:
		ch.global_position = c.pos
		ch.rotation.y = float(c.rot_y)
	world.add_child(ch)
	_views[id] = ch
	if c != null and not bool(c.alive):
		ch.hide_visual()
	return ch

func _update_camera(view: CharacterEntity) -> void:
	var rig: Node3D = view.camera_rig
	if rig == null:
		return
	# The render camera is rotated PI on Y inside the rig, so world camera
	# yaw = body yaw + rig yaw. Keep the absolute client yaw world-space:
	# rig yaw = absolute - body yaw.
	rig.rotation.y = _cam_yaw - view.rotation.y
	var cam: Camera3D = rig.get_node("Camera3D")
	cam.rotation.x = _cam_pitch

func _make_proj_pool() -> void:
	for i in NetProtocol.MAX_PROJS:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.09
		sm.height = 0.18
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.75, 0.95, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.5, 0.8, 1.0)
		mat.emission_energy_multiplier = 2.0
		sm.material = mat
		mi.mesh = sm
		mi.visible = false
		world.add_child(mi)
		_proj_views.append(mi)

func _apply_proj_views(latest: Dictionary) -> void:
	var projs: Array = latest.projs
	for i in _proj_views.size():
		var mi: MeshInstance3D = _proj_views[i]
		if i < projs.size():
			var p: Dictionary = projs[i]
			mi.global_position = p.pos
			mi.visible = true
		else:
			mi.visible = false

func _exit() -> void:
	exit()

func _finish(winner: int, score: Array, wtime: float, lost: bool, title: String) -> void:
	if _ended:
		return
	_ended = true
	print("CLIENT ended: winner=%d score=%s t=%.0f lost=%s %s" % [winner, str(score), wtime, str(lost), title])
	ended.emit(winner, score, wtime, lost, title)

func exit() -> void:
	if mp != null and mp.multiplayer_peer != null:
		mp.multiplayer_peer.close()
