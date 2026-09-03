extends Node
## (autoload: MatchConfig — no class_name, the singleton name is the global)
## Session match configuration (autoload). Team size is configuration, never
## hardcoded (directive §4); 3v3 is the tuned default. difficulty is the bot
## tier id (content/balance/bots/). The hero select writes these; main reads
## them when building a match.

var difficulty := "normal"
var team_size := 3   # players per side (1..6); 3v3 tuned default

func set_difficulty(id: String) -> void:
	if BotDifficulties.ids().has(id):
		difficulty = id
