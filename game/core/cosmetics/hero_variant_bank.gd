class_name HeroVariantBank
extends Resource
## D22: the cosmetic variant bank - one HeroVariantSet per hero, loaded
## from content/cosmetics/hero_variants.tres (data-driven, same pattern as
## ModeRegistry/MapRegistry). Static helpers keep call sites tidy.
const BANK_PATH := "res://content/cosmetics/hero_variants.tres"

@export var sets: Array = []

static func load_bank() -> HeroVariantBank:
	var r = load(BANK_PATH)
	if r is HeroVariantBank:
		return r
	var empty := HeroVariantBank.new()
	empty.sets = []
	return empty

func set_for(hero_id: String) -> HeroVariantSet:
	for s in sets:
		if s is HeroVariantSet and str(s.hero_id) == hero_id:
			return s
	return null

static func color_for(bank: HeroVariantBank, profile: PlayerProfile,
		hero_id: String, fallback: Color) -> Color:
	var s := bank.set_for(hero_id) if bank != null else null
	if s == null or profile == null:
		return fallback
	var prog: ProgressionConfig = _cfg()
	if prog == null:
		return s.color_of(0, fallback)
	var unlocked := s.unlocked_count(profile.mastery_level_of(prog, hero_id)) - 1
	var idx: int = profile.selected_variant(hero_id)
	return s.color_of(mini(idx, unlocked), fallback)

static func _cfg() -> ProgressionConfig:
	var r = load("res://content/progression.tres")
	return r if r is ProgressionConfig else null
