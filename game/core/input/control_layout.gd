class_name ControlLayout
extends Resource
## D24: the BASELINE touch layout - content data, not code (no magic
## numbers, ARCHITECTURE.md §3.9). Button positions are viewport FRACTIONS
## (0..1, center points); the current layout is defined in
## content/settings/control_layout.tres. User customization (scale,
## opacity, side, sensitivity) multiplies this baseline - see
## ControlSettings.
const PATH := "res://content/settings/control_layout.tres"

@export var aim_sens := 0.0032      ## touch aim drag: rad/px baseline
@export var joy_radius := 90.0      ## virtual joystick radius (design px)
@export var aim_zone_split := 0.45  ## left fraction of screen = move zone

## Action cluster baselines (centers in viewport fractions).
@export var fire_pos := Vector2(0.8828125, 0.8194444)
@export var fire_radius := 64.0
@export var fire_color := Color(0.9, 0.35, 0.3, 0.55)
@export var jump_pos := Vector2(0.8828125, 0.6666667)
@export var jump_radius := 46.0
@export var jump_color := Color(0.4, 0.8, 1.0, 0.45)
@export var reload_pos := Vector2(0.953125, 0.6666667)
@export var reload_radius := 46.0
@export var reload_color := Color(1.0, 0.8, 0.3, 0.45)
@export var ab1_pos := Vector2(0.8125, 0.5416667)
@export var ab1_radius := 30.0
@export var ab1_color := Color(0.6, 0.5, 1.0, 0.5)
@export var ab2_pos := Vector2(0.875, 0.5416667)
@export var ab2_radius := 30.0
@export var ab2_color := Color(0.6, 0.5, 1.0, 0.5)
@export var ult_pos := Vector2(0.9375, 0.5416667)
@export var ult_radius := 34.0
@export var ult_color := Color(1.0, 0.6, 0.9, 0.55)

## All button definitions, in build order. Untyped dicts on purpose
## (same pattern as HeroVariantBank - typed nested resources in .tres are
## fragile in 4.7).
func button_defs() -> Array:
	return [
		{id = "FIRE", pos = fire_pos, radius = fire_radius, color = fire_color},
		{id = "JUMP", pos = jump_pos, radius = jump_radius, color = jump_color},
		{id = "RELOAD", pos = reload_pos, radius = reload_radius, color = reload_color},
		{id = "AB1", pos = ab1_pos, radius = ab1_radius, color = ab1_color},
		{id = "AB2", pos = ab2_pos, radius = ab2_radius, color = ab2_color},
		{id = "ULT", pos = ult_pos, radius = ult_radius, color = ult_color},
	]

static func load_layout() -> ControlLayout:
	var r := load(PATH)
	if r is ControlLayout:
		return r
	var fb := ControlLayout.new()
	fb.name = "ControlLayoutFallback"
	return fb
