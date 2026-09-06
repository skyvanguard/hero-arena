class_name MatchClient
extends Node
## LAN match client (Phase 5 v1.1, ARCHITECTURE §3.1): joins a MatchServer
## via ENet (Godot 4.7 SceneMultiplayer API), sends 20 Hz input frames
## (absolute camera yaw/pitch + edges + server-time estimate for lag-comp),
## renders remote characters from interpolated snapshots (100 ms delay ring)
## and the LOCAL character from client prediction (same controller
## interface as the server; reconciled against snapshots). Drop/reconnect:
## auto re-hello with the slot token (server freezes the slot, reattaches).
signal ended(winner: int, score: Array, wtime: float, lost: bool, title: String, stats: Array)
const MAX_RECONNECTS := 6
const PRED_STEP := 1.0 / 60.0
## Reconcile threshold: prediction vs server state (m). Above it the
## predicted character hard-snaps to the server (input changes, respawns).
const PRED_SNAP_DIST := 0.35
var my_id := -1
var my_team := 0
var my_hero_id := ""
var mp: SceneMultiplayer
var world: World
var hud: NetHUD
var _perk_pool: PerkPool = null  # D25 (client-side name resolution only)
## Net-sim transport (Phase 5): when set, send/recv bypass ENet entirely.
var sim_out: SimLink = null
var sim_in: SimLink = null
var _hero_data: HeroData
var _player_color := Color.WHITE  # D22: mastery-selected variant (client-side only)
## Character ids in SNAPSHOT order (= world.characters order = M_STATS row
## order). Match ids are 0-based but monotonically assigned (bot-only fills
## take 0..N-1, a joining human gets the next free id, freed bots' ids are
## never reused) - so my_id is NOT a stats row index; this order is.
var _char_order: Array = []

func stats_index_of(ch_id: int) -> int:
	return _char_order.find(ch_id)
var _host := ""
var _port := 7777
var _in_match := false
var _ended := false
## D19 results: final per-character stats (M_STATS), rows indexed by
## world.characters order (my row = my_id).
var _stats_rows: Array = []
var _acc := 0.0
var _input_interval := 1.0 / NetProtocol.INPUT_HZ
var _seq := 0
var _cam_yaw := 0.0
var _cam_pitch := -0.18
var _views: Dictionary = {}   # ch_id(int) -> CharacterEntity
var _ring: Array = []         # last 4 snapshots
var _ring_times: Array = []   # parallel server-times
var _rx_ms := 0
var _mode_code := 0
var _map_code := 0
var _control_marker_mat: StandardMaterial3D = null
var _control_owner_shown := -2
# Objective visuals (D17): capture flag boxes + base markers, escort payload.
var _flag_views: Array = []
var _flag_shown: Array = [-1, -1]
var _payload_view: MeshInstance3D = null
var _escort_start_x := 16.0
var _escort_goal_x := -16.0
var _match_duration := 300.0
var _proj_views: Array = []   # pooled MeshInstance3D (cosmetic)
var _last_score: Array = [0, 0]
# Session token from M_SLOT: re-hello carries it to reattach to a frozen slot.
var _token := 0
var _reconnects := 0
var _reconnecting := false
var _reconnect_acc := 0.0
# D30 re-hello watchdog: a slot reply lost on a lossy link is never
# retransmitted - re-send the hello so the server re-announces the slot.
const REHELLO_TIMEOUT := 2.0
const MAX_REHELLOS := 4
var _hello_acc := 0.0
var _rehellos := 0
# Client prediction (local player): a private World steps a twin character
# through NetPlayerController (same interface as the server-side humans) so
# the view is driven by prediction, not interpolation.
var _pred_on := false
var _pw: World = null
var _pch: Hero = null
var _pnc: NetPlayerController = null
var _p_in: NetInput = null
var _pred_acc := 0.0
var _pred_dead := true

