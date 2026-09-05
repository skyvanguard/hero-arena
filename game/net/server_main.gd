extends Node
## Dedicated headless match server scene (Phase 5): same codebase, 60 Hz
## authoritative World, ENet transport. Run:
##   godot --headless --path game res://net/server.tscn -- --port=7777
## Bot fill: both teams pre-spawned at MatchConfig.team_size; a human join
## takes the last bot's spot (MatchServer._on_hello).
const FIXED_DT := 1.0 / 60.0

var world: World
var net: MatchServer
var disc: Discovery
var lob: LobbyClient = null
var _team_size := 3
var _relay: RelayClient = null
var _relay_vport := 0
var _pending_lobby := false
var _lob_args: Array = []  # [lobby_addr, lregion, lname, lip]
var _accum := 0.0
var _lob_last_humans := -1
var _lob_last_over := false
var _ctllog := false  # --ctllog: print control-point state every 10 s (ops/debug)
var _ctllog_n := 0

func _ready() -> void:
	randomize()
	var port := MatchConfig.net_port
	var dport := MatchConfig.net_discovery_port
	var relay_addr := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.substr(7))
		elif a.begins_with("--dport="):
			dport = int(a.substr(8))
		elif a.begins_with("--mode="):
			MatchConfig.mode_id = a.substr(7)  # tdm | control (ModeRegistry)
		elif a == "--ctllog":
			_ctllog = true
		elif a.begins_with("--relay="):
			relay_addr = a.substr(8)
	var size := clampi(MatchConfig.team_size, 1, 6)
	world = World.new()
	world.name = "World"
	world.target_score = MatchConfig.target_score
	world.match_duration = MatchConfig.match_duration
	add_child(world)
	var arena := Arena.build(world)
	add_child(arena)
	# Mode framework v1 (Phase 6, D16): rules as a data resource. Control
	# pins its point at the arena center (v1; rotating points = follow-up).
	world.mode = ModeRegistry.get_mode(MatchConfig.mode_id)
	if world.mode != null and world.mode.mode_id == "control":
		world.control_active = true
		world.control_point = Vector3.ZERO
		print("SERVER mode: control (point at arena center)")
	net = MatchServer.new()
	add_child(net)
	net.setup(world, port, size)
	_team_size = size
	net.match_reset.connect(_on_match_reset)
	_fill_teams(size)
	# LAN discovery responder (UDP ping/reply with live match state).
	disc = Discovery.new()
	disc.game_port = port
	var net_ref := net
	var world_ref := world
	var size_ref := size
	disc.state_provider = func() -> Dictionary:
		var state := NetProtocol.DISC_OPEN
		if world_ref.match_over:
			state = NetProtocol.DISC_OVER
		else:
			var full := true
			for t in 2:
				if int(net_ref.team_humans[t]) < size_ref:
					full = false
			if full:
				state = NetProtocol.DISC_FULL
		return {"state": state, "team_size": size_ref,
				"humans": int(net_ref.team_humans[0]) + int(net_ref.team_humans[1]),
				"target_score": world_ref.target_score, "time": world_ref.time}
	add_child(disc)
	disc.setup(dport)
	# NAT traversal v1 (round 29, D15): --relay=ip:port registers this match
	# in the relay over an OUTBOUND UDP connection (the only direction a NAT
	# mapping exists for). The relay grants a virtual port; the lobby
	# registration is deferred until then and advertises <relay_ip>:<vport>.
	# LAN discovery is unaffected (LAN clients still reach the server
	# directly; the relay serves clients on other networks).
	if relay_addr != "":
		var rparts := relay_addr.split(":")
		_relay = RelayClient.new()
		add_child(_relay)
		_relay.setup(String(rparts[0]), int(rparts[1]), port)
		_relay.registered.connect(_on_relay_registered)
	_register_lobby(port, size)

## Optional lobby registration (Phase 5 online): --lobby=host:port advertises
## this match into the matchmaking queue (region via --lregion, reachable
## address via --lip). Godot 4.7 removed OS.get_local_ip() (no core local-IP
## getter remains), so --lip defaults to 127.0.0.1: pass it explicitly when
## clients reach this server at a different address (e.g. 10.0.2.2 for the
## Android emulator NAT). With --relay=, the published address is the relay's
## virtual port instead (clients on other networks reach the NAT'd server
## through the relay; D15).
func _register_lobby(port: int, size: int) -> void:
	var lobby_addr := ""
	var lregion := ""
	var lname := ""
	var lip := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lobby="):
			lobby_addr = a.substr(8)
		elif a.begins_with("--lregion="):
			lregion = a.substr(10)
		elif a.begins_with("--lname="):
			lname = a.substr(8)
		elif a.begins_with("--lip="):
			lip = a.substr(6)
	if lobby_addr == "":
		return
	_lob_args = [lobby_addr, lregion, lname, lip, port, size]
	if _relay != null and _relay_vport <= 0:
		_pending_lobby = true
		print("SERVER lobby: deferring registration until the relay grants a virtual port")
		return
	_do_lobby_register()

