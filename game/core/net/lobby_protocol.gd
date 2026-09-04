class_name LobbyProtocol
extends RefCounted
## Lobby wire protocol (Phase 5 v1 prototype).
##
## Transport: plain TCP, one JSON object per line ("\n"-terminated). This is
## a control channel (a few messages per match, not the 20 Hz sim path), so
## JSON lines were chosen over the binary net protocol for debuggability.
## All strings ASCII. Message types:
##   client -> lobby: ping, join {region, party, skill, name}
##   lobby -> client: hello {region, matches, waiters}, pong,
##                    queue {stage, waited, open}, assign {host, port, ...}
##   match -> lobby:  reg {ip, port, region, team_size, name}, state {humans, over}, hb
##   lobby -> match:  regack {match_id}

const T_PING := "ping"
const T_PONG := "pong"
const T_HELLO := "hello"
const T_JOIN := "join"
const T_QUEUE := "queue"
const T_ASSIGN := "assign"
const T_REG := "reg"
const T_REGACK := "regack"
const T_STATE := "state"
const T_HB := "hb"

const QUEUE_STAGE_STRICT := 1
const QUEUE_STAGE_SKILL := 2
const QUEUE_STAGE_REGION := 3
const QUEUE_STAGE_BOTFILL := 4
const QUEUE_MAX_WAIT := 300.0

static func pack(msg: Dictionary) -> PackedByteArray:
	return (JSON.stringify(msg) + "\n").to_utf8_buffer()

static func unpack_line(line: String) -> Dictionary:
	var j: JSON = JSON.new()
	if j.parse(line) != OK:
		return {}
	var v = j.data
	if v is Dictionary:
		return v
	return {}

## (Named msg_type: "type" is a reserved identifier in Godot 4.7 GDScript.)
static func msg_type(msg: Dictionary) -> String:
	return str(msg.get("t", ""))

## Split a received byte buffer into complete lines: returns [lines, tail]
## where tail is the trailing partial line (re-prepend it on the next read).
static func split_lines(buf: String) -> Array:
	# 4.7: PackedStringArray has no pop_back() - index manually.
	var lines: Array = []
	var parts: PackedStringArray = buf.split("\n")
	var n := parts.size()
	var tail := ""
	var last := n
	if not buf.ends_with("\n"):
		tail = str(parts[n - 1])
		last = n - 1
	for i in last:
		var s: String = str(parts[i]).strip_edges()
		if s != "":
			lines.append(s)
	return [lines, tail]
