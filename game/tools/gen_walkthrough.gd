extends Node
## D37 architecture walkthrough generator (docs/walkthrough.gif).
##
## Runs a REAL 3v3 bot match in-process (the same authoritative World the
## dedicated server drives) and renders a top-down, data-driven
## visualization from the sim state — no rendering server involved, so it
## runs headless in CI. Frames are PNGs; ffmpeg assembles the GIF
## (two-pass palette for quality). The overlays show the architecture
## loop this project is built on: 60 Hz authoritative server sim ->
## 20 Hz snapshots -> interpolated client views.
##
## Note: Godot 4.7's Image has no draw_* helpers (only fill/fill_rect/
## set_pixel), so the primitives below (Bresenham line, circle fill/
## outline) are implemented directly.
##
## Run:
##   godot --headless --path . res://tools/gen_walkthrough.tscn
##   ffmpeg -framerate 10 -i /tmp/walk53/frame_%04d.png -vf palettegen /tmp/walk53/pal.png
##   ffmpeg -framerate 10 -i /tmp/walk53/frame_%04d.png -i /tmp/walk53/pal.png \
##       -lavfi paletteuse docs/walkthrough.gif
const FIXED_DT := 1.0 / 60.0
const W := 480
const H := 270
const TITLE_FRAMES := 20     # 2.0 s title card @ 10 fps
const MATCH_FRAMES := 240    # 24.0 s of match
const TOTAL_FRAMES := TITLE_FRAMES + MATCH_FRAMES
const OUT_DIR := "/tmp/walk53"
const BG := Color(0.063, 0.075, 0.1)
const BAR := Color(0.1, 0.12, 0.16)
const TEAM_C := [Color(0.35, 0.6, 1.0), Color(1.0, 0.4, 0.35)]
const WALL_FILL := Color(0.16, 0.19, 0.25)
const WALL_LINE := Color(0.35, 0.4, 0.5)
const BOUNDS_LINE := Color(0.5, 0.55, 0.65)
const TEXT_C := Color(0.9, 0.92, 0.95)
const TEXT_DIM := Color(0.7, 0.75, 0.85)
const GOOD := Color(0.5, 0.8, 0.6)

var world: World
var server: MatchServer
var arena: Node = null
var _bmin := Vector3.ZERO
var _bmax := Vector3.ZERO
var _walls: Array = []   # Rect2 (projected)
var _frame_n := 0
var _kills: Array = []   # {pos: Vector2, t: float}
var _feed: Array = []    # {text: String, t: float}

## Original 5x7 bitmap font (A-Z, 0-9, punctuation) — no engine dependency,
## deterministic, headless-safe. Each glyph: 7 rows of 5 columns.
static var _FONT := {
	"A": ["01110","10001","10001","11111","10001","10001","10001"],
	"B": ["11110","10001","10001","11110","10001","10001","11110"],
	"C": ["01110","10001","10000","10000","10000","10001","01110"],
	"D": ["11100","10010","10001","10001","10001","10010","11100"],
	"E": ["11111","10000","10000","11110","10000","10000","11111"],
	"F": ["11111","10000","10000","11110","10000","10000","10000"],
	"G": ["01110","10001","10000","10111","10001","10001","01110"],
	"H": ["10001","10001","10001","11111","10001","10001","10001"],
	"I": ["01110","00100","00100","00100","00100","00100","01110"],
	"J": ["00111","00010","00010","00010","00010","10010","01100"],
	"K": ["10001","10010","10100","11000","10100","10010","10001"],
	"L": ["10000","10000","10000","10000","10000","10000","11111"],
	"M": ["10001","11011","10101","10101","10001","10001","10001"],
	"N": ["10001","11001","10101","10011","10001","10001","10001"],
	"O": ["01110","10001","10001","10001","10001","10001","01110"],
	"P": ["11110","10001","10001","11110","10000","10000","10000"],
	"Q": ["01110","10001","10001","10001","10101","10010","01101"],
	"R": ["11110","10001","10001","11110","10100","10010","10001"],
	"S": ["01111","10000","10000","01110","00001","00001","11110"],
	"T": ["11111","00100","00100","00100","00100","00100","00100"],
	"U": ["10001","10001","10001","10001","10001","10001","01110"],
	"V": ["10001","10001","10001","10001","10001","01010","00100"],
	"W": ["10001","10001","10001","10101","10101","11011","10001"],
	"X": ["10001","10001","01010","00100","01010","10001","10001"],
	"Y": ["10001","10001","01010","00100","00100","00100","00100"],
	"Z": ["11111","00001","00010","00100","01000","10000","11111"],
	"0": ["01110","10001","10011","10101","11001","10001","01110"],
	"1": ["00100","01100","00100","00100","00100","00100","01110"],
	"2": ["01110","10001","00001","00010","00100","01000","11111"],
	"3": ["01110","10001","00001","00110","00001","10001","01110"],
	"4": ["00010","00110","01010","10010","11111","00010","00010"],
	"5": ["11111","10000","11110","00001","00001","10001","01110"],
	"6": ["00110","01000","10000","11110","10001","10001","01110"],
	"7": ["11111","00001","00010","00100","01000","01000","01000"],
	"8": ["01110","10001","10001","01110","10001","10001","01110"],
	"9": ["01110","10001","10001","01111","00001","00010","01100"],
	" ": ["00000","00000","00000","00000","00000","00000","00000"],
	":": ["00000","00100","00000","00000","00100","00000","00000"],
	"-": ["00000","00000","00000","01110","00000","00000","00000"],
	"?": ["01110","10001","00001","00110","00100","00000","00100"],
	".": ["00000","00000","00000","00000","00000","00100","00100"],
	">": ["10000","01000","00100","00010","00100","01000","10000"],
	"|": ["00100","00100","00100","00100","00100","00100","00100"],
}

