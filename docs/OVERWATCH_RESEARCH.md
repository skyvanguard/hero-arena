# Overwatch — Research Report

**Status:** Phase 0 research (compiled 2026-09-02)
**Method:** Overwatch Fandom wiki (actively maintained; MediaWiki API), official Blizzard news (overwatch.blizzard.com), r/overwatch sampling 2024–2026 (Arctic Shift archive). We study *systems and community reception* — no characters, maps, names, or assets are copied.

---

## 1. Current State of Overwatch (Sept 2026)

- **Overwatch 2** (F2P, released 2023-08-10 on PS4/PS5/Windows/Xbox/Switch) was **rebranded back to "Overwatch"** in early Feb 2026 as part of a "forever game" strategy.
- **50+ heroes** on the roster; hero releases still frequent (2025–2026 additions include Anran, Venture, Vendetta, Juno, Wuyang, Jetpack Cat, Hazard, Domina, Mauga-as-mythic-cosmetic-hero line).
- 2026 season line: **Reign of Talon** — S1 "Conquest" (Feb 2026, introduced sub-roles), S2 (summit/climb theme), S3 "Into the Tiger's Den" (midcycle "Claws Out"), S4 "Heroes of Busan" (Aug 2026, BlizzCon-adjacent).
- Active development themes: Battle Pass revamp (Aug 2026), Quick Play Hacked experiments (6v6 "Flex Queue", July 2026), Weekly Recall data-driven retrospectives, Fortnite crossover.

---

## 2. Hero Architecture (what to learn)

### 2.1 Role system

