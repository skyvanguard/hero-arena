# NETWORKING.md — Architecture & Protocol (Phase 5, as-built v1.1)

Status: **v1.1 shipped (rounds 10-12) + lobby v1 prototype (round 13)** — v1
(dedicated headless server, LAN direct connect, loopback suite) plus: **server
input sanitization + seq gate, session-token reconnect, World lag-comp
hitscan, client prediction + reconciliation, SimLink net-sim harness** (150 ms
RTT + 2% loss suite), **LAN discovery** (UDP broadcast/unicast ping with live
match state, SCAN in hero-select), **two-device LAN verification** (round 12),
and the **lobby/matchmaking sidecar** (round 13, §9): UDP JSON-lines lobby with
a 4-stage party-aware queue (LATAM-priority widen) and published-server
addressing — verified end-to-end on the emulators (menu → queue → assign →
in-match). NAT traversal/relay is the remaining Phase 5 item.

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
| `0x53` | M_SLOT | S→C | reliable | result i8 (0 ok, -1 team full, **-2 match over**), ch_id u8, team u8, team_size u8, time f32, target_score u8, match_duration f32, **token u32**, **mode_code u8** (0 TDM, 1 Control, 2 Capture, 3 Escort — the client builds its HUD/mirror for the mode), **map_code u8** (index into MapRegistry.ids() — the client's MIRROR arena is built from the same Map data, D18) |
| `0x49` | M_INPUT | C→S | unreliable | seq u16, move (f32,f32), yaw f32, pitch f32, fire u8, edges u8, **time_est f32** (client's estimate of the server time this frame was sampled at) |
| `0x50` | M_SNAPSHOT | S→C | unreliable | seq u16, time f32, score0/1 u8, winner u8, **control (owner u8, progress-team u8, progress u8 — D16)**, **ext u8×4 (mode-specific — D17)**, chars[], projs[] |
| `0x45` | M_EVENT | S→C | reliable | type u8 + payload |
| `0x54` | M_STATS | S→C | reliable | n u8 + per char (world.characters order, same index as the snapshot char list): team u8, kills u8, deaths u8, damage u16 — sent on match_over, BEFORE the over event (D19 results) |
| `0x44` | M_DISCOVER_PING | C→S | UDP discovery port | client name str |
| `0x46` | M_DISCOVER_REPLY | S→C | UDP discovery port | state u8 (0 open, 1 full, 2 over), team_size u8, humans u8, target_score u8, game_port u16, name str, time f32 |

- **Snapshot**: all characters (id u8, team u8, alive u8, hero_idx u8,
  pos (f32×3), rot_y f32, hp/max_hp f32) up to `MAX_CHARS = 6` per side
  (constant: up to `team_size` per side, 6 v1) + up to `MAX_PROJS = 8`
  projectiles (owner u8, pos f32×3, dir f32×3). score0/1 carry the MODE'S
  score (kills in TDM, captures in Control).
- **Perk block (D25, v1.6)**: TRAILING after the projectile array — n u8
  (= char count) + 5 u8 per char in char-list order: [perk_level, perk0,
  perk1, pend0, pend1] as perk-pool indices (255 = none). Backward
  compatible by position: older servers simply don't send the block (clients
  leave `perk_extra = []`), older clients ignore the trailing bytes.
- **Control bytes (D16, Phase 6 v1)**: owner u8 (0 none, 1 team0, 2 team1),
  the team progress runs toward (0/1, 2 none), progress 0..255. The point
  POSITION is not sent — v1 fixes it at the arena center, which the client's
  mirror arena already knows (rotating/multi-point = v2).
- **Ext bytes (D17, Phase 6 v2)**: 4 mode-specific u8 (0 for TDM/Control).
  Capture: ext0/ext1 = the carrier of each team's flag (0 = at base/dropped,
  else snapshot char id + 1) — the flag's live position is the carrier's
  position, already in the char array. Escort: ext0 = payload progress 0..255
  along the lane, ext1 = speed 0..255 (fraction of max_speed). Flag/payload
  LAYOUT is not sent: bases and the lane are the client's own arena
  spawns, deterministic on both sides.
