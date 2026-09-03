# GAME_DESIGN.md — hero identities & design pillars

Original IP only (no T3 Arena / Overwatch names, models, or kit structures
copied — see T3_RESEARCH.md §9 and OVERWATCH_RESEARCH.md §8 for what we
studied vs. what we may use). Each hero must be understandable in seconds
and feel like a different game in ≤5 minutes (Phase 3 exit).

## Design pillars

1. **Readable in seconds** — role + movement identity visible from silhouette/
   color + one core verb.
2. **Kit = 1 passive + 2 abilities + 1 ultimate** — all data-driven (.tres);
   ult charge is combat-driven (damage dealt/taken + kills), never kill-only.
3. **Every hero has a movement identity** — how they get around is as
   distinctive as what they shoot.
4. **No stat-stick heroes** — the kit must change *how* you play, not just
   *how much* you hit for.

---

## Hero #1 — KESTREL (Assault / Sustained)

**Role:** Assault — front-line reliable damage. **Sub-role:** Sustained
(consistent pressure, repositioning, streak-based efficiency).

**Identity in one line:** the front-line falcon — you hover on the edge of
the fight, dash in, string hits, and the longer your streak holds the
sharper you get; at full charge you go full predator.

**Movement identity:** double dash (Glide Burst) + hit-streak speed. Plays
like a hovering raptor: short bursts of speed, never one long commit.

| Slot | Name | Behavior | Data (kestrel.tres) |
|---|---|---|---|
| Weapon | Vector Rifle | 11 dmg / 11 rps / clip 35 / spread 0.4° — high-ROF vector auto | see profile |
| Passive | Wingbeats | 5 landed hits within 2 s = 1 stack (max 2): +5%/+10% speed, -10%/-20% spread | stack_hits=5, window=2.0, tiers |
| Ability 1 (Q) | Glide Burst | double 14 m/s dash in aim direction, 0.12 s apart | count=2, speed=14, CD 6 s |
| Ability 2 (E) | Wingfire | 4-pellet burst, 18° cone, 8 dmg each, applies 25% slow for 3 s | pellets=4, cone=18°, CD 9 s |
| Ultimate (F) | Kestrel Dive | 5 s predator state: 2x fire rate, 1.5x damage, 1.4x speed, 0.2x spread | charge: 0.35/dmg dealt, 0.1/dmg taken, +15/kill, max 100 |

**Design notes**
- The passive rewards *consistency* (sustained sub-role) instead of raw TTK:
  careful spray > burst heroics.
- Glide Burst is mobility + repositioning (assault spacing), not an escape:
  0.27 s of locked momentum, then friction resumes.
- Wingfire is close-control (pellets + slow), deliberately weaker than the
  rifle per pellet — it wins at point-blank, loses at range.
- Kestrel Dive is the payoff: a 5 s window where the vector rifle becomes an
  SMG on steroids. Charge is ~285 damage dealt (≈ 2.5 kills) so an ult lands
  mid-fight, not at match start.
- **Placeholder status:** capsule + cone visuals; VFX/SFX/animation set
  pending the asset pipeline (Phase 2 remainder).

## Hero #2 — BLITZ (Assault / Sprint)

**Role:** Assault. **Sub-role:** Sprint (speed is the identity; the gun is a
fast-ROF projectile dart SMG).

**Identity in one line:** the street-racer — always moving, never aiming
still; damage comes from closing the gap and out-turning the fight.

**Movement identity:** highest base speed on the roster (7.0) + constant
+12% speed passive + faster double dash than Kestrel. You feel *fast* even
between engagements.

| Slot | Name | Behavior | Data (blitz.tres) |
|---|---|---|---|
| Weapon | Hornet | 5-dmg dart, 14 rps, clip 42, **projectile** 24 m/s / 40 m, spread 1.2 deg | mode=projectile |
| Passive | Overdrive | constant +12% movement speed (sprint identity) | speed_mult=1.12 |
| Ability 1 (Q) | Blink Step | double 16 m/s dash, 6 m each — snappier than Kestrel's, shorter CD | count=2, speed=16, CD 5 s |
| Ability 2 (E) | Shredder Round | 10-dart 30-deg cone, 4 dmg each — mid-range shredding, no slow | pellets=10, cone=30 deg, CD 8 s |
| Ultimate (F) | Overclock | 6 s: 1.8x fire rate, 1.3x damage, 1.5x speed — the speed gun at max | charge: 0.30/dealt, 0.12/taken, +15/kill |

