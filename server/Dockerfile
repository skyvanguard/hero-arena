# Hero Arena - dedicated match server (Phase 5 server ops).
#
# Headless Godot 4.7.2 + the game project (gameplay/ runs headless by design,
# AGENTS.md). One container per match; the lobby is a separate process (run
# the same image with res://net/lobby.tscn, or a host lobby for dev).
#
# Build (from the repo root):
#   docker build -f server/Dockerfile -t heroarena/server .
# Run (2-core budget profile, LAN-reachable):
#   docker run -d --name heroarena-srv --cpuset-cpus="0,1" \
#       -p 7777:7777/udp -p 7778:7778/udp heroarena/server
# Host ports may differ from container ports (host:container), e.g.
#   -p 17777:7777/udp -p 17778:7778/udp
# 2-core budget (measured round 27, docs/PERFORMANCE.md): a full 3v3 bot
# match holds the 60 Hz step at world-time ratio 1.0000 and ~0.19 cores avg
# (~10% of the 2-core budget); 20 Hz snapshot pacing verified through the
# published ports (199/200 in 10 s).
# Run with lobby registration (published address = the docker host's LAN IP):
#   docker run -d --name heroarena-srv -p 7777:7777/udp -p 7778:7778/udp \
#       heroarena/server -- --port=7777 --lobby=<lobby-ip>:7790 \
#       --lip=<this-host-lan-ip> --lregion=latam_saopaulo --lname=demo
#
# Ports: 7777/udp = ENet game traffic, 7778/udp = LAN discovery.
# ENet over UDP: no inbound TCP needed.
FROM debian:bookworm-slim

# Pinned engine (docs/ENGINE_DECISION.md): Godot 4.7.2 stable, official Linux
# x86_64 build from the release archive (the binary is not vendored in the repo).
ARG GODOT_VERSION=4.7.2-stable

# Godot 4.7 dlopens fontconfig/freetype even headless (system font probe);
# everything else (X11, audio) is a soft dependency that headless skips.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip libfontconfig1 libfreetype6 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/godot.zip \
        "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" \
    && unzip -o /tmp/godot.zip -d /usr/local/bin \
    && ln -sf /usr/local/bin/Godot_v${GODOT_VERSION}_linux.x86_64 /usr/local/bin/godot \
    && rm /tmp/godot.zip

COPY game /app
WORKDIR /app

# Bake the import cache into the image (fast, deterministic container start).
RUN godot --headless --path /app --import

EXPOSE 7777/udp 7778/udp

# server_main user args go after "--" (OS.get_cmdline_user_args contract).
CMD ["godot", "--headless", "--path", "/app", "res://net/server.tscn", "--", "--port=7777"]