func _on_relay_registered(vport: int) -> void:
	_relay_vport = vport
	if _pending_lobby:
		_pending_lobby = false
		_do_lobby_register()

func _do_lobby_register() -> void:
	var lobby_addr: String = String(_lob_args[0])
	var lregion: String = String(_lob_args[1])
	var lname: String = String(_lob_args[2])
	var lip: String = String(_lob_args[3])
	var port: int = int(_lob_args[4])
	var size: int = int(_lob_args[5])
	var parts := lobby_addr.split(":")
	lob = LobbyClient.new()
	add_child(lob)
	lob.setup(String(parts[0]), int(parts[1]))
	var lip_f := lip
	var port_f := port
	if _relay != null and _relay_vport > 0:
		# Published address = the relay's virtual port: clients connect to
		# <relay_ip>:<vport> and the relay pumps the stream to our NAT
		# mapping. --lip is unused in relay mode.
		lip_f = _relay.relay_ip
		port_f = _relay_vport
	elif lip == "":
		# 4.7: no OS.get_local_ip() - advertise loopback and warn; --lip is
		# required for clients on a different network.
		lip_f = "127.0.0.1"
		push_warning("SERVER lobby: pass --lip=<reachable ip> (OS.get_local_ip was removed in Godot 4.7)")
	var lregion_f := lregion if lregion != "" else "latam_saopaulo"
	var lname_f := lname if lname != "" else ("match @" + lip_f)
	var size_f := size
	lob.connected_ok.connect(func() -> void:
		lob.register_match(lip_f, port_f, lregion_f, size_f, lname_f))
	print("SERVER lobby registration at %s (advertising %s:%d, region %s)" % [
			lobby_addr, lip_f, port_f, lregion_f])

## --ctllog: periodic control-point state line (ops/debug; 600 frames = 10 s).
func _ctllog_tick() -> void:
	if not _ctllog:
		return
	_ctllog_n += 1
	if _ctllog_n < 600:
		return
	_ctllog_n = 0
	var inside := ""
	for c in world.characters:
		if not c.alive:
			continue
		var d: Vector3 = c.global_position - world.control_point
		if d.x * d.x + d.z * d.z <= 16.0 and absf(d.y) <= 2.0:
			inside += str(int(c.team))
	print("SERVER ctl t=%.1f owner=%d prog=%.2f pteam=%d cscore=%s kills=%s inside=[%s]" % [
		world.time, world.control_owner, world.control_progress,
		world.control_progress_team, str(world.control_score), str(world.score), inside])
	print("SERVER ctl mode=%s active=%s over=%s target=%d dur=%.0f" % [
		str(world.mode), world.control_active, world.match_over, world.target_score, world.match_duration])

## A fresh match started in place (MatchServer.reset_match, triggered by a
## join into an over match with no humans left): re-fill the bots with a
## fresh shuffled roster, same composition as startup.
func _on_match_reset() -> void:
	_fill_teams(_team_size)

func _fill_teams(size: int) -> void:
	# Same roster variety as the offline match (main.gd): shuffled heroes.
	var roster: Array = HeroRegistry.HEROES.duplicate()
	roster.shuffle()
	var rix := 0
	for team in 2:
		var pts: Array = world.spawn_points.get(team, [])
		for i in size:
			if pts.size() <= i:
				break
			var data: HeroData = roster[rix % roster.size()]
			rix += 1
			net.spawn_bot(team, data, pts[i])

func _physics_process(delta: float) -> void:
	_ctllog_tick()
	_accum += delta
	var steps := 0
	while _accum >= FIXED_DT and steps < 4:
		world.step(FIXED_DT)
		_accum -= FIXED_DT
		steps += 1
	net.tick(delta)
	if lob != null:
		var humans := int(net.team_humans[0]) + int(net.team_humans[1])
		if humans != _lob_last_humans or world.match_over != _lob_last_over:
			_lob_last_humans = humans
			_lob_last_over = world.match_over
			lob.send_state(humans, world.match_over)
