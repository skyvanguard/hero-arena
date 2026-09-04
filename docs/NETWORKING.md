# NETWORKING.md — Architecture & Protocol (Phase 5, as-built v1.1)

Status: **v1.1 shipped (rounds 10-11)** — v1 (dedicated headless server, LAN
direct connect, loopback suite) plus: **server input sanitization + seq gate,
session-token reconnect, World lag-comp hitscan, client prediction +
reconciliation, SimLink net-sim harness** (150 ms RTT + 2% loss suite), and
**LAN discovery** (UDP broadcast/unicast ping with live match state, SCAN in
hero-select). Internet play remains the last Phase 5 item.

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
- **SimLink** (`core/net/sim_link.gd`, RefCounted) is the swappable transport:
  the server/client send through `sim_out` and poll `sim_in` when set, else
  through ENet. SimLink models one-way **latency (ms)** + independent
  **loss probability** per direction (packet queues keyed on real time,
  `drop_all()` simulates a drop). This is how the net-sim suite proves the
  whole stack at 150 ms RTT + 2% loss with no sockets, and how the future
  latency-profile runs (50/150/300 ms, 10% loss) will work.
- Server scene: `net/server.tscn` (`net/server_main.gd`) — headless, no UI,
  `--port=N` user arg (`--dport=N` for discovery). Pre-fills both teams
  with bots to `MatchConfig.team_size`; a human join **yields the bot
  standing at the spawn point itself** (team pick = fewer *humans*, so 1v1
  fill still works). Yield uses **immediate `free()`**, not `queue_free()`:
  a frame of exact overlap between the fresh human and the yielding bot pushes
  them apart vertically at ~66 m/s (Godot 4.7 resolves exact capsule overlaps
  with a vertical MTV — probe-verified), which would visibly hop the joiner.
- **LAN discovery** (`core/net/discovery.gd` responder +
  `core/net/discovery_scanner.gd` client): the server answers
  M_DISCOVER_PING on the UDP **discovery port** (`MatchConfig.net_discovery_port`
  = 7778; separate from the ENet game port, which owns UDP on 7777) with the
  live state (open / full / over, team size, human count, game port). The
  client SCAN broadcasts the ping (255.255.255.255) **and** unicasts it to the
  explicit host in the join field — the unicast leg also works across the
  emulator NAT, where broadcasts do not reach the host. Results are deduped by
  IP (a multi-homed server legitimately appears once per interface).
- **Godot 4.7 PacketPeerUDP note (probed):** `set_mode_server()` /
  `set_mode_client()` are gone — use `bind(port)` (server: all interfaces;
  client: `bind(0)` = connectionless ephemeral) + `set_dest_address()` +
  `put_packet()`; poll with `get_available_packet_count()` / `get_packet()` /
  `get_packet_ip()` / `get_packet_port()` (read ip/port only AFTER
  `get_packet()` — the packet identity is consumed by that call);
  `set_broadcast_enabled(true)` for broadcast sends.
- Client: `core/net/match_client.gd` — embedded in the game process
  (hero-select JOIN row). Builds a local un-stepped `World` + `Arena.build`
  for visuals only; all sim state comes from snapshots.
