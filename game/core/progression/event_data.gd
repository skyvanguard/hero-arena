class_name EventData
extends Resource
## D29 (events framework): one limited-time event.
##
## Events are the directive's participation/win/objective reward track
## (Phase 7 item 9): a goal kind over match outcomes, an optional mode
## filter (objective modes), and a COSMETIC-ONLY reward (a variant
## unlock for a hero, or none). The no-hero-forcing rule: an event never
## requires or rewards playing a specific HERO (the reward hero is the
## one whose cosmetic variant is granted, not a play requirement).

## What the goal counts: matches played (participation), wins, or MVPs
## (objective performance - the top-impact player on the objective modes).
enum GoalKind { MATCHES, WINS, MVP }

@export var id := ""
@export var display_name := ""
@export var desc := ""
## Inactive events are kept in the bank (content history) but never
## progress or complete.
@export var active := true
@export var goal_kind: int = GoalKind.MATCHES
@export var goal_target := 10
## Mode filter: empty = count matches in every mode; otherwise only
## matches of these modes count (ModeRegistry ids).
@export var modes: Array = []
## Cosmetic reward: the variant index granted for this hero ("" = none).
@export var reward_hero := ""
@export var reward_variant := 0