- Three roles: **Tank / Damage / Support** (OW1's Offense/Defense split was merged into Damage after ~2 years — lesson: sub-roles give specificity without queue complexity).
- **Role Queue** (primary ranked mode): 1 Tank / 2 Damage / 2 Support per team; players lock to one or more roles when queueing; **separate rank per role** in Competitive.
- Role descriptions are identity statements: "If you're a tank, you lead the charge", etc. — copy this tone for our hero marketing.

### 2.2 Sub-Roles (introduced 2026-02-10, "Reign of Talon" S1)

Ten sub-roles with **their own passive abilities** (this is the exact pattern our directive's §9 wants):

| Role | Sub-role | Identity | Passive (examples) |
|---|---|---|---|
| Tank | **Bruiser** (Brawl) | Face enemy tank/DPS up close, soak damage | Damage reduction (vs ≤1.5× headshot weapons), move-speed bonus |
| Tank | **Initiator** (Dive) | Take down key targets, mobility + burst | 50 self-heal (1 s, 5 s CD) after using a movement ability |
| Tank | **Stalwart** (Barrier) | Most varied: poke (Sigma, Domina) & brawl (Reinhardt, JQ); hold space | (role-specific barrier sustain) |
| Damage | **Flanker** (Brawl/Dive) | Burst movement, melt low-HP targets | Health packs buffed (+125 small/+300 large); some flankers +0.5 m/s base speed |
| Damage | **Recon** (Dive/Poke) | Flight heroes, distance + info | (recon/utility tilt) |
| Damage | **Sharpshooter** (Poke) | Long-range, hold angles, headshot focus | Per-weapon charge/heat-reduction table (data-driven!) |
| Damage | **Specialist** (Brawl/Poke) | Jack-of-all-trades or area denial (Mei, Junkrat, Bastion, 76) | (versatility tilt) |
| Support | **Medic** | Healing weapon on primary fire, damage/boost on secondary | (healing focus) |
| Support | **Survivor** (Dive/Poke/Brawl) | Strong mobility, squishy (Juno, Wuyang, Brigitte) | (mobility sustain) |
| Support | **Tactician** (Dive/Poke) | Heals + debuffs/buffs (Zenyatta, Ana, Lúcio, Jetpack Cat) | (utility tilt) |

Notes:

- Sub-role passives are **small, always-on, identity-defining** — not power spikes. They don't appear in the arcade "Stadium" mode.
- Sub-roles were **announced at a Spotlight, then shipped** — a good rollout pattern for us (teaser → data → ship).
- Archetypes (Brawl/Dive/Poke) cut across sub-roles — a second taxonomy layer. Our 6-hero roster should be explicitly placed in both grids.

### 2.3 Ultimate design

- **Ultimate charge earned from dealing damage and healing** (combat-driven, not time). Ultimates are the hero's signature moment; many are "two-tool" (e.g., swap fire modes) or "state-change" (invisibility, transformation, summon).
- OW's 2024 **Pickable Passives** Quick Play Hacked experiment directly produced the **Perks** system — evidence that community choice experiments de-risk new mechanics. We should run similar small experiments (e.g., perk choice screens) in our Phase 7.

### 2.4 Perks system (Season 15 "Honor and Glory", late 2024)

The in-match progression system our directive's §8 refers to:

- Heroes start a match at **level 1**; reach **level 2 → pick 1 of 2 minor perks**; **level 3 → pick 1 of 2 major perks**.
- **Minor perks** = small upgrades (cooldown reductions, etc.); **major perks** = impactful, can change ability function.
- Progress = damage dealt, eliminations, healing (same math as ult charge). **No passive gain**; gain rate **scales from 3 min to 7 min, up to 2×** — so in a 3–8 min match you realistically get minor + maybe major.
- **+15% bonus progress** for eliminating an enemy at a higher perk level than you (rewards engagement with "evolved" opponents).
- Same restrictions as ult charge (no charge from ult damage, no self-damage, tank role passive reduces gains).
- **Not available in Stadium** (arcade) — perk system is a *competitive* feature.
- Perks are **per-hero** (switching heroes resets, but previously unlocked perks stay on that hero).
- Community reception: broadly positive as "choice" (validated by the 2024 experiment); ongoing discussion of which perks should be base-kit (2026 threads).

**Design takeaways for us:**
- Two pick moments per match fits 3–8 min matches perfectly (don't go to 3+ levels — that's a 15-min-match system).
- Choice > straight numbers: "projectile speed vs reload speed" style tradeoffs (exactly the directive's §8 example, proven by OW).
- Late-match ramp means strong finishes matter — keep the ramp window (3–7 min) but tune to our 3–8 min target.
- Data-driven perk definitions are trivially extensible (see our ARCHITECTURE.md ability/perk model).

---

## 3. Matchmaking (the system we must do better than)

From the wiki (current, post-2024-patches) + community:

### 3.1 Mechanism

- Hidden **MMR** per player, per role, per playlist; treated as a bell-curve data point (0 = center). **Visible rank tiers/divisions do not affect matchmaking** (only MMR does); since rank decay was removed, visible rank ≈ MMR.
- Match construction optimizes: skill (role-aligned MMR), queue time, ping (regional proximity), **group size (4s vs 4s)**, **group wideness** (match similar internal rank spreads within parties), and — since the **Oct 15 2024 patch — "grouping advantage"** in high ranks (parties get extra scrutiny).
- **Role Delta**: when exact MMR parity is impossible, minimize per-role MMR deltas, **tank prioritized** — "in 80% of matches the tank MMR difference is < 1 division."
- **Win-probability model**: competitive matches guarantee ≥ 40% win prob for the weaker team; 80% of matches fall in 45–55%; ~half of narrow matches in 49–51%. Model is calibrated against actual results.
- MMR updates on **match result only** (no stat-based MMR), scaled by: relative MMR, account age/frequency of the mode (smoothing for new accounts).
- **Avoid list** respected until queue times get long.

### 3.2 Community reception (recurring complaints, 2024–2026)

- **Constant matchmaking grumbling**: "Wtf matchmaking on s12" (2024), "Wtf matchmaking" (2025), "Broken matchmaking" (2026), "What is wrong with matchmaking??" (2026) — it is *the* persistent OW complaint, even with a sophisticated system.
- **Party vs solo**: "Why are duo queues the most toxic in the game?" (2024); "How was I able to duo plat 1 with gold 4 without being a wide queue?" (2026); "What's the point of grinding ranked if matchmaking and bans punish the wrong people?" (2026).
- **Bot suspicion**: "Was our Zen a bot?" (2025) — even OW gets bot accusations when MMR is opaque.
- **Streaks & volatility**: "Lost 9 ranked games in a row" (2025); fast matches amplify perceived imbalance (Blizzard's own 2026 Director's Take names "stomps" and "early-game ultimate economy" as perception drivers).
- **Transparency gap**: the system is sophisticated but *invisible*; players experience it as opaque. OW publishes data retrospectives (Weekly Recall) — we should do better: show the player *why* they were placed (region, ping, party composition, skill band), per directive §17.

### 3.3 Queue-time / format experiments (2026)

- **6v6 "Flex Queue" Quick Play Hacked** (July 2026, two weekends): hybrid of 2-2-2 role queue and open queue — guaranteed 1 Tank + 3 Flex DPS + 2 Support; any Flex DPS can dynamically swap to Tank in-match (only one at a time). Stated goals: fewer tank-queue waits, reduce tank-outcome dominance, reduce stomps/volatility, keep dynamic teamfights.
- Explicit caveat: experiments may feed mode tweaks rather than change the main format.
- **Lesson for us:** OW is *searching for* small-team/low-pressure alternatives because 5v5 is fragile. Our 3v3-first bet matches where the market is heading; our bot-fill strategy (directive §16) is our answer to their queue-time problem.

---

## 4. Modes & Maps

- Primary modes: **Escort (push), Control (hold), Assault/Conquest (capture)**, plus **Stadium** (2025 arcade mode with items/powers instead of perks) and **Quick Play Hacked** (experimental sandbox).
- **Map voting is not standard in competitive** (maps rotate; community asks for it) — opportunity for us (directive §24).
- Map design: mid-scale, multi-lane with verticality, flank routes, objective space sized for 5v5. For our 3v3, maps should be *smaller* (T3-scale), with 2–4 lanes, readable sightlines, and objective clarity at mobile distances.
- Regional **ban rates** are published in data retrospectives — another transparency win for us.

## 5. Progression & Monetization

- **Battle Pass**: 80 tiers free + premium; **Revamp (Aug 11, 2026)**: broken into **five 8–10 tier "tracks" the player chooses the order of**, each ending in a Legendary or Epic skin; premium adds one **"Tier Hack"** charge (Sombra-themed) to swap any track reward for a curated past skin. Philosophy: *"Personalization and Player Agency."*
- **Hero unlocks**: F2P grind, per-hero XP, hero-specific cosmetic **Hero Pass**es (paid), shop (Luna/credits), events (Lunar New Year, Pride, etc.), mythic cosmetics (2/season; community pushes "2 mythic *weapons* per season").
- No gameplay paywall: all heroes full-power at unlock (the model our directive §7 demands).
- Complaints: grind length, mythic placement, event challenge friction, loot-box legacy (OW1) — OW2 removed loot boxes for heroes (big community win; "forced challenges" remain a gripe).

**Takeaways:**
- All-heroes-unlocked-full-power is the community expectation for hero shooters — keep it.
- Track-based/agency-pass design (choose your track order) is a better default than linear 80-tiers for a small-team game with fewer players (less FOMO pressure).
- Mythic-tier cosmetics create the "dream reward" cadence without touching gameplay.

## 6. Combat & Feedback

- Hitscan + projectiles coexist per hero; headshot multipliers; overhealth (armor) for tanks; healing reduction as a **global passive** (data-driven exclusion lists for which abilities ignore it).
- Damage feedback: hitmarkers, damage arrows, killfeed, ultimate-ready fanfare, directional indicators — the "player must understand what happened" bar our directive sets is OW's bar.
- Cooldowns, ammo/reloads per weapon; weapon swap times; per-hero mobility (blink, roll, dash, flight) defines the hero, not just the weapon.
- **Aim assist** exists and is controversial; OW's is modest. Our mobile ladder (off/low/med/high + projectile-speed setting) should be more explicit and tunable than OW's.

## 7. What Overwatch Proves (and What to Fix)

| Proven (adopt) | Broken (fix) |
|---|---|
| Role + sub-role identity system with small always-on passives | Opaque MMR → perpetual matchmaking distrust |
| Combat-driven ult charge | Party-vs-solo friction (no visible mitigation) |
| Perks = in-match choice, 2 levels, 2 options each | No offline/bot destination for solo players |
| All heroes free at full power | 5v5 fragility (stomps, tank dominance, queue times) |
| Track/agency Battle Pass | Linear-grind FOMO in events/challenges |
| Data-driven balance (perks, healing-reduction tables, role-delta) | No community server/self-hosting; no modding |
| Fast feedback loop (Weekly Recall data) | Arcade/competitive split confuses where features land |

---

## 8. Source List

- Overwatch Fandom wiki (MediaWiki API, active through Feb 2026 patch pages): *Roles, Sub-Roles, Global Passive Abilities, Perks, Matchmaking, Ultimate ability, Overwatch 2, Battle Pass* — https://overwatch.fandom.com/
- Official news (overwatch.blizzard.com): *Director's Take: Battle Pass Revamp* (2026), *Director's Take: Future Formats* (2026, Quick Play Hacked / Flex Queue 6v6), Reign of Talon S1–S4 announcements, Weekly Recall posts.
- r/overwatch 2024–2026 post sample via Arctic Shift (758 posts sampled across 32 months; keyword-filtered for matchmaking/queue/MMR/party/perks/5v5/sub-role/ranked/bots/rebrand).
- Polygon (via wiki citation): Overwatch 2 5v5 changes (2021), name-change explainer (2026).

*Systems studied, not copied. All hero names, maps, and art belong to Blizzard/Activision.*
