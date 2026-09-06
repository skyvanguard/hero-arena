class_name SeasonBank
extends Resource
## D26: the season bank - content/cosmetics/seasons.tres holds every
## SeasonData + which one is current. Adding a season is a data change;
## the current track is content, not code.

const BANK_PATH := "res://content/cosmetics/seasons.tres"

@export var seasons: Array = []
@export var current_season := ""

static func load_seasons() -> SeasonBank:
	var r = load(BANK_PATH)
	if r is SeasonBank:
		return r
	var empty := SeasonBank.new()
	empty.seasons = []
	return empty

func data_of(id: String) -> SeasonData:
	for s in seasons:
		if s is SeasonData and str(s.id) == id:
			return s
	return null

func current() -> SeasonData:
	return data_of(current_season)

## Display name of the current season ("" when the bank is missing/empty).
static func current_name() -> String:
	var b := load_seasons()
	var c := b.current()
	return c.display_name if c != null else ""

## Validation (headless): returns an error list, empty when the whole bank
## is well-formed (unique ids, current exists, every pack entry resolves
## to a real palette index, no duplicate entries, non-empty current pack).
static func validate(bank: SeasonBank) -> Array:
	var errs: Array = []
	var seen: Array = []
	for s in bank.seasons:
		var sd: SeasonData = s
		if sd == null or sd.id == "" or sd.display_name == "":
			errs.append("bad season entry")
			continue
		if seen.has(sd.id):
			errs.append("dup id " + sd.id)
		seen.append(sd.id)
		var seen_e: Array = []
		for e in sd.entries:
			var ed: Dictionary = e
			var hid: String = str(ed.get("hero", ""))
			var vix: int = int(ed.get("variant", -1))
			var key := hid + ":" + str(vix)
			if seen_e.has(key):
				errs.append(sd.id + " dup " + key)
			seen_e.append(key)
			var vs: HeroVariantSet = HeroVariantBank.load_bank().set_for(hid)
			if vs == null or vix < 0 or vix >= vs.palette.size():
				errs.append(sd.id + " bad entry " + key)
	var c := bank.current()
	if c == null:
		errs.append("current missing: " + bank.current_season)
	if c != null and c.entries.size() == 0:
		errs.append("current pack empty")
	return errs