func setup(host_port: String, hero_data: HeroData,
		player_color: Color = Color.WHITE) -> void:
	_hero_data = hero_data
	# D22 cosmetic: the player's predicted character wears the mastery-
	# selected variant color (Color.WHITE = caller had no bank -> default).
	_player_color = player_color
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
	mp.connected_to_server.connect(_on_connected)
	mp.connection_failed.connect(_on_conn_failed)
	mp.server_disconnected.connect(_on_disconnected)
	mp.peer_packet.connect(_on_peer_packet)
	if sim_out != null:
		return  # net-sim harness: the test drives connect/hello manually
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(_host, _port)
	if err != OK:
		_finish(-1, [0, 0], 0.0, true, "CONNECT FAILED (%d)" % err)
		return
	mp.multiplayer_peer = peer

func _on_connected() -> void:
	print("CLIENT connected to %s:%d" % [_host, _port])
	var buf := NetProtocol.pack_hello(MatchConfig.team_size, _hero_data.id, _token)
	_tx(0, buf, MultiplayerPeer.TRANSFER_MODE_RELIABLE, NetProtocol.CH_RELIABLE)
	_hello_acc = 0.0
	_rehellos = 0

func _on_conn_failed() -> void:
	if _ended:
		return
	if _in_match and _reconnects < MAX_RECONNECTS:
		_begin_reconnect()
	else:
		_finish(-1, _last_score, 0.0, true, "CONNECT FAILED")

func _on_disconnected() -> void:
	if _ended:
		return
	if _in_match and _reconnects < MAX_RECONNECTS:
		_begin_reconnect()
	else:
		_finish(-1, _last_score, 0.0, true, "CONNECTION LOST")

## Drop/reconnect (Phase 5): the server froze the slot on its side of the
## drop; re-dial with the slot token and the server reattaches the same
## character. Bounded retry, then give up with the last known score.
func _begin_reconnect() -> void:
	_reconnecting = true
	_reconnects += 1
	_reconnect_acc = 0.0
	if hud != null:
		hud.set_state("RECONNECTING %d/%d..." % [_reconnects, MAX_RECONNECTS])
	if mp != null and mp.multiplayer_peer != null:
		mp.multiplayer_peer.close()
		mp.multiplayer_peer = null

func _do_reconnect() -> void:
	if sim_out != null:
		# Net-sim harness: the test rewires the link + re-hellos manually.
		_reconnecting = false
		return
	if _host == "":
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(_host, _port)
	if err != OK:
		_reconnecting = false
		_finish(-1, _last_score, 0.0, true, "CONNECTION LOST")
		return
	mp.multiplayer_peer = peer

func _process(delta: float) -> void:
	if sim_in != null:
		sim_in.poll()
	elif mp != null and mp.multiplayer_peer != null:
		var n := 0
		while mp.poll() == OK and n < 64:
			n += 1
	if _reconnecting and not _ended:
		_reconnect_acc += delta
		if _reconnect_acc >= 0.5:
			_reconnect_acc = 0.0
			_do_reconnect()
	# D30 re-hello watchdog: if the slot never confirms within
	# REHELLO_TIMEOUT (the reply was lost on a lossy link), re-send the hello
	# with the same token; the server's idempotent re-hello re-announces the
	# slot (or completes a fresh join). Bounded - the transport watchdog
	# owns a dead server.
	if my_id < 0 and not _reconnecting and not _ended \
				and _rehellos < MAX_REHELLOS and _hero_data != null:
		_hello_acc += delta
		if _hello_acc >= REHELLO_TIMEOUT:
			_hello_acc = 0.0
			_rehellos += 1
			_tx(0, NetProtocol.pack_hello(MatchConfig.team_size,
					_hero_data.id, _token),
					MultiplayerPeer.TRANSFER_MODE_RELIABLE,
					NetProtocol.CH_RELIABLE)
	if _in_match:
		_acc += delta
		while _acc >= _input_interval:
			_sample_input()
			_acc -= _input_interval
		_apply_views()

## Client prediction: step the local twin at 60 Hz (same fixed step as the
## server) so the predicted path matches the server's integration.
func _physics_process(delta: float) -> void:
	if not _pred_on or not _in_match or _pch == null or _pw == null:
		return
	if _pred_dead:
		return
	_pred_acc += delta
	var steps := 0
	while _pred_acc >= PRED_STEP and steps < 4:
		_pred_acc -= PRED_STEP
		_pw.step(PRED_STEP)
		steps += 1

