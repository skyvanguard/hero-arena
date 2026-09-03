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

## LAN server port (Phase 5 v1: direct connect; discovery lands later).
var net_port := 7777

func set_difficulty(id: String) -> void:
	if BotDifficulties.ids().has(id):
		difficulty = id
