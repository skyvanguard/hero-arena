## Summary

<!-- One sentence: what system changed and why. If it touches the
     docs/ARCHITECTURE.md decisions log, link the design issue. -->

## What was tested

<!-- Evidence, not intentions. Copy the commands + results. -->

- [ ] `--import` clean (all-scripts compile gate)
- [ ] Full headless battery: ____ suites, ____ checks, 0 failed
      (net suites flaky under load? re-ran solo: yes/no)
- [ ] Docker release gate (server changes): image builds +
      `tools/docker_smoke.tscn` → SMOKE PASS
- [ ] Mod validation (mods/ touched): `tools/validate_mods.tscn` → 0 issues
- [ ] Platform for mobile-affecting changes: emulator / real device
      (device + OS, one line; "real device" notes are the standard)

## Definition of done (AGENTS.md)

- [ ] Builds (client + headless server)
- [ ] Tests pass (headless sim; net-sim for networking; bot harness for bots)
- [ ] No new unreviewed dependency (or: license note added to
      docs/OPEN_SOURCE_RESEARCH.md §2.3)
- [ ] Docs touched where architecture changed (ROADMAP checkbox,
      ARCHITECTURE decisions log, system doc section)
- [ ] Android check where gameplay input / rendering changed

## Assets (delete this block if none touched)

<!-- Provenance line: one line, no ambiguity. -->

assets: ____ original, ____ CC0 (____), ____ CC-BY (____, credited in
assets/LICENSE-ASSETS.md + credits screen)

## Screenshots / video (UI or gameplay changes)

<!-- A GIF of the behavior is worth a thousand lines of description. -->
