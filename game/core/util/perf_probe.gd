class_name PerfProbe
extends Node
## FPS / frame-time logger for device perf notes (Phase 1 gate + PERFORMANCE.md).
## Logs every 5 s of wall time: avg fps, worst frame. Headless-safe no-op.

var _frames := 0
var _time := 0.0
var _worst := 0.0
var _last := -1

func setup(_world: World) -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)

func _process(delta: float) -> void:
	if _last < 0:
		_last = Time.get_ticks_msec()
		return
	var dt := Time.get_ticks_msec() - _last
	_last = Time.get_ticks_msec()
	_frames += 1
	_time += dt
	_worst = maxf(_worst, dt)
	if _time >= 5000.0:
		var fps := 1000.0 * _frames / _time
		print("PERF %.0f fps (worst frame %.1f ms, %d frames over %.1f s)" % [fps, _worst, _frames, _time / 1000.0])
		_frames = 0
		_time = 0.0
		_worst = 0.0
