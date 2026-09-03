extends SceneTree
## Procedural SFX generator (Phase 2 asset pipeline).
## Synthesizes original 16-bit PCM mono WAVs into assets/audio/sfx/ -
## zero external assets (original IP, AGENTS.md). Run:
##   godot --headless --path game -s res://tools/gen_sfx.gd

const RATE := 22050
const DIR := "res://assets/audio/sfx"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260903  # deterministic: assets are reproducible originals
	_write("sfx_fire.wav", _fire(rng))
	_write("sfx_dash.wav", _dash(rng))
	_write("sfx_burst.wav", _burst(rng))
	_write("sfx_ult.wav", _ult(rng))
	_write("sfx_hit.wav", _hit(rng))
	_write("sfx_kill.wav", _kill(rng))
	_write("sfx_jump.wav", _jump(rng))
	_write("sfx_reload.wav", _reload(rng))
	_write("sfx_respawn.wav", _respawn(rng))
	print("SFX: wrote 9 files to ", DIR)
	quit(0)

func _write(name: String, samples: PackedFloat32Array) -> void:
	var n := samples.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	var peak := 0.0
	for i in n:
		peak = maxf(peak, absf(samples[i]))
	var scale := 0.72 / peak if peak > 0.0 else 1.0
	for i in n:
		var v := int(clampf(samples[i] * scale, -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	# Complete RIFF file in memory, single store.
	var out := PackedByteArray()
	out.resize(44 + data.size())
	var o := 0
	out[o] = 0x52; out[o+1] = 0x49; out[o+2] = 0x46; out[o+3] = 0x46
	o += 4
	o = _put_le32(out, o, 36 + data.size())
	out[o] = 0x57; out[o+1] = 0x41; out[o+2] = 0x56; out[o+3] = 0x45
	o += 4
	out[o] = 0x66; out[o+1] = 0x6D; out[o+2] = 0x74; out[o+3] = 0x20  # "fmt "
	o += 4
	o = _put_le32(out, o, 16)
	out[o] = 1; out[o+1] = 0     # PCM
	out[o+2] = 1; out[o+3] = 0   # mono
	o += 4
	o = _put_le32(out, o, RATE)
	o = _put_le32(out, o, RATE * 2)
	out[o] = 2; out[o+1] = 0     # block align
	out[o+2] = 16; out[o+3] = 0  # bits per sample
	o += 4
	out[o] = 0x64; out[o+1] = 0x61; out[o+2] = 0x74; out[o+3] = 0x61  # "data"
	o += 4
	o = _put_le32(out, o, data.size())
	assert(o + data.size() == out.size())
	for i in data.size():
		out[44 + i] = data[i]
	var f := FileAccess.open(ProjectSettings.globalize_path(DIR.path_join(name)), FileAccess.WRITE)
	f.store_buffer(out)
	f.close()

func _put_le32(buf: PackedByteArray, at: int, v: int) -> int:
	buf[at] = v & 0xFF
	buf[at + 1] = (v >> 8) & 0xFF
	buf[at + 2] = (v >> 16) & 0xFF
	buf[at + 3] = (v >> 24) & 0xFF
	return at + 4

func _env(t: float, a: float, d: float, dur: float) -> float:
	if t < a:
		return t / a
	if t > dur:
		return 0.0
	return maxf(0.0, 1.0 - (t - a) / maxf(d, 0.0001))

func _fire(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	var n := int(RATE * 0.08)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 55.0)
		var noise := rng.randf_range(-1.0, 1.0)
		var click := sin(TAU * 110.0 * t) * exp(-t * 120.0) * 0.6
		s.append((noise * 0.8 + click) * env)
	return s

func _dash(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	var n := int(RATE * 0.28)
	for i in n:
		var t := float(i) / RATE
		var p := t / 0.28
		var env := sin(p * PI)
		var noise := rng.randf_range(-1.0, 1.0)
		var mod := 0.4 + 0.6 * sin(TAU * (30.0 + 140.0 * p) * t)
		s.append(noise * mod * env * 0.8)
	return s

func _burst(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	var n := int(RATE * 0.16)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for k in 2:
			var dt := t - k * 0.05
			if dt >= 0.0:
				v += sin(TAU * (220.0 - 90.0 * k) * dt) * exp(-dt * 40.0) * 0.7
		v += rng.randf_range(-1.0, 1.0) * exp(-t * 30.0) * 0.3
		s.append(clampf(v, -1.0, 1.0))
	return s

func _ult(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	var n := int(RATE * 0.6)
	for i in n:
		var t := float(i) / RATE
		var sweep := sin(TAU * (140.0 + 700.0 * t) * t) * _env(t, 0.05, 0.25, 0.35) * 0.6
		var chord := 0.0
		if t > 0.28:
			var dt := t - 0.28
			chord = (sin(TAU * 523.25 * t) + sin(TAU * 659.25 * t) + sin(TAU * 783.99 * t)) * exp(-dt * 5.0) * 0.25
		s.append(sweep + chord + rng.randf_range(-1.0, 1.0) * 0.05)
	return s

func _hit(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	var n := int(RATE * 0.07)
	for i in n:
		var t := float(i) / RATE
		var v := sin(TAU * 130.0 * t) * exp(-t * 60.0) * 0.9
		v += rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.4
		s.append(v)
	return s

func _kill(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	var n := int(RATE * 0.3)
	for i in n:
		var t := float(i) / RATE
		var v := sin(TAU * (420.0 - 1100.0 * t) * t) * _env(t, 0.01, 0.25, 0.3) * 0.7
		v += sin(TAU * 90.0 * t) * exp(-t * 12.0) * 0.5
		s.append(v)
	return s

func _jump(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	var n := int(RATE * 0.12)
	for i in n:
		var t := float(i) / RATE
		var p := t / 0.12
		s.append(rng.randf_range(-1.0, 1.0) * sin(p * PI) * 0.35)
	return s

func _reload(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	var n := int(RATE * 0.3)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for k in [0.0, 0.16]:
			var dt: float = t - float(k)
			if dt >= 0.0 and dt < 0.03:
				v += rng.randf_range(-1.0, 1.0) * exp(-dt * 160.0) * 0.9
		s.append(v)
	return s

func _respawn(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	var n := int(RATE * 0.2)
	for i in n:
		var t := float(i) / RATE
		var p := t / 0.2
		s.append(sin(TAU * (300.0 + 1600.0 * p) * t) * sin(p * PI) * 0.5)
	return s
