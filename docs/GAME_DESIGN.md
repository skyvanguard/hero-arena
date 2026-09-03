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

## Roster plan (Phase 3 fills #2–#6)

2 Assault, 1 Tank, 2 Support/Utility, 1 Controller (directive §6).
Identities land here as each hero is built.