func _draw_text(img: Image, x: int, y: int, text: String, color: Color,
		scale: int = 1) -> void:
	var cx := x
	for ch in text.to_upper():
		var g: Array = _FONT.get(ch, _FONT["?"])
		for ry in 7:
			var row: String = str(g[ry])
			for rx in 5:
				if row[rx] == "1":
					for sy in scale:
						for sx in scale:
							var px := cx + rx * scale + sx
							var py := y + ry * scale + sy
							if px >= 0 and py >= 0 and px < W and py < H:
								img.set_pixel(px, py, color)
			cx += 6 * scale

func _text_w(text: String, scale: int) -> int:
	return text.length() * 6 * scale

func _line(img: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var x := x0
	var y := y0
	while true:
		if x >= 0 and y >= 0 and x < W and y < H:
			img.set_pixel(x, y, color)
		if x == x1 and y == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy

func _rect_outline(img: Image, rc: Rect2, color: Color) -> void:
	var x0 := int(rc.position.x)
	var y0 := int(rc.position.y)
	var x1 := x0 + int(rc.size.x)
	var y1 := y0 + int(rc.size.y)
	_line(img, x0, y0, x1, y0, color)
	_line(img, x1, y0, x1, y1, color)
	_line(img, x1, y1, x0, y1, color)
	_line(img, x0, y1, x0, y0, color)

func _fill_circle(img: Image, cx: int, cy: int, r: int, color: Color) -> void:
	for dy in range(-r, r + 1):
		var w := int(sqrt(float(r * r - dy * dy)))
		if w > 0:
			img.fill_rect(Rect2i(cx - w, cy + dy, w * 2 + 1, 1), color)

func _circle_outline(img: Image, cx: int, cy: int, r: int, color: Color) -> void:
	for i in 48:
		var a1 := TAU * float(i) / 48.0
		var a2 := TAU * float(i + 1) / 48.0
		_line(img,
				int(cx + cos(a1) * r), int(cy + sin(a1) * r),
				int(cx + cos(a2) * r), int(cy + sin(a2) * r), color)

func _wx(v: float) -> float:
	var span := _bmax.x - _bmin.x
	if span < 0.01:
		return W / 2.0
	return 12.0 + (v - _bmin.x) / span * 456.0

func _wz(v: float) -> float:
	var span := _bmax.z - _bmin.z
	if span < 0.01:
		return 140.0
	return 26.0 + (v - _bmin.z) / span * 220.0

func _render(frame: int) -> void:
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	img.fill(BG)
	if frame < TITLE_FRAMES:
		_render_title(img, frame)
	else:
		_render_match(img, frame)
	img.save_png("%s/frame_%04d.png" % [OUT_DIR, frame])

func _render_title(img: Image, frame: int) -> void:
	_draw_text(img, (W - _text_w("HERO ARENA", 4)) / 2, 60, "HERO ARENA", TEXT_C, 4)
	_draw_text(img, (W - _text_w("ARCHITECTURE WALKTHROUGH", 2)) / 2, 116,
			"ARCHITECTURE WALKTHROUGH", TEXT_DIM, 2)
	_draw_text(img, (W - _text_w("3V3 BOT MATCH - CROSSDOCKS", 1)) / 2, 144,
			"3V3 BOT MATCH - CROSSDOCKS", TEXT_DIM)
	_draw_text(img, (W - _text_w("GENERATED FROM THE AUTHORITATIVE SIM", 1)) / 2, 158,
			"GENERATED FROM THE AUTHORITATIVE SIM", TEXT_DIM)
	_draw_text(img, (W - _text_w("60HZ SERVER SIM > 20HZ SNAPSHOTS > VIEWS", 1)) / 2,
			172, "60HZ SERVER SIM > 20HZ SNAPSHOTS > VIEWS", GOOD)
	var p := (frame % 10) / 10.0
	var bar_w := int(200.0 * p)
	if bar_w > 0:
		img.fill_rect(Rect2i((W - 200) / 2, 200, bar_w, 3), GOOD)

func _render_match(img: Image, frame: int) -> void:
	for r in _walls:
		var rc: Rect2 = r
		img.fill_rect(Rect2i(int(rc.position.x), int(rc.position.y),
				int(rc.size.x), int(rc.size.y)), WALL_FILL)
		_rect_outline(img, rc, WALL_LINE)
	_rect_outline(img, Rect2(Vector2(12.0, 26.0), Vector2(456.0, 220.0)), BOUNDS_LINE)
	for team in 2:
		var pts: Array = world.spawn_points.get(team, [])
		var sc: Color = TEAM_C[team]
		for p in pts:
			var pv: Vector3 = p
			img.fill_rect(Rect2i(int(_wx(pv.x)) - 3, int(_wz(pv.z)) - 3, 7, 7), sc)
	for k in _kills:
		var age := world.time - float(k.t)
		if age < 0.5:
			var rad := 4.0 + age * 20.0
			var fade: int = int(255.0 * (1.0 - age * 2.0))
			_circle_outline(img, int(k.pos.x), int(k.pos.y), int(rad),
					Color(fade / 255.0, fade / 255.0, 1.0))
	for ch in world.characters:
		if ch == null or not ch.alive:
			continue
		var cx := int(_wx(ch.position.x))
		var cy := int(_wz(ch.position.z))
		var team: int = ch.team
		var mhp := 100.0
		var mv = ch.get("max_hp")
		if mv is float:
			mhp = mv
		var frac: float = clampf(ch.hp / mhp, 0.2, 1.0)
		var rad := int(3.0 + 3.0 * frac)
		_fill_circle(img, cx, cy, rad, TEAM_C[team])
		_circle_outline(img, cx, cy, rad, Color(1, 1, 1))
		var nm: String = str(ch.display_name)
		var nm_c: Color = TEAM_C[team].lerp(Color(1, 1, 1), 0.25)
		_draw_text(img, cx - _text_w(nm, 1) / 2, cy - rad - 10, nm, nm_c)
	img.fill_rect(Rect2i(0, 0, W, 20), BAR)
	var s0: int = int(world.score.get(0, 0))
	var s1: int = int(world.score.get(1, 1))
	var mode_s := "TDM"
	if world.mode != null:
		mode_s = str(world.mode.mode_id)
	_draw_text(img, 8, 6, "HERO ARENA - " + mode_s, TEXT_C, 2)
	var sc := "%d : %d" % [s0, s1]
	_draw_text(img, (W - _text_w(sc, 2)) / 2, 6, sc, Color(1, 1, 1), 2)
	var tt := "T+%dS" % int(world.time)
	_draw_text(img, W - _text_w(tt, 2) - 8, 6, tt, TEXT_DIM, 2)
	var fy := 28
	for f in _feed:
		if world.time - float(f.t) > 5.0:
			continue
		var ft: String = str(f.text)
		_draw_text(img, W - _text_w(ft, 1) - 6, fy, ft, Color(0.85, 0.87, 0.9))
		fy += 8
	img.fill_rect(Rect2i(0, H - 14, W, 14), BAR)
	var cap := "AUTHORITATIVE 60HZ SERVER > 20HZ SNAPSHOTS > CLIENT VIEWS"
	_draw_text(img, (W - _text_w(cap, 1)) / 2, H - 11, cap, GOOD)

func _on_world_event(name: String, data: Dictionary) -> void:
	if name == "kill":
		var victim = data.get("victim_ch")
		if victim != null:
			_kills.append({pos = Vector2(_wx(victim.position.x),
				_wz(victim.position.z)), t = world.time})
		if _kills.size() > 24:
			_kills = _kills.slice(_kills.size() - 24)
		var line := str(data.get("killer", "?")) + " > " + str(data.get("victim", "?"))
		var hs := " (HEADSHOT)" if bool(data.get("headshot", false)) else ""
		_feed.append({text = line + hs, t = world.time})
		if _feed.size() > 3:
			_feed = _feed.slice(_feed.size() - 3)

func _physics_process(_delta: float) -> void:
	world.step(FIXED_DT)
	if server != null:
		server.tick(FIXED_DT)
	_frame_n += 1
	if _frame_n % 6 == 1:
		var frame := (_frame_n - 1) / 6
		if frame < TOTAL_FRAMES:
			_render(frame)
		if frame == TOTAL_FRAMES - 1:
			var s0: int = int(world.score.get(0, 0))
			var s1: int = int(world.score.get(1, 1))
			print("WALKTHROUGH frames: %d -> %s  (score %d:%d, %.1f s sim)"
					% [TOTAL_FRAMES, OUT_DIR, s0, s1, world.time])
			get_tree().quit(0)

func _ready() -> void:
	seed(777)
	var dd := DirAccess.open("res://")
	if dd != null:
		dd.make_dir_recursive_absolute(OUT_DIR)
	world = World.new()
	world.name = "World"
	world.target_score = 999  # the capture never ends mid-GIF
	world.match_duration = 900.0
	world.mode = ModeRegistry.get_mode("tdm")
	if world.mode != null:
		world.mode.setup(world)
	world.world_event.connect(_on_world_event)
	add_child(world)
	arena = Arena.build(world)
	add_child(arena)
	_server_bounds()
	server = MatchServer.new()
	add_child(server)
	server.setup(world, 7990, 3)  # ENet idle; the sim is the point
	var roster: Array = HeroRegistry.heroes().duplicate()
	roster.shuffle()
	var rix := 0
	for team in 2:
		var pts: Array = world.spawn_points.get(team, [])
		for i in 3:
			if pts.size() <= i:
				break
			var data: HeroData = roster[rix % roster.size()]
			rix += 1
			var ch := server.spawn_bot(team, data, pts[i])
			ch.display_name = data.display_name
	await get_tree().physics_frame

func _collect_shapes(n: Node, out: Array) -> void:
	if n is CollisionShape3D:
		out.append(n)
	elif n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_shapes(c, out)

func _server_bounds() -> void:
	var items: Array = []
	_collect_shapes(arena, items)
	var boxes: Array = []
	for it in items:
		var a: AABB
		var xf: Transform3D
		if it is CollisionShape3D:
			var cs: CollisionShape3D = it
			if cs.shape == null:
				continue
			# BoxShape3D has no get_aabb() in 4.7 - build it from the extents;
			# shapes without a get_aabb() are skipped (meshes carry the rest).
			if cs.shape is BoxShape3D:
				var bs: BoxShape3D = cs.shape
				a = AABB(Vector3(-bs.size / 2), bs.size)
			elif cs.shape.has_method("get_aabb"):
				a = cs.shape.get_aabb()
			else:
				continue
			xf = cs.global_transform
		else:
			var mi: MeshInstance3D = it
			a = mi.get_aabb()
			xf = mi.global_transform
		if a.size == Vector3.ZERO:
			continue
		var gmn: Vector3 = xf * a.position
		var gmx: Vector3 = gmn
		for i in 8:
			var c: Vector3 = xf * Vector3(
					a.position.x + a.size.x if i & 1 else a.position.x,
					a.position.y + a.size.y if i & 2 else a.position.y,
					a.position.z + a.size.z if i & 4 else a.position.z)
			gmn = Vector3(minf(gmn.x, c.x), minf(gmn.y, c.y), minf(gmn.z, c.z))
			gmx = Vector3(maxf(gmx.x, c.x), maxf(gmx.y, c.y), maxf(gmx.z, c.z))
		boxes.append([gmn, gmx])
	if boxes.is_empty():
		print("WALKTHROUGH: no arena shapes found - using default bounds")
		_bmin = Vector3(-26.0, 0.0, -26.0)
		_bmax = Vector3(26.0, 8.0, 26.0)
		return
	var g0: Vector3 = boxes[0][0]
	var g1: Vector3 = boxes[0][1]
	for b in boxes:
		var mn: Vector3 = b[0]
		var mx: Vector3 = b[1]
		g0 = Vector3(minf(g0.x, mn.x), minf(g0.y, mn.y), minf(g0.z, mn.z))
		g1 = Vector3(maxf(g1.x, mx.x), maxf(g1.y, mx.y), maxf(g1.z, mx.z))
	_bmin = g0
	_bmax = g1
	for b in boxes:
		var mn: Vector3 = b[0]
		var mx: Vector3 = b[1]
		_walls.append(Rect2(Vector2(_wx(mn.x), _wz(mn.z)),
				Vector2(_wx(mx.x) - _wx(mn.x), _wz(mx.z) - _wz(mn.z))))