func _on_peer_packet(_id: int, buf: PackedByteArray) -> void:
	if buf.size() < 2:
		return
	var m: int = buf[0]
	if m == NetProtocol.M_SLOT:
		var d: Dictionary = NetProtocol.unpack_slot(buf)
		if int(d.result) != 0:
			if int(d.result) == -2:
				_finish(-1, _last_score, 0.0, false, "MATCH OVER")
			else:
				_finish(-1, _last_score, 0.0, true, "TEAM FULL")
			return
		var tk := int(d.get("token", 0))
		if tk > 0:
			_token = tk
		my_id = int(d.ch_id)
		my_team = int(d.team)
		_match_duration = float(d.match_duration)
		_mode_code = int(d.get("mode_code", 0))
		_map_code = int(d.get("map_code", 0))
		if world == null:
			_enter()
		else:
			# Re-slot after reconnect: keep world/views; the next snapshot
			# hard-syncs the prediction.
			_reconnecting = false
			if hud != null:
				hud.set_state("IN MATCH  ·  slot %d" % my_id)
	elif m == NetProtocol.M_SNAPSHOT:
		_on_snapshot(NetProtocol.unpack_snapshot(buf))
	elif m == NetProtocol.M_EVENT:
		_on_event(NetProtocol.unpack_event(buf))
	elif m == NetProtocol.M_STATS:
		_stats_rows = NetProtocol.unpack_stats(buf)  # D19: arrive before match_over

func _enter() -> void:
	_in_match = true
	my_hero_id = _hero_data.id
	world = World.new()
	world.name = "World"
	add_child(world)
	# Mirror arena from the SERVER's map (M_SLOT map_code, D18) so spawns and
	# geometry match the authoritative world.
	var ids: Array = MapRegistry.ids()
	var mid: String = ids[_map_code] if _map_code < ids.size() else MapRegistry.DEFAULT_ID
	var arena := Arena.build(world, MapRegistry.get_map(mid))
	add_child(arena)
	if _mode_code == 1:
		world.control_active = true
		world.control_point = Vector3.ZERO  # v1: fixed at arena center (wire §2)
		_build_control_marker()
	elif _mode_code == 2:
		_build_capture_visuals()
	elif _mode_code == 3:
		_build_escort_visual()
	_make_proj_pool()
	hud = NetHUD.new()
	add_child(hud)
	hud.my_team = my_team
	hud.set_state("IN MATCH  ·  slot %d" % my_id)
	# D25: the client's perk pool (same content resource as the server) for
	# resolving E_PERK pool indices to names; card taps become input edges.
	_perk_pool = load("res://content/perks/perks.tres")
	hud.perk_chosen.connect(_on_perk_chosen)
	_pred_on = MatchConfig.net_prediction
	if _pred_on:
		_pw = World.new()
		_pw.name = "PredictWorld"
		add_child(_pw)
		var parena := Arena.build(_pw)
		add_child(parena)
		_p_in = NetInput.new()
	print("CLIENT slot %d team %d (%s)" % [my_id, my_team, my_hero_id])

## Capture visuals (D17): a base marker per team (central spawn, team color)
## + one flag box per flag that follows the CARRIER'S view (wire ext codes;
## code 0 = at base/dropped, the base marker stands in for it - v1).
func _build_capture_visuals() -> void:
	var pts0: Array = world.spawn_points.get(0, [])
	var pts1: Array = world.spawn_points.get(1, [])
	var bases: Array = []
	for pts in [pts0, pts1]:
		var b: Vector3 = pts[1] if pts.size() > 1 else (pts[0] if pts.size() == 1 else Vector3(16.0, 0.9, 0.0))
		bases.append(b)
	var cols: Array = [Color(0.3, 0.55, 0.95, 0.5), Color(0.95, 0.35, 0.3, 0.5)]
	for ft in 2:
		var bm := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.5
		cm.bottom_radius = 0.5
		cm.height = 1.4
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = cols[ft]
		cm.material = mat
		bm.mesh = cm
		bm.position = Vector3(bases[ft].x, 0.7, bases[ft].z)
		world.add_child(bm)
		var fv := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(0.25, 1.1, 0.25)
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = cols[ft].lerp(Color.WHITE, 0.35)
		fb.material = fmat
		fv.mesh = fb
		fv.visible = false
		world.add_child(fv)
		_flag_views.append(fv)

