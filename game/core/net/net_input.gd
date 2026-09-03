class_name NetInput
extends RefCounted
## Latest input frame for one remote player + unconsumed edges. The server
## applies edges exactly once (consume_edges) at the next sim tick.
var seq := 0
var move := Vector2.ZERO
var yaw := 0.0
var pitch := -0.18
var fire := false
var edges := 0

func apply(d: Dictionary) -> void:
	seq = int(d.seq)
	move = d.move
	yaw = float(d.yaw)
	pitch = float(d.pitch)
	fire = bool(d.fire)
	edges |= int(d.edges)

func consume_edges() -> int:
	var e := edges
	edges = 0
	return e