**Design notes**
- Projectiles (not hitscan) give dart shots *travel time*: leading targets,
  visible dodge windows, readable counters — a different combat skill from
  Kestrel's hitscan rifle.
- Lowest max HP on the roster (100): the sprint fantasy is "die less by
  never being where you were"; the armor tank covers the other end.
- DPS sits below Kestrel (57 vs 121 in the harness) on purpose — Blitz
  trades sustained numbers for the fastest effective mobility; the balance
  table (tests/test_roster.tscn) tracks the spread.

## Hero #3 — BASTION (Tank / Armor)

**Role:** Tank. **Sub-role:** Armor (mitigation identity; front-line
presence, not glass).

**Identity in one line:** the front door — you are the thing that breaks
the hit; close-range shotgun authority, flat damage mitigation, and an
ult that says *still standing*.

**Movement identity:** slowest base speed (5.0) + lowest jump; one hard
charge instead of double dash. Positioning is deliberate.

| Slot | Name | Behavior | Data (bastion.tres) |
|---|---|---|---|
| Weapon | Bulwark | 8-pellet shotgun, 6 dmg/pellet, 1.6 rps, clip 8, 12-deg spread — point-blank authority | pellets=8, mode=hitscan |
| Passive | Reactive Plating | flat 20% reduction on all incoming damage | dmg_reduce=0.20 |
| Ability 1 (Q) | Bulwark Charge | single 18 m/s, 5 m charge — a commitment, not a dodge | count=1, speed=18, CD 7 s |
| Ability 2 (E) | Quake Stomp | 8-ray 120-deg frontal arc, 6 dmg each + 35% slow 2 s — space control | pellets=8, cone=120 deg, CD 10 s |
| Ultimate (F) | Last Stand | 6 s: 1.5x fire rate, 1.4x damage, 1.2x speed — the shotgun gets loud | charge: 0.25/dealt, 0.08/taken, +20/kill |

**Design notes**
- 200 HP + 20% flat mitigation = effective 250: the only hero whose
  presence changes enemy target-priority math. Mitigation is data-only
  (passive kind ARMOR) and applies before ult charge accrues.
- The shotgun is per-pellet hitscan with wide spread: devastating at
  0-5 m, a coin-flip at 15 m — the range tax for being the door.
- Quake Stomp is the CC answer to the two assaults' dashes: slow, not
  lock (CC-lock budget tracked in the balance harness).
- Kill charge is the highest on the roster (+20): tanks trade less
  damage, so kills are their main charge engine.
## Hero #4 — MIRA (Support / Field)

**Role:** Support. **Sub-role:** Field (healing presence; the team's
heartbeat rather than a burst button).

**Identity in one line:** the heartbeat — you stand with the fight and the
team simply does not stay down; your damage is the price of that presence,
and healing is also how you fuel your own ult.

**Movement identity:** average speed (6.0), no mobility kit — positioning
is "stay near allies, slightly off the line". The field IS her kit.

| Slot | Name | Behavior | Data (mira.tres) |
|---|---|---|---|
| Weapon | Lance | 9 dmg / 8 rps / clip 30 / 0.8 deg — reliable secondary rifle | hitscan |
| Passive | Mending Presence | constant 5 HP/s tick-heal to allies within 7 m (always on) | radius=7, heal_per_s=5 |
| Ability 1 (Q) | Healing Pulse | instant 35 HP to self + allies within 8 m | radius=8, amount=35, CD 8 s |
| Ability 2 (E) | Mending Ward | 5 s field: 6 HP/s + 15% speed to allies within 6 m | CD 12 s |
| Ultimate (F) | Starfall Mercy | 6 s field: 12 HP/s + 10% speed to allies within 8 m | charge: 0.25/dealt, 0.10/taken, 0.15/heal, +10/kill |

**Design notes**
- Healing is the charge engine (charge_per_heal_dealt 0.15): a support who
  peels for the team lands her ult — support time is not dead time.
- Presence heal is a world-tick (60 Hz sim) with a per-tick cap; the heal
  HUD only labels heals >= 1 to avoid number spam.