## Escort visual (D17): the payload box; x comes from the snapshot progress
## along the same deterministic lane the server uses (central spawn x's).
func _build_escort_visual() -> void:
	var pts0: Array = world.spawn_points.get(0, [])
	var pts1: Array = world.spawn_points.get(1, [])
	_escort_start_x = pts0[1].x if pts0.size() > 1 else 16.0
	_escort_goal_x = pts1[1].x if pts1.size() > 1 else -16.0
	var pv := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 0.7, 1.1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.8, 0.25)
	bm.material = mat
	pv.mesh = bm
	pv.position = Vector3(_escort_start_x, 0.35, 0.0)
	world.add_child(pv)
	_payload_view = pv

func _objective_visuals(ext: Array) -> void:
	if _mode_code == 2:
		for ft in 2:
			var code: int = int(ext[ft])
			if code == _flag_shown[ft]:
				continue
			_flag_shown[ft] = code
			var fv: MeshInstance3D = _flag_views[ft]
			if code == 0:
				fv.visible = false
			else:
				var view = _views.get(code - 1, null)
				fv.visible = view != null and is_instance_valid(view)
			if fv.visible:
				var view2 = _views.get(code - 1, null)
				if is_instance_valid(view2):
					fv.global_position = view2.global_position + Vector3(0.0, 1.6, 0.0)
	elif _mode_code == 3 and _payload_view != null:
		var x: float = lerpf(_escort_start_x, _escort_goal_x, float(ext[0]) / 255.0)
		_payload_view.position = Vector3(x, 0.35, 0.0)

## Capture HUD (D17): one imperative line per flag situation (on-change in
## NetHUD keeps the GL canvas quiet).
func _hud_capture(ext: Array) -> void:
	var enemy_code: int = int(ext[1 - my_team])
	var own_code: int = int(ext[my_team])
	if enemy_code == my_id + 1:
		hud.set_control(-1, my_team, 1.0, "RETURN THE FLAG!")
	elif own_code != 0:
		hud.set_control(-1, 1 - my_team, 1.0, "OUR FLAG IS DOWN!")
	else:
		hud.set_control(-1, -1, 0.0, "STEAL THE ENEMY FLAG")

## Control point floor marker (v1: one central circle at the arena origin).
## Color updates only on OWNER change (GL canvas write-on-change rule).
func _build_control_marker() -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 4.0  # ControlMode.capture_radius (wire keeps it fixed in v1)
	cm.bottom_radius = 4.0
	cm.height = 0.05
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.8, 0.8, 0.9, 0.18)
	cm.material = mat
	mi.mesh = cm
	mi.position = Vector3(0.0, 0.04, 0.0)
	world.add_child(mi)
	_control_marker_mat = mat

func _on_event(d: Dictionary) -> void:
	if not _in_match:
		return
	match int(d.type):
		NetProtocol.E_KILL:
			var line: String = str(d.killer) + " x " + str(d.victim)
			if bool(d.headshot):
				line += " (HS)"
			hud.set_feed(line)
		NetProtocol.E_PERK:
			_on_perk_event(d)
		NetProtocol.E_MATCH_OVER:
			var w: int = int(d.winner)
			var lost := w != -1 and w != my_team
			var sc: Array = d.score
			if my_team == 1:
				sc = [sc[1], sc[0]]  # local-team-first for the results overlay
			_finish(w, sc, float(d.time), lost,
					"" if w == -1 else ("DEFEAT" if lost else "VICTORY"))

