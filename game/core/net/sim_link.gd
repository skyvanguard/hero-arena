class_name SimLink
extends RefCounted
## Net-sim transport (Phase 5): a stand-in for the ENet peer with
## configurable one-way latency + per-packet loss. Wired into MatchServer /
## MatchClient as sim_out (this endpoint's send path) and polled as sim_in
## (inbound): send() queues packets with a delivery timestamp, poll() (called
## by the owning endpoint every tick) delivers due packets to on_packet.
## The net-sim harness (tests/test_net_sim) drives matches through these to
## validate behavior under 50/150/300 ms RTT + 2/10% loss, and drop_all()
## simulates a connection drop (the reconnect path).
var latency_ms := 0.0
var loss := 0.0
var on_packet: Callable
var sent := 0
var dropped := 0
var delivered := 0
var _q: Array = []  # [at_ms: int, to_id: int, buf: PackedByteArray]

func send(to_id: int, buf: PackedByteArray, _mode: int, _ch: int) -> void:
	sent += 1
	if loss > 0.0 and randf() < loss:
		dropped += 1
		return
	_q.append([Time.get_ticks_msec() + int(latency_ms), to_id, buf])

func poll() -> void:
	var now := Time.get_ticks_msec()
	while _q.size() > 0 and int(_q[0][0]) <= now:
		var e: Array = _q.pop_front()
		delivered += 1
		if on_packet.is_valid():
			on_packet.call(e[1], e[2])

## Connection drop: in-flight packets are lost (reliable semantics are
## simulated by the re-hello/reconnect flow, not by retransmission).
func drop_all() -> void:
	_q.clear()
