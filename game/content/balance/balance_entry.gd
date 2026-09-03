class_name BalanceEntry
extends Resource
## Per-hero balance tuning (Phase 3) — the DESIGN layer on top of the kit.
## Kits (content/heroes/) define a hero's identity (structure, ability
## shapes); balance entries define the numbers designers tune between
## passes. All multipliers 1.0 = untouched kit value (baseline sheet).
## Server-side only: applied once at spawn by HeroFactory.

@export var hero_id: String = ""
@export var hp_mult := 1.0
@export var damage_mult := 1.0
@export var fire_rate_mult := 1.0
@export var speed_mult := 1.0
## Scales every ult-charge gain (dealt/taken/heal/kill).
@export var ult_charge_mult := 1.0
@export var notes: String = ""