## D25: perk level-up (pending=255) shows the cards for MY slot; a pick
## confirmation sets the badge. Other slots get a feed line.
func _on_perk_event(d: Dictionary) -> void:
	if _perk_pool == null:
		return
	var me := int(d.ch_id) == my_id
	var lvl := int(d.level)
	var pk := int(d.picked)
	if me:
		if pk == 255:
			var n: Array = []
			var ds: Array = []
			for ci in [int(d.choice0), int(d.choice1)]:
				var p := _perk_pool.get_perk(_perk_pool.perks[ci].id) if ci < _perk_pool.perks.size() else null
				n.append(p.name if p != null else "—")
				ds.append(p.desc if p != null else "")
			hud.set_perk_choices(n, ds, lvl)
		else:
			var p2 := _perk_pool.get_perk(_perk_pool.perks[int(d.choice0)].id) if int(d.choice0) < _perk_pool.perks.size() else null
			hud.set_perk_picked(p2.name if p2 != null else "Perk", lvl)
	else:
		var nm: String = ""
		if pk != 255 and int(d.choice0) < _perk_pool.perks.size():
			nm = _perk_pool.perks[int(d.choice0)].name
		if pk == 255:
			hud.set_feed("A teammate or enemy leveled up (LV%d)" % lvl)
		elif nm != "":
			hud.set_feed("Perk: %s" % nm)

func _on_perk_chosen(idx: int) -> void:
	# The pick rides the next 20 Hz input frame as an edge bit (32/64);
	# the server validates it (a stale pick is rejected, cards stay up).
	Controls.perk_pick = idx

func _on_snapshot(d: Dictionary) -> void:
	_char_order = []
	for c in d.chars:
		_char_order.append(int(c.id))
	_ring.append(d)
	_ring_times.append(float(d.time))
	if _ring.size() > 4:
		_ring.remove_at(0)
		_ring_times.remove_at(0)
	_rx_ms = Time.get_ticks_msec()
	if _in_match:
		var sc: Array = d.score
		_last_score = [int(sc[0]), int(sc[1])]
		hud.set_score(int(sc[0]), int(sc[1]))
		var remaining := int(ceilf(maxf(0.0, _match_duration - float(d.time))))
		hud.set_time(-1 if int(d.winner) != -1 else remaining)
		var ctl: Array = d.get("control", [-1, -1, 0.0])
		if is_instance_valid(world):
			world.control_owner = int(ctl[0])
			world.control_progress = float(ctl[2])
		var own: int = int(ctl[0])
		if _control_marker_mat != null and own != _control_owner_shown:
			_control_owner_shown = own
			var c := Color(0.8, 0.8, 0.9, 0.18)
			if own == 0:
				c = Color(0.25, 0.45, 0.9, 0.25)
			elif own == 1:
				c = Color(0.9, 0.3, 0.25, 0.25)
			_control_marker_mat.albedo_color = c
		var ext: Array = d.get("ext", [0, 0, 0, 0])
		_objective_visuals(ext)
		if hud != null:
			if _mode_code == 2:
				_hud_capture(ext)
			elif _mode_code == 3:
				var pp: float = float(ext[0]) / 255.0
				hud.set_control(-1, 0, pp, "PAYLOAD %d%%" % int(pp * 100.0))
			else:
				hud.set_control(int(ctl[0]), int(ctl[1]), float(ctl[2]))
		_reconcile(d)

## Current server-time estimate (latest snapshot time + elapsed since RX).
## Tagged onto every input frame: the server measures one-way latency from
## it and rewinds targets by that much when validating this client's shots.
func _est_server_time() -> float:
	if _ring_times.is_empty():
		return 0.0
	var latest_t: float = _ring_times.back()
	if _rx_ms == 0:
		return latest_t
	return latest_t + (Time.get_ticks_msec() - _rx_ms) / 1000.0

