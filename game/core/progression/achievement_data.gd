class_name AchievementData
extends Resource
## D26 (Phase 7, item 4): one achievement as DATA. Conditions are evaluated
## against PlayerProfile counters (updated from server-side match stats at
## match end); rewards are COSMETIC-ONLY (none, or an early cosmetic-variant
## unlock) - no pay-to-win, nothing here touches a match.

## KILLS / WINS / HEADSHOTS / MVP / MATCHES: cumulative profile counters.
## ACCOUNT_LEVEL: the global account level. BEST_STREAK: the profile's
## all-time best in-match kill streak. PLAYS_WITH_HERO: plays of `hero`
## (per_hero seed - the same stats that drive mastery).
enum Condition {
	KILLS,
	WINS,
	HEADSHOTS,
	MVP,
	MATCHES,
	ACCOUNT_LEVEL,
	BEST_STREAK,
	PLAYS_WITH_HERO,
}

enum Reward {
	NONE,
	VARIANT_UNLOCK,  ## cosmetic: makes (reward_hero, reward_variant) selectable now
}

@export var id := ""
@export var display_name := ""
@export var desc := ""
@export var condition: Condition = Condition.KILLS
@export var target := 1
@export var hero := ""  ## PLAYS_WITH_HERO only
@export var reward: Reward = Reward.NONE
@export var reward_hero := ""
@export var reward_variant := 0
