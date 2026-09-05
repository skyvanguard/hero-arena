# BUILD.md — demo builds & signing

How the public demo builds (Releases page) are made, and how to reproduce
them from a fresh clone.

## Prerequisites

- Godot **4.7.2 stable** (editor with export templates installed for
  Android + Linux/X11).
- JDK 17+ (for keytool / signing the Android build).
- Android SDK (for local device installs; not needed for the raw export).

## Demo keystore

The demo builds are signed with a **public demo keystore** committed at
game/build/keys/heroarena-demo.keystore (alias heroarena, password
heroarena-demo, valid 10000 days). It exists so the demo APK can be rebuilt
by anyone from this repo. A future production release gets its own
keystore (do not commit that one).

The Android export preset (game/export_presets.cfg, preset "Android")
references it:

    keystore/release="build/keys/heroarena-demo.keystore"
    keystore/release_user="heroarena"
    keystore/release_password="heroarena-demo"

## Android demo APK (release, shipping renderer)

From game/:

    godot --headless --path . --export-release Android build/demo/heroarena.apk

The APK ships with renderer/rendering_method="mobile" (Vulkan Forward
Mobile) — the Android target renderer. For local **emulator** smoke tests
the headless AVD cannot present Vulkan; flip the FEATURE-TAGGED line to
gl_compatibility, rebuild with --export-debug, and remember the emu also
wants target_score := 1 in core/match_config.gd for quick matches (see
docs/PERFORMANCE.md "Known environment notes"). Revert both after.

## Desktop demo (Linux x86_64)

From game/:

    godot --headless --path . --export-release Linux build/demo/heroarena.x86_64.x86_64

Produces the binary + heroarena.x86_64.pck (run with the .pck beside the
binary; chmod +x).

## Dedicated server image

    docker build -f server/Dockerfile -t heroarena/server .   # from repo root
    docker run -p 7777:7777/udp -p 7778:7778/udp heroarena/server

One container per match; see docs/NETWORKING.md for lobby registration and
the 2-core budget (docs/PERFORMANCE.md).

## Uploading to the Releases page

The demo-0.1.0 release assets (heroarena.apk, heroarena.x86_64.x86_64,
heroarena.x86_64.pck) are uploaded to the release with
uploads.github.com asset upload (Content-Type per file type).
