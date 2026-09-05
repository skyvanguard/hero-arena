class_name ControlSettings
extends RefCounted
## D24: the USER'S control customization - persisted overrides on top of
## the ControlLayout baseline (player profile JSON, no wire, no P2W -
## cosmetic/input ergonomics only).
##
## Resolution: ControlSettings.effective(layout, settings, vp) is a PURE
## function returning the final layout (button centers in pixels, radii,
## colors with alpha, joystick radius, aim sensitivity). The touch layer
## builds from it; the desktop mouse aim reads the sensitivity multiplier.
const AIM_SENS_MIN := 0.25
const AIM_SENS_MAX := 3.0
const SCALE_MIN := 0.75
const SCALE_MAX := 1.5
const OPACITY_MIN := 0.3
const OPACITY_MAX := 1.0
const FIRE_SIDE_LEFT := 0
const FIRE_SIDE_RIGHT := 1
const STEP := 0.25  # settings-panel stepper granularity

## Desktop (mouse) path: main sets this from the profile at match start so
## gameplay/hero.gd can stay free of UI types (static data, headless-safe).
static var aim_sens_active := 1.0

var aim_sens := 1.0       ## multiplier on the baseline touch sensitivity
var button_scale := 1.0   ## multiplier on every button radius
var button_opacity := 1.0 ## multiplier on every button color alpha
var joystick_scale := 1.0 ## multiplier on the joystick radius
var fire_side := FIRE_SIDE_RIGHT  ## 0 = cluster mirrored to the left half

func clamp_all() -> void:
	aim_sens = clampf(aim_sens, AIM_SENS_MIN, AIM_SENS_MAX)
	button_scale = clampf(button_scale, SCALE_MIN, SCALE_MAX)
	button_opacity = clampf(button_opacity, OPACITY_MIN, OPACITY_MAX)
	joystick_scale = clampf(joystick_scale, SCALE_MIN, SCALE_MAX)
	fire_side = clampi(fire_side, FIRE_SIDE_LEFT, FIRE_SIDE_RIGHT)

## Keyed access for the settings panel (only the numeric settings are
## steppable; fire_side is a toggle and has its own path).
func value_of(key: String) -> float:
	match key:
		"aim_sens":
			return aim_sens
		"button_scale":
			return button_scale
		"button_opacity":
			return button_opacity
		"joystick_scale":
			return joystick_scale
	return 1.0

func value_set(key: String, v: float) -> void:
	match key:
		"aim_sens":
			aim_sens = v
		"button_scale":
			button_scale = v
		"button_opacity":
			button_opacity = v
		"joystick_scale":
			joystick_scale = v

func to_dict() -> Dictionary:
	return {
		aim_sens = aim_sens, button_scale = button_scale,
		button_opacity = button_opacity, joystick_scale = joystick_scale,
		fire_side = fire_side,
	}

static func from_dict(d: Dictionary) -> ControlSettings:
	var s := ControlSettings.new()
	if d != null and not d.is_empty():
		s.aim_sens = float(d.get("aim_sens", 1.0))
		s.button_scale = float(d.get("button_scale", 1.0))
		s.button_opacity = float(d.get("button_opacity", 1.0))
		s.joystick_scale = float(d.get("joystick_scale", 1.0))
		s.fire_side = int(d.get("fire_side", FIRE_SIDE_RIGHT))
	s.clamp_all()
	return s

## Pure resolution: baseline x user settings x viewport -> final layout.
## fire_side LEFT mirrors every button center across the vertical axis
## (the action cluster crosses to the other half; the floating joystick
## still appears where the finger lands, and the right-side aim drag zone
## is unchanged - it is the universal aim surface).
static func effective(layout: ControlLayout, s: ControlSettings,
		vp: Vector2) -> Dictionary:
	s.clamp_all()
	var buttons := []
	for def in layout.button_defs():
		var center: Vector2 = (def.pos as Vector2) * vp
		if int(s.fire_side) == FIRE_SIDE_LEFT:
			center.x = vp.x - center.x
		var col: Color = def.color
		col.a = clampf(col.a * s.button_opacity, 0.0, 1.0)
		buttons.append({
			id = str(def.id),
			center = center,
			radius = float(def.radius) * s.button_scale,
			color = col,
		})
	return {
		buttons = buttons,
		joy_radius = layout.joy_radius * s.joystick_scale,
		aim_sens = layout.aim_sens * s.aim_sens,
		aim_zone_split = layout.aim_zone_split,
	}