- **Events** (reliable, for UI/feel): E_HIT=0, E_KILL=1 (names + teams +
  headshot), E_RESPAWN=2, E_MATCH_OVER=3, E_HEAL=4, E_PERK=5 (D25: ch u8,
  level u8, choice0/choice1 u8 = pool indices, picked u8 — 255 = the offer is
  pending, else the index the character picked; the client resolves names from
  its own copy of the same `content/perks/perks.tres` pool).
- **Aim convention**: client sends **absolute** camera yaw/pitch; server
  direction = `cos(pitch)·sin(yaw), sin(pitch), cos(pitch)·cos(yaw)`
  (hero rig rotated PI on Y: yaw=pitch=0 → local +Z = project forward).
  Input edges (bitfield): 1 jump, 2 reload, 4 ability1, 8 ability2, 16 ult,
  32 perk_pick0, 64 perk_pick1 (D25) — OR-accumulated per input, consumed
  server-side; perk picks are validated through the same server `pick()`
  entry point (a stale/wrong index is rejected and the offer stays up).
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
- **aim is client-scaled (D24)**: the touch layer multiplies the drag by the
    user's effective sensitivity (ControlLayout baseline x ControlSettings,
    resolved in ControlSettings.effective) before sending; the server treats
    the aim delta like any other client claim - the pitch clamp above is the
    bound. Sensitivity is an ergonomic, per-device local setting: no wire
    field, no P2W.
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
- **Match lifecycle after over (round 28, v1)**: when a match is finished,
  a fresh hello starts a new match **in place** — but only when no other
  human is connected (`slots` empty; all prior humans have left, their slots
  frozen). `MatchServer.reset_match()` frees every character/projectile/zone,
  clears `slots` + `_frozen` (frozen tokens are **invalidated** — a returning
  owner fresh-joins the new match, they do not reattach to a freed body),
  zeroes `team_humans`/`next_id`, and calls `World.reset()` (fresh
  time/score/over/winner on the same world + arena). The scene re-fills the
  bots through the `match_reset` signal (it owns the roster). Joins into an
  over match that still has connected humans are rejected with the over code
  (client shows the existing "MATCH OVER" finish) — v1 has no mid-
  observation reset. Discovery/lobby state is derived from `match_over`, so
  the match advertises OPEN again automatically. Server authority is
  untouched: the reset happens on a hello, between physics ticks, and the
  v1 invariant (nobody connected sees the transition) means no new wire
  messages were needed.
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

### Reconnect reliability (D30, round 46)

A slot reply lost on a lossy link no longer dead-ends the connect:
the client's re-hello watchdog (2 s, max 4 retries, while `my_id < 0`)
re-sends the hello with the same token, and the server re-announces the
existing slot for a peer that already holds one (idempotent re-hello)
instead of fresh-joining a second character. test_net_sim and
test_net_profiles verify it deterministically by dropping the reply path
100% around the token reattach.

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
- `tests/test_net_profiles.tscn` — **SimLink latency/loss profiles (round 28, 30
  checks)**: the test_net_sim battery re-run at three profiles — 50 ms RTT +
  10% loss, 150 ms RTT + 2% loss (the shipped baseline), 300 ms RTT + 10%
  loss — with a fresh world/server/client per profile. Prediction-tracking
  budget scales with RTT (unreconciled window ≈ RTT/2 + interpolation): 1.5 m
  at 150 ms, 3.0 m at 300 ms. Connect/slot, input roundtrip, combat + kill
  feed, and the drop → freeze → token reattach path all hold at every
  profile.
- `tests/test_match_lifecycle.tscn` — **in-place match reset (round 28, 8
  checks)**: sim transport, target 1 (first bot kill ends the match): join a
  live match, wait for over, a fresh join while a human is still connected
  is rejected (over code, no slot), the last human leaves (slot frozen), a
  fresh join resets the match in place (score/time/over cleared, 6-char
  roster + joiner), a pre-reset token fresh-joins instead of reattaching to
  the freed character, and the fresh match steps + streams broadcast
  snapshots.
- `tests/test_relay.tscn` — **NAT traversal v1 (round 29, 7 checks)**: one
  relay (control 7801) in-scene; two match servers (ENet 7777/7778 + worlds +
  6 bots each) register over outbound UDP and get distinct virtual ports;
  two ENet clients connect to `<relay>:<vport>` exactly as NAT'd clients
  would: slot assign per match, 10 s snapshot pacing per client (~20 Hz
  through the pump), no cross-talk (killing client A's peer with reconnect
  disabled freezes its stream while B keeps flowing), and a dropped client
  with reconnect enabled re-joins its own match through the relay (token
  reattach over the forwarded stream).
