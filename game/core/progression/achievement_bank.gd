class_name AchievementBank
extends Resource
## D26: the achievement bank - one .tres under content/achievements/ holding
## every AchievementData (same data-driven pattern as the variant bank).
## Evaluation runs at match end, after PlayerProfile.apply_match updated the
## counters; the bank is cosmetic-only content (no match effect).

const BANK_PATH := "res://content/achievements/achievements.tres"

@export var achievements: Array = []

static func load_bank() -> AchievementBank:
	var r = load(ModLoader.resolve(BANK_PATH))
	if r is AchievementBank:
		return r
	var empty := AchievementBank.new()
	empty.achievements = []
	return empty

func data_of(id: String) -> AchievementData:
	for a in achievements:
		if a is AchievementData and str(a.id) == id:
			return a
	return null

## Human-readable reward line ("" for NONE) - cosmetic wording only.
static func reward_text(ad: AchievementData) -> String:
	if ad.reward == AchievementData.Reward.NONE:
		return ""
	var hero_name: String = ad.reward_hero.to_upper()
	for h in HeroRegistry.HEROES:
		if h is HeroData and str(h.id) == ad.reward_hero:
			hero_name = str(h.display_name).to_upper()
			break
	return "Unlocks %s variant %d (cosmetic)" % [hero_name, ad.reward_variant]

## Evaluate the profile (counters ALREADY updated by apply_match) against the
## whole bank. Marks newly met achievements on the profile (one-shot - they
## never re-unlock) and returns their display dicts.
static func newly_unlocked(profile: PlayerProfile) -> Array:
	var out: Array = []
	var bank := load_bank()
	for a in bank.achievements:
		var ad: AchievementData = a
		if ad == null or profile.achievements.has(ad.id):
			continue
		var met := false
		match ad.condition:
			AchievementData.Condition.KILLS:
				met = profile.total_kills >= ad.target
			AchievementData.Condition.WINS:
				met = profile.wins >= ad.target
			AchievementData.Condition.HEADSHOTS:
				met = profile.total_headshots >= ad.target
			AchievementData.Condition.MVP:
				met = profile.total_mvp >= ad.target
			AchievementData.Condition.MATCHES:
				met = profile.matches >= ad.target
			AchievementData.Condition.ACCOUNT_LEVEL:
				met = profile.level >= ad.target
			AchievementData.Condition.BEST_STREAK:
				met = profile.best_streak >= ad.target
			AchievementData.Condition.PLAYS_WITH_HERO:
				var h: Dictionary = profile.per_hero.get(ad.hero, {})
				met = int(h.get("plays", 0)) >= ad.target
		if not met:
			continue
		profile.achievements[ad.id] = true
		if ad.reward == AchievementData.Reward.VARIANT_UNLOCK:
			var list: Array = profile.ach_variant_unlocks.get(ad.reward_hero, [])
			if not list.has(ad.reward_variant):
				list.append(ad.reward_variant)
				profile.ach_variant_unlocks[ad.reward_hero] = list
		out.append({"id": ad.id, "name": ad.display_name, "desc": ad.desc,
			"reward": reward_text(ad)})
	return out

## Result-overlay text rows (pure, headless-testable).
static func view_rows(unlocked: Array) -> Array:
	var rows: Array = []
	for u in unlocked:
		var ud: Dictionary = u
		var row: String = "*NEW*  " + str(ud.get("name", ""))
		var rw: String = str(ud.get("reward", ""))
		if rw != "":
			row += "   (" + rw + ")"
		rows.append(row)
	return rows