- **Client-side physics bodies are invisible** (all nested bodies zeroed,
  receiver included, via a manual walk — `find_children` misses the receiver
  and in 4.7 returned 0 matches even when attached). In-process/loopback the
  server and client worlds share one physics space; a view body coincident
  with a server character pushes it and blocks LOS and weapon rays
  (verified in round 9: bots scanning "saw" nothing because a view head-sensor
  sat on the enemy's head). The **prediction twin** (`§4`) is zeroed the same
  way.

## 2. Wire protocol (v2)

All integers little-endian; strings `u16 len + utf8`; floats IEEE-754 f32
(manual bit codec — 4.7 dropped `PackedFloat32Array.pack_bytes()`).
Dispatch is by first magic byte, channel-independent:

| Magic | Name | Dir | Channel | Payload |
|---|---|---|---|---|
| `0x48` | M_HELLO | C→S | reliable | team_size u8, hero_id str, **session u32** (0 = fresh join, else slot token) |
| `0x53` | M_SLOT | S→C | reliable | result i8 (0 ok, -1 team full, **-2 match over**), ch_id u8, team u8, team_size u8, time f32, target_score u8, match_duration f32, **token u32** |
| `0x49` | M_INPUT | C→S | unreliable | seq u16, move (f32,f32), yaw f32, pitch f32, fire u8, edges u8, **time_est f32** (client's estimate of the server time this frame was sampled at) |
| `0x50` | M_SNAPSHOT | S→C | unreliable | seq u16, time f32, score0/1 u16, winner i8, chars[], projs[] |
| `0x45` | M_EVENT | S→C | reliable | type u8 + payload |
| `0x44` | M_DISCOVER_PING | C→S | UDP discovery port | client name str |
| `0x46` | M_DISCOVER_REPLY | S→C | UDP discovery port | state u8 (0 open, 1 full, 2 over), team_size u8, humans u8, target_score u8, game_port u16, name str, time f32 |

- **Snapshot**: all characters (id u8, team u8, alive u8, hero_idx u8,
  pos (f32×3), rot_y f32, hp/max_hp f32) up to `MAX_CHARS = 6` per side
  (constant: up to `team_size` per side, 6 v1) + up to `MAX_PROJS = 8`
  projectiles (owner u8, pos f32×3, dir f32×3).
- **Events** (reliable, for UI/feel): E_HIT=0, E_KILL=1 (names + teams +
  headshot), E_RESPAWN=2, E_MATCH_OVER=3, E_HEAL=4.
- **Aim convention**: client sends **absolute** camera yaw/pitch; server
  direction = `cos(pitch)·sin(yaw), sin(pitch), cos(pitch)·cos(yaw)`
  (hero rig rotated PI on Y: yaw=pitch=0 → local +Z = project forward).
  Input edges (bitfield): 1 jump, 2 reload, 4 ability1, 8 ability2, 16 ult —
  OR-accumulated per input, consumed server-side.
- **Rates**: snapshots 20 Hz (`SNAPSHOT_HZ`), input sampled 20 Hz
  (`INPUT_HZ`) on the client. Server steps at 60 Hz fixed.

## 3. Authority model (v1.1)

- Server owns: positions, HP/damage, ammo, cooldowns, score, deaths/respawns,
  match end. The client never sends state, only input (declared action fields).
- **Input sanitization** (all in `MatchServer._on_input`, property-tested in
  `test_net_props`):
  - **seq gate**: u16 wrap-aware — a frame with
    `(seq - last + 32768) % 65536 - 32768 <= 0` is stale/replayed and is
    dropped whole (move, aim, fire, edges alike). Edges are OR-accumulated on
    the accepted frame, so a replayed edge can't re-trigger a jump/reload.
  - **move** magnitude clamped to 1.0 (client lies about the joystick),
    **yaw** wrapped to [-π, π], **pitch** clamped to [-1.25, 0.9] rad
    (content/balance owns the real aim range; the clamp is a sanity bound).
  - **Latency estimate**: `time_est` → server measures one-way input age
    `clamp(server_time - time_est, 0, lag_comp_window)` and stores it as
    the character's `net_comp_delay` (feeds lag-comp, `§6`).
- Remote humans are **server-side `Hero` + `NetPlayerController`** — the same
  controller interface as bots (D3 parity): fed from per-peer `NetInput`.
  Bots and humans are indistinguishable to the sim. (The client reuses the
  same class for its prediction twin, `§4`.)
- **Reconnect (session tokens)**: on disconnect the slot **freezes** —
  `_frozen[token] = {ch, team, hero_id}`, controller removed, input zeroed,
  `net_comp_delay` zeroed, `team_humans` decremented; the character stays in
  the sim. The token came with M_SLOT (random u32). A re-hello carrying
  `session == token` **reattaches**: same `CharacterEntity` instance, same
  char id, fresh controller/input, token consumed, team humans restored.
  A fresh join can yield a frozen slot (then the token is invalidated and a
  re-hello falls through to a normal join). Client side: bounded retry
  (`MAX_RECONNECTS = 6`, 0.5 s cadence) re-creates the ENet peer and re-hellos
  with the stored token; the server never sees more than the slot.
- Kill feed / match-over on the client come from the reliable event channel,
  not from watching snapshots.

## 4. Client prediction + reconciliation

- The client keeps a **private prediction world** (`_pw`, `World` +
  `Arena.build`) and a **twin character** (`_pch`, a real `Hero`,
  `is_player = false`, driven by a real `NetPlayerController`) — i.e. the
  local player is simulated through the exact same code path as server
  characters and bots (D3 parity, client-side).
- Every 20 Hz input sample (`_sample_input`) feeds **both** the wire frame
  (with `time_est`) and the twin's `NetInput` — the same edge is applied
  once per sample group, on both sides.
- `_pw.step(1/60)` runs in the client's `_physics_process` (bounded
  catch-up, ≤ 4 steps). The local player's **view** is rendered from the twin
  (no interpolation delay for own movement); other views interpolate as in v1.
- **Reconciliation** on each snapshot (`_reconcile`):
  - server says I'm dead → stop stepping the twin (`_pred_dead`) until respawn;
  - respawn or position error > `PRED_SNAP_DIST = 0.35 m` → **hard snap**
    (pos/rot, velocity zeroed);
  - otherwise keep the local sim (error absorbed by the next input's edges).
- Twin physics is zeroed (body + nested) and masked to world-only, and its
  visuals are hidden — the view node is what renders. (Shared-physics-space
  rule from `§1` applies to the twin too.)
- Enabled by `MatchConfig.net_prediction` (default on).

## 5. Rendering (client)

- Every character is a **view** node (server chars rendered identically to
  bots — no local-player special case in the sim; the local hero gets a
  camera rig in its view).
- **Interpolation** at latest-server-time − 100 ms over a 4-snapshot ring;
  `lerp_angle` for rotation; stale views freed when a character leaves
  (bot yielded to a human).
- **The local player's view follows the prediction twin** (`§4`) — own
  movement has no interpolation delay; everything else interpolates.

## 6. Lag compensation (server hitscan)

- Every `World.step` records each character's pose into a per-character
  60 Hz history tail (`_history`, cap `int(lag_comp_window·60) + 2`).
- `World.hitscan(origin, dir, source, max_range)` is the **single source of
  truth** for all hitscan (weapons call it; the old per-weapon ray is gone):
  1. a current physics ray (`get_direct_space_state().intersect_ray`,
     mask WORLD|BODY|HEAD, `source.own_rids()` excluded) gives wall distance
     and the current-body hit;
  2. **analytic rewind**: each *enemy* character is tested at past poses
     (3-sphere capsule approx: body spheres r `BODY_RADIUS` at
     pose ± `BODY_HALF_H`·up, head sphere r `HEAD_RADIUS` at
     pose + `HEAD_OFFSET`·up — the same shapes `HeroFactory` builds the
     colliders from, now referenced through `CharacterEntity` consts).
     `delay = clamp(source.net_comp_delay, 0, lag_comp_window)`; samples =
     `ceil(delay·60)` (cap 120). Best (min t) across current + past wins.
- Window: `MatchConfig.lag_comp_window = 0.2` s, applied to
  `world.lag_comp_window` at server setup. A shot aimed at where a target
  was `delay` ago validates; the same ray at delay 0 misses (both
  directions property-tested, plus window-clamp and head-pose cases).
- Bots have `net_comp_delay = 0` (they run at server time) — lag-comp only
  bends validation for human input.

## 7. Testing

- `tests/test_net.tscn` — in-process loopback (server + bot-filled 3v3 +
  real ENet client on 127.0.0.1:7999), 10 checks: connect+slot, hero pick
  honored, bot yield keeps team size, snapshot→views, input roundtrip
  (movement + aim), **view tracks server state (after input stops — the view
  trails by a snapshot or two mid-motion, converging to a standing state is
  the stable property)**, **combat runs server-side (≥2 kills in 60 s) + kill
  feed relayed**, server survives disconnect.
- `tests/test_net_props.tscn` — **server-authority property tests** (20
  checks), no ENet: crafted input frames go straight into
  `MatchServer._on_input`: move clamp (1000× joystick), stale-seq fire/move/
  edge rejection (u16 wrap-aware), pitch/yaw clamp, ammo never negative over
  20 s of fire + shot-event/`weapon.shots_fired` parity; **lag-comp
  geometry** (scripted 4 m/s target, shot-at-old-pose validates with delay /
  misses at delay 0 / head-pose headshot / window clamp / older-than-window
  miss); **server-side reconnect** (token issue, freeze, same-instance
  reattach, token consumed, dead-token fresh-join fall-through).
- `tests/test_net_sim.tscn` — **SimLink full-stack** (10 checks): 150 ms RTT
  (75 ms/way) + 2% loss per direction, no ENet: slot via sim, input roundtrip
  under latency, **predicted view tracks server (<1.5 m) under latency**,
  50 s combat (≥2 kills) + kill feed, **drop → freeze → new client re-hellos
  with the token → same CharacterEntity instance + same char id, token
  consumed**, server keeps stepping.
- `tests/test_discovery.tscn` — UDP ping/reply over loopback (6 checks):
  open server answers with game port + state + humans, join reflected in the
  headcount, full and over states advertised (over wins over full), dead port
  finishes empty.
- Full battery: 10 headless suites, 205 checks.

## 8. v1.1 tradeoffs (explicit)

| Tradeoff | Why v1.1 accepts it | Follow-up |
|---|---|---|
| Reconciliation hard-snap at 0.35 m | Simple, stable; prediction error that large means something big changed (hit, dash, respawn) | Smarter blend / delta-based correction |
| Lag-comp = analytic 3-sphere rewind (not full physics re-sim) | Cheap and deterministic; capsule shapes match the real colliders | Re-sim window if abilities make it matter |
| One-way latency from client `time_est` (no RTT ping) | ENet + this already bounds the error; window clamp absorbs it | RTT ping for symmetric window |
| Frozen slot can be yielded to a fresh join (token invalidated) | Simpler than slot locks; the joiner gets a spot | Optional slot lock with grace period |
| Discovery deduped by IP (a multi-homed server lists once per interface) | Correct general behavior; LANs rarely multi-home one server | Group by game identity if it ever hurts |
| Broadcasts do not cross the emulator NAT | The unicast leg (explicit host) covers the emulator case; real LANs get both | mDNS if two phones become the acceptance test |
| No internet play | LAN-first mandate (directive §21) | Regions + matchmaking prototype |
| Snapshot cap 6/8 (chars/projs) | 6v6 + 8 projectiles is the tuned max | Grow with 6v6 tuning |