- `tests/test_mode_control.tscn` — **mode framework + Control (round 30,
  15 checks)**: registry returns TDM/Control (unknown → TDM); TDM-as-mode wins
  at target_score through the framework; the full control state machine —
  solo occupant starts progress, contested freezes it, capture scores + owns
  the point, holding needs no occupancy, enemy re-occupation runs progress
  toward the enemy, a re-capture to 1-1 does NOT end the match, the 2nd team
  capture wins; tied timeout → holder, 0-0 timeout → draw; `World.reset()`
  clears all objective state (D14 compatibility); a bot with no target in a
  neutral control decides CAPTURE with a goal inside the circle; and 6 bots
  in a live control match start capturing within 30 s (stochastic by design).
- `tests/test_mode_capture.tscn` — **Capture/CTF mode (rounds 31-32,
  17 checks)**: registry; setup places flags at the CENTRAL spawns (bases);
  enemy-in-radius steals; the carried flag follows the carrier; carrier death
  drops the flag at the death position (through the `World.kill` ->
  `Mode.on_kill` hook); the flag's own team re-secures a drop; an enemy flag
  carried home scores + returns to its base (no win at 1); the 2nd capture
  wins; tied timeout -> the enemy-flag holder, both-flags-free -> draw;
  `World.reset()` returns flags to bases and clears carriers/captures (D14);
  a bot with no target decides CAPTURE toward the enemy flag; objective
  pressure (D18): a fresh free flag keeps an engaged bot on its ATTACK
  target, a stale one (free > 8 s) pulls it off, and the free-flag clock
  accumulates in step and resets on a steal.
- `tests/test_map.tscn` — **map framework (round 32, 12 checks; round 42:
  17 checks over the four-map pool)**: registry (all four maps resolve,
  unknown/empty -> default); whole-pool integrity (3 spawns per team on
  the central lane, every asset in-bounds, positive box sizes, distinct
  layouts); the Crossdocks data equals the legacy placeholder geometry;
  The Foundry is a distinct original 52 m layout; building from a map
  applies its spawns to the world; Capture bases and the Escort lane
  follow the Foundry spawns (modes-on-map-2 integration); an empty Map
  falls back to the legacy layout; 6 bots fight on Foundry through the
  full MatchServer stack for 8 s within bounds; Sawmill's spawns reach
  the world and the Capture/Escort modes follow them; 6 bots fight on
  Saltline within the 56 m bounds; MatchConfig.map_id drives the host's
  map; the hero-select picker's named handlers write MatchConfig and
  reject unknown ids.
- `tests/test_results.tscn` — **results + progression (round 33, 17
  checks)**: server-side stat accumulation (damage_dealt tracks the final
  applied amount, kill credits killer+victim, source-less kills count the
  death only); World.stats_rows() follows the character-list order; MVP
  selection (most kills, damage tie-break, -1 when no kills); M_STATS
  pack/unpack roundtrip (u16 damage lane); end-to-end over the real ENet
  loopback with the explicit tick() driving (the client slotted, the human
  kills to the target, M_STATS arrives before the over event with the
  final table, the client finishes); ProgressionConfig level curve is
  strictly increasing; PlayerProfile XP rules (win+kills+MVP multi-level-up,
  participation XP, per-hero record) and save/load roundtrip; the
  hero-select progression badge renders.
- `tests/test_vote.tscn` — **next-match mode voting (round 34, 13 checks)**:
  registration carries the host mode; unknown-match and bad-mode votes are
  ignored; one vote per peer (last write wins - re-taps and vote switches
  never inflate); split votes hold without a decision; a strict majority
  flips the directory entry, forwards setmode to the registered match
  server, and the server stores the pending mode; reset_match() applies the
  voted Mode (world.mode swapped + pure-data setup) and clears the pending
  slot; a queueing client's assign carries tally/leading/decided; the state
  heartbeat updates the directory mode; over matches accept votes (the
  results-screen flow). Verified on-device (emulator): results-screen vote
  row, CAP tap, lobby ack rendered as "CAPTURE 1 · leading CAPTURE".
