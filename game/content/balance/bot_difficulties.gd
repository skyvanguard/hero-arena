class_name BotDifficulties
extends RefCounted
## Registry for the four difficulty parameter packs (content/balance/bots/).
## Bots read their entire behavior profile from a BotDifficulty resource,
## so adding a tier is a data change, not a code change.

const IDS := ["beginner", "normal", "advanced", "expert"]

const PACKS: Dictionary = {
	"beginner": preload("res://content/balance/bots/beginner.tres"),
	"normal": preload("res://content/balance/bots/normal.tres"),
	"advanced": preload("res://content/balance/bots/advanced.tres"),
	"expert": preload("res://content/balance/bots/expert.tres"),
}

static func by_id(id: String) -> BotDifficulty:
	var p: BotDifficulty = PACKS.get(id, PACKS["normal"])
	return p

static func ids() -> Array:
	return IDS.duplicate()
