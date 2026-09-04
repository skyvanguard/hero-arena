extends Node
## (autoload: MatchConfig — no class_name, the singleton name is the global)
## Session match configuration (autoload). Team size is configuration, never
## hardcoded (directive §4); 3v3 is the tuned default. difficulty is the bot
## tier id (content/balance/bots/). The hero select writes these; main reads
## them when building a match.

var difficulty := "normal"
var team_size := 3   # players per side (1..6); 3v3 tuned default

## TDM end condition (directive §6: 3–8 min matches). First team to
## target_score wins, or the higher score at match_duration. Data, not code.
var target_score := 15
var match_duration := 300.0  # 5 min, mid of the 3-8 min band (first to target_score, or higher score here)

## LAN server port (Phase 5 v1: direct connect).
var net_port := 7777
## LAN discovery port (Phase 5, UDP ping/reply; separate from the ENet game
## port, which owns UDP on net_port).
var net_discovery_port := 7778
## Lobby / matchmaking port (Phase 5 v1, UDP JSON-lines; see docs/NETWORKING).
## The lobby runs as a separate headless process (net/lobby.tscn).
var lobby_port := 7790

## Net v1.1 (Phase 5): client prediction for the local player. The client
## steps its own character through the same controller interface and
## reconciles against snapshots (hard-snap above a small distance; death /
## respawn always). Off = pure 100 ms interpolation (v1 behavior).
var net_prediction := true
## Server-side lag compensation: max rewind (s) World.hitscan applies to
## target poses when validating a net human's shot; the actual rewind is the
## shooter's measured input age clamped to this. 0 disables.
var lag_comp_window := 0.2

func set_difficulty(id: String) -> void:
	if BotDifficulties.ids().has(id):
		difficulty = id