- `tests/test_mapvote.tscn` — **next-match map voting (round 35, 17 checks;
  round 44 D27 anti-repetition)**: registration carries the host map; bad-map
  votes ignored; the entry's current map is rejected as a repeat (pre- and
  post-decision, incl. weighted party votes) and the older map becomes
  votable again once another plays (rotation); `rotation_pool` helper;
  one map vote per peer (last write wins); MODE and MAP tallies are
  independent per peer; split map votes hold; a strict majority flips the
  directory map, leaves the mode domain untouched, and forwards setmap;
  the next reset applies the voted map (arena rebuilt, spawn points
  change, pending slot cleared); assign carries map + map vote state; the
  state heartbeat keeps the directory map fresh.
- `tests/test_mode_escort.tscn` — **Escort mode (round 31, 11 checks)**:
  registry; setup pins the lane from the spawn x's; idle payload; one
  attacker pushes at max_speed with real progress; equal heads fully stop
  it; 2v1 clamps to full speed; delivery (attackers riding the payload) wins
  for the attackers; timeout is a defender win; `World.reset()` parks the
  payload at the start (D14); an unengaged attacker's CAPTURE goal orbits
  the payload on the goal side.
- `tests/test_discovery.tscn` — UDP ping/reply over loopback (6 checks):
  open server answers with game port + state + humans, join reflected in the
  headcount, full and over states advertised (over wins over full), dead port
  finishes empty.
- **Two-device live verification (round 12, not a suite — needs Android):**
  two emulators (different profiles: small portrait-class AVD + pixel_5
  2340x1080 landscape) + a host-dedicated server. Both devices SCAN-found the
  server, joined the same live match on opposing teams, and the cross-device
  checks held: a human headshot on device 2 appeared in device 1's kill feed;
  both clients rendered the arena + HUD + touch controls at their respective
  resolutions; results overlays were per-side correct (team-0 device
  VICTORY 15-8, team-1 device DEFEAT 8-15 local-team-first); 0 script errors
  on both devices and the server; PSS ~149-152 MB each. The emulator NAT only
  reaches the UNICAST discovery leg (broadcasts do not cross it). Verification
  also caught and fixed two bugs (results-overlay team-0 assumption; respawn
  lambda capturing a freed character — see ROADMAP round 12).
- **Broadcast leg verified (round 28, host proxy for real WiFi):** the
  emulator-NAT limitation above meant the BROADCAST half of discovery had
  never been exercised. On the dev host (real /24 NIC, 192.168.100.92/24):
  a `--network host` docker server (same `heroarena/server` image) + a
  broadcast-only scanner (255.255.255.255:7778, no unicast hint) found the
  server (`state=0 OPEN`), and an ENet client joined through the LAN IP
  (slot assign + 20 Hz snapshot stream — server-side seq delta over 10 s
  matched the client count exactly, so the pacing is server-confirmed). This
  is the strongest broadcast-leg evidence available without two physical
  phones; the real-WiFi two-phone sign-off remains the acceptance test.