## Reconcile the predicted local character against a fresh snapshot:
## death/respawn always hard-sync; above PRED_SNAP_DIST the prediction
## snapped (input changes land here - the server saw the old input).
func _reconcile(d: Dictionary) -> void:
	if not _pred_on or _pw == null:
		return
	var mc: Variant = _find_char(d, my_id)
	if mc == null:
		return
	if not bool(mc.alive):
		if not _pred_dead:
			_pred_dead = true
		return
	if _pch == null:
		_ensure_predicted(mc)
		_pred_dead = false
		return
	if _pred_dead:
		_pred_dead = false
		_pch.global_position = mc.pos
		_pch.rotation.y = float(mc.rot_y)
		_pch.velocity = Vector3.ZERO
		return
	var err := (_pch.global_position - (mc.pos as Vector3)).length()
	if err > PRED_SNAP_DIST:
		_pch.global_position = mc.pos
		_pch.rotation.y = float(mc.rot_y)
		_pch.velocity = Vector3.ZERO

## Create the predicted twin on the first snapshot that carries our state:
## same controller interface as the server-side human (NetPlayerController),
## colliding with WORLD geometry only (never characters - the server owns
## character-vs-character physics), and with all NESTED bodies zeroed (in
## loopback the twin shares the process physics space with the server world;
## a stray head-sensor would block server LOS/weapon rays again).
func _ensure_predicted(c: Dictionary) -> void:
	var pc: Color = _player_color if _player_color != Color.WHITE else _hero_data.color
	_pch = HeroFactory.create(my_team, false, pc, _hero_data)
	_pch.display_name = "You"
	_pch.collision_layer = 0
	var stack: Array = [_pch]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is PhysicsBody3D:
			(n as PhysicsBody3D).collision_layer = 0
			(n as PhysicsBody3D).collision_mask = 0
		for k in n.get_children():
			stack.append(k)
	_pch.collision_mask = CharacterEntity.LAYER_WORLD
	# Not in the tree yet: local position (_pw is at the origin); global
	# pre-add errors on 4.7.
	_pch.position = c.pos
	_pch.rotation.y = float(c.rot_y)
	_pch.hide_visual()  # the VIEW renders; the twin is physics-only
	_pw.add_child(_pch)
	_pw.register_character(_pch)
	_pnc = NetPlayerController.new()
	_pch.add_child(_pnc)
	_pnc.setup(_pch, null, _pw, null)
	_pnc.input = _p_in
	_pch.controller = _pnc

## 20 Hz input sample: shared Controls contract + local absolute camera.
## The SAME frame drives the predicted twin (client-side parity with the
## server: identical input, identical controller, identical 60 Hz physics).
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
	var ppk := Controls.consume_perk_pick()  # D25: perk choice edges
	if ppk == 0:
		edges |= 32
	elif ppk == 1:
		edges |= 64
	var move: Vector2 = Controls.move.limit_length(1.0)
	var buf := NetProtocol.pack_input(_seq, move, _cam_yaw, _cam_pitch,
			Controls.fire, edges, _est_server_time())
	_seq = (_seq + 1) % 65536
	_tx(0, buf, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, NetProtocol.CH_UNRELIABLE)
	if _pred_on and _p_in != null and not _pred_dead:
		_p_in.move = move
		_p_in.yaw = _cam_yaw
		_p_in.pitch = _cam_pitch
		_p_in.fire = Controls.fire
		_p_in.edges = edges
		if _pch != null and _pnc != null:
			_pnc.input = _p_in

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
		if int(c.id) == my_id and _pred_on and _pch != null and not _pred_dead:
			# Local character: prediction drives the view (no 100 ms delay).
			view.global_position = _pch.global_position
			view.rotation.y = _pch.rotation.y
		else:
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
	# ch is not in the tree yet: use local position (world is at the origin,
	# so local == global); setting global_position pre-add errors on 4.7.
	var c: Variant = _find_char(_ring.back(), id)
	if c != null:
		ch.position = c.pos
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
	ended.emit(winner, score, wtime, lost, title, _stats_rows)

func _tx(id: int, buf: PackedByteArray, mode: int, ch: int) -> void:
	if sim_out != null:
		sim_out.send(id, buf, mode, ch)
	elif mp != null:
		mp.send_bytes(buf, id, mode, ch)

func exit() -> void:
	if _pw != null and is_instance_valid(_pw):
		_pw.queue_free()
		_pw = null
		_pch = null
		_pnc = null
	if mp != null and mp.multiplayer_peer != null:
		mp.multiplayer_peer.close()
