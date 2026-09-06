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
	# D26/D29/D31: achievement + event + shop variant unlocks are cosmetic
	# early access - the effective cap is the max of the mastery gate and
	# every granted variant.
	for g in profile.grant_sources():
		var granted: Array = g.get(hero_id, [])
		for i in granted.size():
			unlocked = maxi(unlocked, int(granted[i]))
	var idx: int = profile.selected_variant(hero_id)
	return s.color_of(mini(idx, unlocked), fallback)

## D31: is this variant selectable for this profile? The mastery gate OR
## any cosmetic grant (achievements / events / shop) unlocks it. The
## hero-select variant dots and the shop both use this (before D31 the
## dots only saw the mastery gate, so D26/D29 grants looked locked even
## though color_for already honored them).
static func variant_unlocked(bank: HeroVariantBank, profile: PlayerProfile,
		prog: ProgressionConfig, hero_id: String, idx: int) -> bool:
	var s := bank.set_for(hero_id) if bank != null else null
	if s == null:
		return idx <= 0
	if profile == null or prog == null:
		return idx <= 0
	var need := 0
	if idx < s.unlock_levels.size():
		need = int(s.unlock_levels[idx])
	if profile.mastery_level_of(prog, hero_id) >= need:
		return true
	for g in profile.grant_sources():
		if (g.get(hero_id, []) as Array).has(idx):
			return true
	return false

static func _cfg() -> ProgressionConfig:
	var r = load("res://content/progression.tres")
	return r if r is ProgressionConfig else null