- Full battery: 30 headless suites, 563 checks (round-38 per-suite counts:
  hero 42 + main 16 + roster 57 + bots 23 + projectile 10 + practice 11 +
  map 12 + mode_control 15 (round 30) + mode_capture 17 + mode_escort 11
  (rounds 31-32) + net 10 + net_props 20 + net_sim 10 + net_profiles 30 +
  lobby 12 (round 13) + match_lifecycle 8 (round 28) + relay 7 (round 29) +
  results 18 (round 33; +1 round 36 regression) + vote 13 (round 34) +
  mapvote 17 (round 35; +5 D27 anti-repetition, round 44) + cosmetics 21 (round 36; D22 mastery/variants are
  client-side - no wire changes) + partyvote 20 (round 37; D23 weighted; round 44: map-domain scenarios moved off the default map for the D27 repeat rule, same 20 checks; D23 weighted voting, real UDP lobby) + controls 25 (round 38; D24 layout x settings,
  headless-resolved) + discovery 6 + perks 38 (round 40; D25 in-match
  perks: XP curve, role-filtered offers, determinism, every effect key,
  bot picks, reset, E_PERK + snapshot round-trips incl. old-server
  backward-compat) + perk_ui 12 (round 40; headless UI smoke: choice
  panel, tap -> pick signal on both HUDs, picked-perk badge, keys 1/2)
  (map suite 12 -> 17 in round 42: whole-pool integrity + bounds, mode-follow
  and 6-bot fight on the new maps) + progression_v2 23 (round 43; D26: achievement conditions/thresholds,
  one-shot grants, old-save compat, reward gating, D26 stat columns,
  seasonal cosmetic validation) + matchmaking_v2 14 (round 45; D28: win-probability model - MMConfig load, win_prob math, even-split projection + fairness gate, party-block grouping, live strict/v1 assignments with win_prob, SKILL-stage gate, REGION fair-preference, BOTFILL ordering, ledger decay, no stranding) + events 15 (round 46; D29: bank integrity + validate catches, exact participation threshold, single/multi mode filters, inactive events, one-shot, reward gating at mastery 1, cosmetic-only mastery, old 7-arg call sites, old-save compat + round-trip, view rows) + passives 25 (round 41; Phase 7 item 2: all six sub-role passives
  behavior-verified in the real pipeline + passive x perk x ult stacking)
  . Note: under heavy machine load several net suites flake (frame-based
  waits vs real-time SimLink latency). test_net_profiles and test_net_sim
  had a structural cause - a slot reply lost on a lossy link dead-ended the
  reattach; D30 (round 46) fixed it (client re-hello watchdog + server
  idempotent re-announce) and both suites now verify the recovery
  deterministically at 100% reply loss. test_roster and
  test_match_lifecycle were observed once each under a loaded battery;
  green on re-run. Re-run quiet for a clean sweep.

## 8. v1.1 tradeoffs (explicit)

| Tradeoff | Why v1.1 accepts it | Follow-up |
|---|---|---|
| Reconciliation hard-snap at 0.35 m | Simple, stable; prediction error that large means something big changed (hit, dash, respawn) | Smarter blend / delta-based correction |
| Lag-comp = analytic 3-sphere rewind (not full physics re-sim) | Cheap and deterministic; capsule shapes match the real colliders | Re-sim window if abilities make it matter |
| One-way latency from client `time_est` (no RTT ping) | ENet + this already bounds the error; window clamp absorbs it | RTT ping for symmetric window |
| Frozen slot can be yielded to a fresh join (token invalidated) | Simpler than slot locks; the joiner gets a spot | Optional slot lock with grace period |
| Discovery deduped by IP (a multi-homed server lists once per interface) | Correct general behavior; LANs rarely multi-home one server | Group by game identity if it ever hurts |
| Broadcasts do not cross the emulator NAT | The unicast leg (explicit host) covers the emulator case; real LANs get both | mDNS if two phones become the acceptance test |
| Internet play is lobby-published, not relayed (§9) | LAN-first mandate (directive §21); relay/hole-punch is a separate follow-up | Relay/hole-punch, lobby HA, party handshake |
| Snapshot cap 6/8 (chars/projs) | 6v6 + 8 projectiles is the tuned max | Grow with 6v6 tuning |
## 9. Lobby & matchmaking (round 13, v1 prototype)

Separate lightweight sidecar for online play: core/matchmaking/regions.gd
(region table), core/net/lobby_protocol.gd (line-JSON + seq helpers),
core/net/lobby_server.gd (UDP sidecar), core/net/lobby_client.gd
(client-side), net/lobby.tscn (headless scene). tests/test_lobby.tscn
covers the queue (12 checks).

### 9.1 Why UDP (and not TCP)

Godot 4.7.2 headless **TCP was probed and is unusable as a server socket**:
TCPServer.listen() returns OK and reports the local port but creates **no
system socket** (no fd under /proc/PID/fd, invisible to ss -tln, external
connects refused; cross-process godot-to-godot TCP ends in STATUS_ERROR).
In-process loopback TCP works — which is exactly what a lobby is not. UDP
(PacketPeerUDP) is fully real in headless (proven by discovery + the
two-emulator runs). So the lobby transport is **UDP with application-level
reliability**:

- One JSON object per line (newline-terminated; a line may span packets —
  the server keeps a per-peer line buffer).
- Every client-to-server message needing an ack (join, reg) carries a seq;
  the server dedupes per (peer, type, seq); the client retransmits the same
  seq every 2.5 s until acked.
- The server only sends queue progress while queued, so the client treats any
  lobby message as keep-alive; 4 s of silence -> the client re-joins with a
  FRESH seq (a lost assign would otherwise be swallowed forever by the
  same-seq dedupe).
- Ping every 1 s = keep-alive + RTT display. "Connected" = a fresh message
  (any type); 5 s of silence = disconnected. The state machine keys on
  RECEIVED time, not the last pong: a stale pong would re-fire the connect
  branch forever (round-13 bug, fixed).

### 9.2 Message types (lobby protocol v1.5, D20/D21/D23 voting)

| Type | Dir | Seq | Notes |
|---|---|---|---|
| ping / pong(at) | both | ping only | RTT echo; first ping from a new peer also triggers hello (UDP has no connect) |
| hello{region,matches,waiters} | s->c | - | Sent on first ping |
| join{region,party,skill,name} | c->s | yes | Creates the waiter |
| queue{stage,waited,open} | s->c | - | >=1 Hz while queued; doubles as keep-alive |
| assign{host,port,match_id,region,name,mode,map,tally,leading,decided,map_tally,map_leading,map_decided,stage,win_prob (D28: join win-chance, -1 unknown),waited} | s->c | - | mode/map = the match's mode + map ids (D18: the queued client knows what it is joining); tally/leading/decided + map_* = the D20/D21 vote state (mode and map are independent tallies) |
| reg{ip,port,region,team_size,name,mode,map} | s->s | yes | A game server registers its match (published address + mode D18 + map D21) |
| regack{match_id} | s->s | - | |
| state{humans,over,mode,map} | s->s | - | Live match state (2 s heartbeat while the server is alive, so the entry survives the 5 s reap during long silent bot-only stretches); mode/map = what the server is actually running, so the directory reflects voted swaps at the next reset; ANY message from a match peer refreshes match liveness |
| vote{match_id,mode,[party_id,party_size,leader]} | c->s | no | D20: vote the match's NEXT mode. Fire-and-forget; one vote per peer p |er match PER DOMAIN, last write wins (re-taps/retransmits never inflate) |
| voteresult{match_id,tally,leading,decided,mode,[party_vote]} | s->c | - | D20/D23: ack with the running WEIGHTED tally; the deciding voter's own ack already shows decided=true; party_vote=true acks a non-leader member (no weight added) |
| setmode{match_id,mode} | s->s | - | D20: a strict majority decided; forwarded to the registered match server, which stores it for the next in-place match reset (a live match never changes rules mid-fight) |
| mapvote{match_id,map,[party_id,party_size,leader]} | c->s | no | D21/D23: vote the match's NEXT map; same rules as vote, independent weighted tally |
| mapvoteresult{match_id,tally,leading,decided,map,repeat,[party_vote]} | s->c | - | D21/D23: ack with the running weighted map tally (party_vote as voteresult); D27: repeat = the entry's current map (excluded from the pool) |
| setmap{match_id,map} | s->s | - | D21: a strict majority decided the map; the server rebuilds the arena (free old geometry, Arena.build) at the next in-place reset |

### 9.2a Next-match mode + map voting (D20/D21, rounds 34-35)

- **Why the lobby**: the lobby is the only place that knows both the voters
  and the match server, and it already carries the match's mode in reg/assign.
  Voting is community pressure on the host's default, not a new authoritative
  system: the match server validates the id (ModeRegistry.ids()) and stays the
  rulekeeper - it only ever swaps the mode at a reset, between matches.
- **Tally rule**: one vote per peer per match (the lobby keeps
  vote_source{peer:mode}; a new vote retracts the previous one, so same-mode
  re-votes are idempotent). A decision needs >= 2 votes AND a strict
  majority. Decisions are sticky (first decision wins); re-registration
  (server restart) starts a fresh, empty tally.
- **D23 weighted tallies (v1.5)**: the tally values are WEIGHTS, not counts.
  A party speaks through its leader: the leader's vote carries
  party_size (clamped 1..6) as weight, and non-leader members sending the
  same party_id with leader=false are acknowledged with party_vote=true and
  add no weight. A decision now needs a strict weighted majority
  (winner*2 > total) AND >= 2 voting entities (peers) - a single party,
  however large, cannot unilaterally decide its own domain, and equal
  parties (3v3, 2v2) tie and hold. A leader re-vote moves the whole weight
  (retract with the old weight, add with the new). Party context rides the
  vote message itself because assigned peers leave the waiter queue, so a
  per-waiter identity would be lost on assignment. Solo voters (no
  party_id) keep weight 1: all-solo lobbies behave exactly like v1.4, and
  v1.4 clients are plain solo voters on a v1.5 lobby (the party fields are
  optional; old lobbies ignore them). The party group-join handshake (one
  token for the whole group) and party UI remain v2 - today a party is a
  convention its members agree on (same party_id), matching the
  lobby's existing unauthenticated trust model.
- **Application point**: MatchServer.set_mode_from_lobby() stores
  _pending_mode; reset_match() (the in-place new-match path, triggered by a
  hello after the match is over) assigns the voted Mode resource and runs its
  pure-data setup() before the scene re-fills the bots.
- **Over matches are votable**: a vote targets the NEXT match, and the
  server runs it in-place on the next hello (the directory entry - and its
  vote cycle - persists across in-place resets; re-registration starts
  fresh). Decisions are sticky per directory entry.
- **v1 scope**: mode + map voting (D20/D21) with per-party vote bundles
  (D23). In-match (pre-start) application and the party group-join
  handshake (+ party UI in hero-select) are v2.
- **UI**: the results screen (net + lobby matches) shows a
  "NEXT MATCH - VOTE THE MODE" row with four buttons; the voteresult ack
  renders the running tally / leading mode / DECIDED line. The vote lobby
  connection lives for the results screen only (freed on continue).
### 9.3 Four-stage queue (party-aware, LATAM-priority)

| Stage | Window | Candidate rule |
|---|---|---|
| 1 STRICT | 0-5 s | exact region match |
| 2 SKILL | 5-15 s | no-op in v1 (skill recorded, not ranked) |
| 3 REGION | 15-60 s | any region in Regions.widen_order(preference) — LATAM first (Sao Paulo -> Bogota -> CDMX), then NA/EU/Asia |
| 4 BOTFILL | 60 s+ | any not-over match with room; fewest humans, then rank |

A candidate needs room = team_size - humans >= party; over matches are never
candidates. regions.gd holds the widen-order table (infra table, not
gameplay balance — the magic-number rule's infra exception).

### 9.4 Addressing & ops

- The lobby assigns **published server addresses**: a game server starts with
  --lobby=<host:port> --lip=<reachable IP> --lregion=<code> --lname=<name>
  and registers itself; the client's assign carries that published ip:port.
  **Direct mode (--lip)** still applies when clients reach the server without
  a relay (LAN, or a relay-less server): --lip must be reachable from joining
  clients (on an emulator, 10.0.2.2 = the host; a host-side process must use
  127.0.0.1 for its own lobby leg — 10.0.2.2 only resolves from the emulator
  side). OS.get_local_ip() is gone in Godot 4.7, so the server is told
  explicitly (it warns when the 127.0.0.1 default is left). **Relay mode**
  (--relay=, §9.5) supersedes --lip: the published address becomes the relay's
  virtual port, which is reachable by definition.
- MatchConfig.lobby_port = 7790 default. Hero-select has an ONLINE panel:
  region cycle + live ping + PLAY -> queue -> auto-join via net_deployed
  (ENTER/SPACE offline-launch is suppressed while queued).
- The lobby is a separate headless process:
  lobby.tscn -- --port=7790 --region=latam_saopaulo --fill=60. The game
  server is unchanged except registration + state broadcast.
- **Dedicated server image (round 27):** `server/Dockerfile` (repo-root build
  context) ships the pinned Godot 4.7.2 binary + `game/` project with the
  import cache baked in; `docker run -d --cpuset-cpus="0,1" -p 7777:7777/udp
  -p 7778:7778/udp heroarena/server` starts a 3v3 server (ENet 7777/udp +
  discovery 7778/udp). Bridge networking is fine (verified: discovery reply
  + ENet handshake + 20 Hz snapshot stream through the published ports from
  the host); `--network host` also works if you want no port mapping.
  2-core budget: docs/PERFORMANCE.md (round 27 section).

### 9.5 NAT traversal v1: relay (round 29, D15)

A match server behind a NAT cannot be dialed directly: the only mapping that
exists points OUT (the server's own outbound connections). The relay turns
that into a joinable address:

1. The server starts with `--relay=<relay-ip>:7800` (in addition to
   `--lobby=...`). `RelayClient` (core/net/relay_client.gd) opens an
   **outbound** UDP socket and sends
   `R_REG [0x52 0x47, token u32 LE, game_port u16 LE]` — the relay learns the
   server's NAT mapping (the registration source address) and the ENet port
   to forward to (the registration socket is a different socket from the
   game's, so the game port must ride in the payload).
2. The relay (core/net/relay.gd, `res://net/relay.tscn`) grants a **virtual
   port** from 7901..8156 (256 concurrent matches — far above the 2-core
   single-match budget; wide range so VPS port collisions are obvious) and
   replies `R_OK [0x52 0x4F, vport u16 LE]`.
3. Lobby registration is **deferred** until the vport is granted, and the
   published address becomes `<relay_ip>:<vport>` — the ONLY change the
   lobby sees. **The client protocol is untouched**: it makes a normal ENet
   connection to the assigned address, which just happens to be a relay
   virtual port.
4. The relay is a headerless per-(match, client) datagram pump. Each link
   gets one ephemeral socket, giving the two identities that NAT traversal
   demands:
   - client datagram → relay vport socket → forwarded via the link socket
     (source = the link's ephemeral port) → server: the server sees every
     relayed client from a DISTINCT source port, exactly as on a flat LAN;
   - server reply → arrives at the link socket → forwarded via the **vport
     socket** → client: the client sees the server AT the vport it dialed
     (ENet binds a connection to the dialed address; a reply from any other
     source port is dropped as an unknown peer — this was the round-29 bug
     that kept the handshake from completing).
   ENet's own reliability, channels, and flow control run on the forwarded
   stream; the relay parses nothing below the two control datagrams.
5. Liveness: `R_PING [0x52 0x50]` every 10 s keeps the server's NAT mapping
   open even with zero clients; re-REG every 5 s until R_OK (give up after
   10). Eviction: a match silent > 60 s loses its vport (and its links);
   an idle link > 120 s is closed (ENet heartbeats keep live links well
   under that).

**Run:** `godot --headless --path game res://net/relay.tscn -- --port=7800`
or the same docker image: `docker run -d --name heroarena-relay
-p 7800:7800/udp -p 7901-8156:7901-8156/udp heroarena/server
res://net/relay.tscn -- --port=7800` (the image moved to the ENTRYPOINT+CMD
convention in round 29 so `docker run` args work — the old exec-form CMD
made any run-arg replace the whole command; the round-27 lobby-run example
in the Dockerfile header was corrected accordingly). Server: add
`--relay=<relay-ip>:7800`. LAN discovery is unaffected (LAN clients still
reach the server directly; the relay serves other networks).

**Verified (round 29):** test_relay 7/7 (two relayed matches in parallel —
distinct vports, slots, 10 s pacing per client, no cross-talk, reconnect
through the relay) + a **live NAT test**: server in a docker BRIDGE container
(real network boundary) registering in a host relay, probe client joining
through the vport: slot assign + 199 snapshots in 10 s (~19.9 Hz) + 207
combat events; and the FULL online flow: lobby queue → assigned
`<relay-ip>:7901` → ENet join through the relay → slot in ~300 ms. One
topology note from that test: the advertised host part of the address must
be the address CLIENTS use to reach the relay (public/LAN IP of the relay
host); a client on the relay's own host reaches it at loopback.

**Follow-ups (tracked):** STUN-style address discovery (relay tells server
its public ip so the server can auto-publish), hole-punching for
symmetric-NAT pairs that can connect directly (relay stays as fallback),
relay HA / multi-instance (vport space is per-instance), R_REG token auth
(lobby-issued match secret). One relay per region is plenty for v1 scale.

### 9.6 v1 tradeoffs (explicit)

- JSON lines over UDP: human-readable, zero codec deps, plenty for lobby
  traffic; not binary-optimized (fine until thousands of waiters).
- Party v1: a party only fits a match with room >= party; the party
  group-join handshake is deferred. Voting is party-aware since D23
  (§9.2a): a party's leader votes with its size as weight, members defer
  to the leader (party_vote ack).
- One lobby process per region table; multi-region deployment + redirect is a
  follow-up.
- Relay v1: one instance per region, no auth token (R_REG token = 0), no
  hole-punching — servers behind NAT always relay (§9.5 follow-ups).
- Skill (stage 2) recorded but unranked in v1.
- Botfill = "any open match after 60 s" because every match bot-fills
  anyway; fewest-humans ordering is the v1 fairness choice.
