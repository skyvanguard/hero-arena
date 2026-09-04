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
var _accum := 0.0
var _lob_last_humans := -1
var _lob_last_over := false

func _ready() -> void:
	randomize()
	var port := MatchConfig.net_port
	var dport := MatchConfig.net_discovery_port
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.substr(7))
		elif a.begins_with("--dport="):
			dport = int(a.substr(8))
	var size := clampi(MatchConfig.team_size, 1, 6)
	world = World.new()
	world.name = "World"
	world.target_score = MatchConfig.target_score
	world.match_duration = MatchConfig.match_duration
	add_child(world)
	var arena := Arena.build(world)
	add_child(arena)
	net = MatchServer.new()
	add_child(net)
	net.setup(world, port, size)
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
	_register_lobby(port, size)

## Optional lobby registration (Phase 5 online): --lobby=host:port advertises
## this match into the matchmaking queue (region via --lregion, reachable
## address via --lip). Godot 4.7 removed OS.get_local_ip() (no core local-IP
## getter remains), so --lip defaults to 127.0.0.1: pass it explicitly when
## clients reach this server at a different address (e.g. 10.0.2.2 for the
## Android emulator NAT).
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
	var parts := lobby_addr.split(":")
	lob = LobbyClient.new()
	add_child(lob)
	lob.setup(String(parts[0]), int(parts[1]))
	if lip == "":
		# 4.7: no OS.get_local_ip() - advertise loopback and warn; --lip is
		# required for clients on a different network.
		lip = "127.0.0.1"
		push_warning("SERVER lobby: pass --lip=<reachable ip> (OS.get_local_ip was removed in Godot 4.7)")
	var lip_f := lip
	var lregion_f := lregion if lregion != "" else "latam_saopaulo"
	var lname_f := lname if lname != "" else ("match @" + lip_f)
	var port_f := port
	var size_f := size
	lob.connected_ok.connect(func() -> void:
		lob.register_match(lip_f, port_f, lregion_f, size_f, lname_f))
	print("SERVER lobby registration at %s (advertising %s, region %s)" % [
			lobby_addr, lip_f, lregion_f])

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
