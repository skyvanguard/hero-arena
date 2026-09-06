class_name CoachConfig
extends Resource
## D32 (AI coaching): data-driven thresholds + tip wording for the
## post-match coach. No magic numbers in the engine (core/coach/coach.gd)
## - every threshold and every sentence lives here. The tip templates use
## {placeholder} tokens replaced at render time.

## Headshot rate at/above this: no aim tip. Below hs_rate_warn with at
## least aim_min_kills kills: the aim tip fires.
@export var hs_rate_good := 0.25
@export var hs_rate_warn := 0.10
## Do not lecture a 0-2 kill game about headshots (noisy sample).
@export var aim_min_kills := 3
## kills/deaths below this (with at least 2 deaths): the survival tip.
@export var kd_warn := 0.75
## best_streak at/above this: the streak praise.
@export var streak_goal := 4
## Output budget: at most max_tips tips, of which at most max_warnings
## are warnings (the rest are positives).
@export var max_tips := 3
@export var max_warnings := 2

## Tip wording (content; {tokens} are substituted in Coach.tips).
@export var tip_aim := "Headshot rate is low ({hs}% of {kills} kills) - lead your shots, aim for the head."
@export var tip_survive := "You died {deaths} times for {kills} kills - survive longer and re-engage with cover."
@export var tip_mvp := "You were the top performer - excellent objective play."
@export var tip_streak := "{streak}-kill streak - elite consistency; try to chain more."
@export var tip_win := "Solid win - keep the momentum."
## Mode id -> objective note (behavior advice, never hero-specific).
@export var mode_lines: Dictionary = {}