- Mira's TTK is worse than the assaults by design (71 dps harness); her
  value is the 5-12 HP/s that changes every other hero's survivability.
## Hero #5 — PATCH (Support / Flex)

**Role:** Support. **Sub-role:** Flex (cooldown reduction + utility;
the hero who makes every cooldown tick faster).

**Identity in one line:** the wrench — nothing you carry is the star,
everything you carry comes back sooner; you are the tempo of the squad.

**Movement identity:** slightly above-average speed (6.2); Mule Shot gives
the whole squad a short speed pill — mobility as a service.

| Slot | Name | Behavior | Data (patch.tres) |
|---|---|---|---|
| Weapon | Sidekick | 7 dmg / 10 rps / clip 30 / 1.0 deg — fast SMG | hitscan |
| Passive | Toolkit | all ability cooldowns x0.8 (the flex identity) | cd_mult=0.8 |
| Ability 1 (Q) | Mule Shot | +40% speed to self + allies within 5 m for 2.5 s | CD 10 s |
| Ability 2 (E) | Field Resupply | instant full clip + 25 HP to allies within 5 m | CD 11 s |
| Ultimate (F) | Overdrive Crew | 6 s: +30% speed AND +30% fire rate to allies within 6 m | charge: 0.28/dealt, 0.10/taken, +12/kill |

**Design notes**
- FLEX passive is a global cooldown multiplier (data-only): it shortens
  Q/E/ult pacing, not movement — the "everything ticks faster" fantasy.
- Resupply is the emergency button: refill + heal in one press, the
  support answer to an empty clip at the worst moment.
- 66.5 dps in the harness — the best "secondary gun" of the two supports,
  trading raw healing for tempo (Patch is the aggressive support).

## Hero #6 — NIMBUS (Controller / Zone)

**Role:** Controller. **Sub-role:** Zone (area denial; the enemy's
footing is his problem).

**Identity in one line:** the weather — you do not out-aim the enemy, you
change the ground under their feet; slow fields, ion bolts, and a storm
that makes the whole team's guns ring faster.

**Movement identity:** average speed (6.0); the Ion Carbine is a slow,
heavy bolt — range and setup over reaction.

| Slot | Name | Behavior | Data (nimbus.tres) |
|---|---|---|---|
| Weapon | Ion Carbine | 12 dmg bolt, 4 rps, clip 24, projectile 18 m/s / 50 m, 35% slow 1.5 s | mode=projectile |
| Passive | Static Charge | +8% fire rate while an enemy is within 10 m | radius=10, rate_mult=1.08 |
| Ability 1 (Q) | Static Field | 3 m slow zone (30% slow) at 12 m, lasts 4 s | CD 11 s |
| Ability 2 (E) | Ion Barrage | 6-bolt 40 deg cone, 8 dmg each + 30% slow 1 s | CD 9 s |
| Ultimate (F) | Ion Storm | 6 s: 1.6x fire rate, 1.5x damage, 1.25x speed, 0.8x spread | charge: 0.30/dealt, 0.10/taken, +12/kill |

**Design notes**
- The only pure Controller: his kit is slow + field + a damage spike, not
  healing. He denies ground (Static Field) and punishes positioning.
- Static Charge passive is the zone identity: the closer the fight, the
  faster he shoots — rewarding holding the corner of a lane.
- 48 dps harness; his TTK is slow (2.08 s) — the controller does not win
  the 1v1 TTK race, he wins the fight by making the enemy sluggish.
## Roster plan (Phase 3 fills #2–#6)

2 Assault, 1 Tank, 2 Support/Utility, 1 Controller (directive §6).
Identities land here as each hero is built.

| # | Hero | Role/Sub-role | Status |
|---|---|---|---|
| 1 | Kestrel | Assault / Sustained | built + tested |
| 2 | Blitz | Assault / Sprint | built + tested (projectile weapon) |
| 3 | Bastion | Tank / Armor | built + tested (pellet shotgun, mitigation) |
| 4 | Mira | Support / Field | built + tested (heal/field pipeline) |
| 5 | Patch | Support / Flex | built + tested (boosts + cooldown reduction) |
| 6 | Nimbus | Controller / Zone | built + tested (projectile slow + ground zones) |
