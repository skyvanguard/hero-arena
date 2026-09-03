class_name PerfProbe
extends RefCounted
## FPS / frame-time logger for device perf notes (Phase 1 gate + PERFORMANCE.md).
## Logs every 5 s of wall time: avg fps, worst frame, sim ms.

static var _frames := 0
static var _time := 0.0
static var _worst := 0.0
static var _last := 0.0
static var _enabled := false

static func setup(node: Node, _world: World) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_enabled = true
	_last = Time.get_ticks_msec()
	node.process_frame.connect(_on_frame)

static func _on_frame() -> void:
	if not _enabled:
		return
	var now := Time.get_ticks_msec()
	var dt := now - _last
	_last = now
	_frames += 1
	_time += dt
	_worst = maxf(_worst, dt)
	if _time >= 5000.0:
		var fps := 1000.0 * _frames / _time
		print("PERF %.0f fps (worst frame %.1f ms, %d frames over %.1f s)" % [fps, _worst, _frames, _time / 1000.0])
		_frames = 0
		_time = 0.0
		_worst = 0.0
