# MODS.md — mod support v1 (Phase 8, D34)

A mod is a **directory of data files** — the same `content/` Resources the
game itself ships. No code is required; every gameplay value stays
server-authoritative (a mod can tune a hero's kit, but the server still
computes damage, kills, and score).

## Where mods live

| Root | What | Precedence |
|---|---|---|
| `res://mods/<id>/` | bundled with the project (the mod index) | shadowed by the same id in `user://mods` |
| `user://mods/<id>/` | user drop-in (the game's user directory) | wins over a bundled copy of the same id |

The **mod index** is the `mods/` directory + the registry below. Drop a
folder into `user://mods/` and the next launch picks it up — that is the
entire install step.

## Manifest (required)

Every mod needs `<id>/mod.tres`:

```tres
[gd_resource type="Resource" script_class="ModManifest" load_steps=2 format=3]

[ext_resource type="Script" path="res://core/modding/mod_manifest.gd" id="1"]

[resource]
script = ExtResource("1")
id = "my_mod"                # must equal the directory name
display_name = "My Mod"      # required, non-empty
author = "you"               # shown by the validator
desc = "What it does."
version = "1.0.0"            # required, non-empty
api_version = 1              # must be <= the game's ModLoader.API_VERSION
```

**Versioned mod API:** the game's current mod-API generation is
`ModLoader.API_VERSION` (currently **1**). A mod whose `api_version` is
*newer* is rejected with a readable reason ("requires mod API N - update
the game"); older mods are accepted. API changes are additive-only:
new fields default, old layouts keep loading.

## Drop-in content (all optional per mod)

```
<id>/
  mod.tres                      manifest
  heroes/<hero_id>.tres         HeroData - appended to the roster
  maps/<map_id>.tres            Map - appended to the map pool
  modes/<mode_id>.tres          Mode-derived Resource - appended to the modes
  cosmetics/*.tres              HeroVariantBank - its sets are added for
                                hero_ids that have no base set (base wins)
  balance/entries/<hero_id>.tres BalanceEntry - tuning for your hero
  balance/<file>.tres           whole-file override of the matching
                                res://content/<file>.tres
```

Rules:
- **Heroes** are fully self-contained `HeroData` files (weapon dict,
  passive, abilities, ult - see `content/heroes/kestrel.tres` as the
  reference shape; weapons/abilities ride inside the hero). A hero id
  colliding with a base hero is rejected by the validator (base wins).
  The hero's `sub_role` must match its passive kind (the roster harness
  enforces the identity contract) and its weapon stats must land inside
  the role's balance band (`content/balance/balance.gd` BANDS).
- **Balance overrides** (the only "tune the game" lever in v1): the file
  must be the **same resource type** as the base. Supported keys:
  `progression.tres` (ProgressionConfig), `matchmaking.tres` (MMConfig),
  `coach/coach.tres` (CoachConfig), `events/events.tres` (EventBank),
  `shop/shop.tres` (ShopBank), `achievements/achievements.tres`
  (AchievementBank), `cosmetics/seasons.tres` (SeasonBank),
  `perks/perks.tres` (PerkPool). When two accepted mods override the same
  file, the **alphabetically last mod id wins** (deterministic).
- Mod mode Resources are shared cached instances - objective state lives
  on the world (`mode.setup(world)`), so stateless mode scripts are the
  contract.

## Validation tool

```bash
godot --headless --path game res://tools/validate_mods.tscn
# exit code = issue count; prints one line per mod
```

Checks: manifest acceptance (id/name/version/api), hero kit integrity
(id == file name, weapon keys, passive/ult/ability kinds, role/sub_role
range, base-id collisions), map integrity (id, size, spawn balance,
box/box-size parity), mode type, cosmetic set shape (palette 5,
unlock_levels 5), balance entry shape (id, multipliers > 0), and override
types. `test_mods` (tests/) exercises every rule headless, including the
rejection paths and override precedence.

## Mod index (published mods)

| Mod | Version | API | Author | Contents |
|---|---|---|---|---|
| [starter_pack](../game/mods/starter_pack/) | 1.0.0 | 1 | hero-arena (reference community mod) | original hero **Vanta** (controller: Veil Stacks / Smoke Step / Ember Ward / Vanta's Veil), original map **Drift Flats**, Vanta cosmetic set, Vanta baseline balance entry |

`starter_pack` is the **first community mod** (Phase 8 exit item) and the
reference implementation: it is bundled, validated, played by bots (they
share the controller interface), and exercised by `test_mods`.

## Known v1 limits

- A mod cannot remove/rename base content (additive only; base wins on
  id collisions).
- Variant sets merge per hero (whole set), not per palette slot.
- `user://mods` is per-machine (the mod index is the repo `mods/` folder;
  publishing = adding a directory + a row in the table above).
