# RELEASE.md — dedicated server release runbook (Phase 8, D33)

The one-command release the directive promises:

```bash
docker build -f server/Dockerfile -t heroarena/server .   # from the repo root
docker run -d --name heroarena-srv -p 7777:7777/udp -p 7778:7778/udp heroarena/server
```

`docker run` with the default tail starts the **dedicated match server**
(headless Godot 4.7.2, pinned in the image; the import cache is baked in
so container start is fast and deterministic). One container per match;
ENet is UDP-only — **no inbound TCP needed** (works behind NAT with port
forwarding or the built-in relay).

## Verified end-to-end (round 49)

`tools/docker_smoke.tscn` runs a REAL ENet client as a separate host
process against the container's published port and requires a slot +
snapshots:

```bash
docker run -d --name heroarena-srv -p 7777:7777/udp -p 7778:7778/udp heroarena/server
# (host) godot --headless --path game res://tools/docker_smoke.tscn
# -> SMOKE PASS: docker-published server -> external ENet client (slot + snapshots)
```

Result on this machine: **PASS** (slot my_id=6 after 8.0 s of snapshots;
container logs clean, 0 error lines over 11 min uptime). Re-run this
pair after every image rebuild as the release gate.

## Ports

| Port | Proto | What |
|---|---|---|
| 7777 | udp | ENet game traffic (the match) |
| 7778 | udp | LAN discovery (ping/reply with live match state) |
| 7790 | udp | lobby registration (when used, `--lobby`) |
| 7800 | udp | relay control (relay mode only) |
| 7901–8156 | udp | relay virtual ports (relay mode only, publish per deployment) |

Host ports may differ from container ports (`-p 17777:7777/udp`).

## Options (appended after the image name)

```
docker run -d heroarena/server res://net/server.tscn -- --port=7777 \
    --mode=control --map=foundry                    # tdm|control|capture|escort,
                                                     # crossdocks|foundry|sawmill|saltline
docker run -d heroarena/server res://net/server.tscn -- --port=7777 \
    --lobby=<lobby-ip>:7790 --lip=<this-host-lan-ip> \
    --lregion=latam_saopaulo --lname=demo           # register with a lobby
                                                     # (the address players
                                                     # see = --lip, the LAN IP)
```

**Relay mode** (NAT traversal; one per region is plenty for v1):

```bash
docker run -d --name heroarena-relay -p 7800:7800/udp -p 7901-8156:7901-8156/udp \
    heroarena/server res://net/relay.tscn -- --port=7800
# a server behind NAT then adds: --relay=<relay-ip>:7800
```

**Lobby mode** (the matchmaking queue; see docs/NETWORKING.md §9):

```bash
docker run -d --name heroarena-lobby -p 7790:7790/udp heroarena/server \
    res://net/lobby.tscn -- --port=7790
```

## Performance budget

2-core budget profile (measured, docs/PERFORMANCE.md round 27): a full
3v3 bot match holds the 60 Hz step at world-time ratio 1.0000 on
~0.19 cores avg (~10% of a 2-core budget); snapshot pacing verified
through the published ports. Pin the container to 2 cores for the
documentated profile: `--cpuset-cpus="0,1"`.

## Image versioning

`heroarena/server:latest` is the dev tag. For a release, tag the image
after the version commit (e.g. `docker tag heroarena/server
heroarena/server:v0.1.0`) and document the commit hash here. The image
pins Godot 4.7.2 (docs/ENGINE_DECISION.md) and bakes the project's import
cache, so a rebuilt image is the only release artifact that changes per
version.

## Release checklist (per version)

1. `git` tree clean; battery green (`tests/test_*.tscn`, see
   docs/NETWORKING.md §7 for the suite list).
2. `docker build -f server/Dockerfile -t heroarena/server .`
3. `docker run ... heroarena/server` + `docker_smoke.tscn` -> SMOKE PASS.
4. Tag the image `vX.Y.Z`; record the commit hash + date below.

### Release log

| Version | Commit | Date | Notes |
|---|---|---|---|
| v0.1.0 (dev) | 1f20d9e | round 49 | first one-command release: dedicated server verified end-to-end via docker_smoke (external ENet client, slot + snapshots); image rebuilt with rounds 40-49 (perks, passives, 4 maps, 4 modes, progression v2 + shop + events + coach, matchmaking v2, reconnect fix) |
