# NETWORKING.md — Architecture & Protocol (Phase 5, as-built v1)

Status: **v1 shipped (round 9)** — dedicated headless server + LAN direct connect +
loopback test suite. Prediction/reconnect/discovery/lag-comp are explicit v1
*non-goals* (below) and land in later Phase 5 rounds.

## 1. Transport (as-built)

- **Godot 4.7 high-level multiplayer over ENet** (`ENetMultiplayerPeer`), one
  dedicated headless server per match, clients connect over the LAN by
  `host:port` (UI field in hero-select; `MatchConfig.net_port` = 7777 default).
- **Godot 4.7 API note (probed empirically):** the multiplayer API class is
  `SceneMultiplayer` (parent `MultiplayerAPI`) — **RefCounted, not a Node**.
  It must be (a) held as a property, (b) given `set_root_path(<node path>)`
  before use, and (c) **polled manually** (`while mp.poll() == OK: pass`) from
  the owner's process/tick. Raw bytes: `mp.send_bytes(bytes, id, mode, channel)`
  (note argument order: bytes first, then remote id) and the
  `peer_packet(id, bytes)` signal; `peer_connected` carries the id,
  `connected_to_server`/`server_disconnected`/connection_failed don't.
- Channels: `CH_RELIABLE = 0` (ENet reliable), `CH_UNRELIABLE = 1`.
  ENet opens 8 channels; we use 2.
- Server scene: `net/server.tscn` (`net/server_main.gd`) — headless, no UI,
  `--port=N` user arg. Pre-fills both teams with bots to
  `MatchConfig.team_size`; a human join **yields the last bot's spot** on the
  smaller team (team pick = fewer *humans*, so 1v1 fill still works).
- Client: `core/net/match_client.gd` — embedded in the game process
  (hero-select JOIN row). Builds a local un-stepped `World` + `Arena.build`
  for visuals only; all sim state comes from snapshots.
- **Client views are physics-invisible** (all nested physics bodies zeroed).
  In-process/loopback the server and client worlds share one physics space;
  a view body coincident with a server character pushes it and blocks LOS and
  weapon rays (verified: bots scanning for minutes "saw" nothing because a
  view head-sensor sat on the enemy's head).

## 2. Wire protocol (v1)

All integers little-endian; strings `u16 len + utf8`; floats IEEE-754 f32
(manual bit codec — 4.7 dropped `PackedFloat32Array.pack_bytes()`).
Dispatch is by first magic byte, channel-independent:

| Magic | Name | Dir | Channel | Payload |
|---|---|---|---|---|
| `0x48` | M_HELLO | C→S | reliable | team_size u8, hero_id str |
| `0x53` | M_SLOT | S→C | reliable | result i8 (-1 reject), ch_id u8, team u8, team_size u8, time f32, target_score u8, match_duration f32 |
| `0x49` | M_INPUT | C→S | unreliable | seq u16, move (f32,f32), yaw f32, pitch f32, fire u8, edges u8 |
| `0x50` | M_SNAPSHOT | S→C | unreliable | seq u16, time f32, score0/1 u16, winner i8, chars[], projs[] |
| `0x45` | M_EVENT | S→C | reliable | type u8 + payload |

- **Snapshot**: all characters (id u8, team u8, alive u8, hero_idx u8,
  pos (f32×3), rot_y f32, hp/max_hp f32) up to `MAX_CHARS = 6` per side…
  (constant: up to `team_size` per side, 6 v1) + up to `MAX_PROJS = 8`
  projectiles (owner u8, pos f32×3, dir f32×3).
- **Events** (reliable, for UI/feel): E_HIT=0, E_KILL=1 (names + teams +
  headshot), E_RESPAWN=2, E_MATCH_OVER=3, E_HEAL=4.
- **Aim convention**: client sends **absolute** camera yaw/pitch; server
  direction = `(cos(pitch)·sin(yaw), sin(pitch), cos(pitch)·cos(yaw))`
  (hero rig rotated PI on Y: yaw=pitch=0 → local +Z = project forward).
  Input edges (bitfield): 1 jump, 2 reload, 4 ability1, 8 ability2, 16 ult —
  OR-accumulated per input, consumed server-side.
- **Rates**: snapshots 20 Hz (`SNAPSHOT_HZ`), input sampled 20 Hz
  (`INPUT_HZ`) on the client. Server steps at 60 Hz fixed.

## 3. Authority model (v1)

- Server owns: positions, HP/damage, ammo, cooldowns, score, deaths/respawns,
  match end. The client never sends state, only input (declared action fields).
- Remote humans are **server-side `Hero` + `NetPlayerController`** — the same
  controller interface as bots (D3 parity): fed from per-peer `NetInput`.
  Bots and humans are indistinguishable to the sim.
- Disconnect: the slot **freezes** (controller removed; body stays). v1 has no
  reconnect — a later Phase 5 round adds session tokens + resync.
- Kill feed / match-over on the client come from the reliable event channel,
  not from watching snapshots.

## 4. Rendering (client)

- Every character is a **view** node (server chars rendered identically to
  bots — no local-player special case in the sim; the local hero gets a
  camera rig in its view).
- **Interpolation** at latest-server-time − 100 ms over a 4-snapshot ring;
  `lerp_angle` for rotation; stale views freed when a character leaves
  (bot yielded to a human).
- **No client prediction in v1** — local movement shows through the 100 ms
  interp delay. Known feel cost, accepted to ship the wire first;
  prediction + reconciliation + lag compensation are the next net round.

## 5. Testing

- `tests/test_net.tscn` — in-process loopback (server + bot-filled 3v3 +
  real ENet client on 127.0.0.1:7999), 10 checks: connect+slot, hero pick
  honored, bot yield keeps team size, snapshot→views, input roundtrip
  (movement + aim), view tracks server, **combat runs server-side
  (≥2 kills in 60 s) + kill feed relayed**, server survives disconnect.
- Net-sim harness (latency/packet-loss injection) + server-authority property
  tests (client lies rejected) = later Phase 5 round.

## 6. v1 tradeoffs (explicit)

| Tradeoff | Why v1 accepts it | Follow-up |
|---|---|---|
| No client prediction (100 ms feel delay) | Wire + authority first | Prediction + reconciliation round |
| No lag compensation | Server-side validation window is small (hitscan within a few frames) | 100–200 ms rewind window |
| Disconnect freezes slot | Reconnect needs session tokens | Token + resync round |
| No LAN discovery (type host:port) | Direct connect validates the wire | mDNS/UDP broadcast discovery |
| No internet play | LAN-first mandate (directive §21) | Regions + matchmaking prototype |
| Snapshot cap 6/8 (chars/projs) | 6v6 + 8 projectiles is the tuned max | Grow with 6v6 tuning |
