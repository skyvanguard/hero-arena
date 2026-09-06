class_name ModManifest
extends Resource
## D34 (mod support v1): the drop-in mod manifest. Every mod directory
## (res://mods/<id>/ bundled, user://mods/<id>/ user drop-in) must contain
## a mod.tres with exactly this script. `api_version` is the versioned mod
## API contract (see docs/MODS.md): a mod is accepted only when its
## api_version is <= ModLoader.API_VERSION (a mod built for a newer game
## API is rejected with a readable error, never a crash).
@export var id := ""
@export var display_name := ""
@export var author := ""
@export var desc := ""
@export var version := ""
@export var api_version := 1
