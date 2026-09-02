# T3 Arena — Research Report

**Status:** Phase 0 research (compiled 2026-09-02)
**Method:** primary-source review — official site & store listings, App Store / TapTap reviews, r/T3Arena (via Arctic Shift archive, 1,200+ posts 2022–2026), T3 Arena Fandom wiki (MediaWiki API), in-game screenshots. No proprietary assets or code were copied; this is analysis only.

---

## 1. Product Overview

| Attribute | Value |
|---|---|
| Full name | T3 Arena ("T3" branding, XD) |
| Developer | XD Entertainment Pte Ltd (Singapore) |
| Genre | Third-person hero shooter ("MOBA shooter" in its own marketing) |
| Platforms | Android (Google Play: com.xd.t3.global), iOS (id1602814337), TapTap (219804) |
| Beta | March 2022 (Season 0 "Gear Up", 2022-03-17) |
| Global launch | ~May 2022 (Season 1 "Glory Begins", 2022-05-25) |
| Team size | 3v3 (original identity), 5v5 added later and now the marketed format ("5v5 MOBA Shooter") |
| Match length | 2–5 min advertised ("3–5 min gameplay"), 6-second respawn |
| Hero count | "nearly 30" (store copy); Fandom wiki lists 31 playable heroes at its last update |
| Ratings | 4.8/5 (81K ratings, App Store US), 8.9/10 (11K ratings, TapTap) |
| Current state (2026) | Effectively in maintenance/decline: no meaningful content updates, community reports crashes, ~4.4K Reddit subscribers, "the game is dead" sentiment |

### 1.1 What made it popular (the "spirit" to preserve)

- **Stylized, colorful, readable 3D** — cel-shaded hero silhouettes (e.g., rock-singer DPS with a golden guitar, white-tiger tank with a big round shield) are instantly legible. This readability was a genuine differentiator vs. photoreal mobile shooters.
- **Fast, casual entry** — "RUN & GUN FUN" positioning; easy-to-learn, hard-to-master; short matches; 6-second respawn-to-frontline.
- **Auto-Fire** — a signature accessibility mechanic: "Just aim at your target and let your weapon do the rest." It let non-shooter players fight while still rewarding aim. (A double-edged sword: competitive players resented it — see §6.)
- **Hero variety with distinct identities** — 30+ heroes with unique weapons/abilities; community fan art revolves around specific characters (Lacia, Hua Ling are fan favorites; "my Marvel Rivals before Marvel Rivals" is a recurring description).
- **3v3 identity** — the community explicitly credits 3v3 with making "every character able to take on every other character."
- **Party + voice chat**, clubs, seasons, event modes — standard live-service furniture done acceptably.

---

## 2. Core Gameplay Mechanics

### 2.1 Controls (from the Fandom Beginner Guide)

- Left-half virtual joystick = movement; right-half drag = aim/camera.
- Jump button lower-right; reload button; ability icons on the right side of screen.
- Health + armor bars at the bottom of the screen.
- **Health auto-regens slowly "up to a certain extent" after taking damage; full recovery requires Health Potions spread across the map.** (Important design detail: map pickups matter.)
- Ultimate abilities are **charged by hitting enemies** (not time-based); active abilities are time-based cooldowns.

### 2.2 Hero kit structure (from hero pages: Aleta, Fade, etc.)

Each hero has:

1. **Primary weapon** (unique per hero, e.g., Aleta: "Dual Auto-Pistols — fast but inaccurate, close range"; Fade: "Quantum Cannon — space-class shipboard artillery, powerful shells").
2. **Passive ability** (e.g., Aleta "Double-Jumper": tap jump mid-air to double-jump; Fade "C-Conversion": damage taken reduces dash cooldown).
3. **Active ability** (1–2, cooldown-based; e.g., Aleta "Holo-Dash": quick dash).
4. **Ultimate** (charge-based; some heroes have **two-phase ultimates** — "Ultimate 1/2" and "2/2"; e.g., Aleta's Decoy Bomb → Holo-Burst combo. Second Ultimates were an unlockable item in the original economy).

Kit shape is close to: weapon + passive + 1–2 actives + (1–2 phase) ultimate. This is simpler than Overwatch's offense/defense/ult trio, and it works for mobile.

### 2.3 Economy & power-grind elements (problems to fix)

- **Hero rarity tiers**: Rare / Grand / Epic / Mythic / All-Star. Heroes dropped from "Rumble Boxes" (luck-based), later changed to **Hero Tickets** (guaranteed purchase). Arcade/Battle-pass heroes (e.g., Vincent, Ono) were excluded from ticket pool.
- **Hero Glory Level** ("hero points" = per-hero rank/level, up to ~70): leveling a hero unlocked stronger **passives and second ultimates** — i.e., **newly unlocked heroes were weaker than levelled heroes** ("Hero Level 1 → weak version → grind → strong version"). This is exactly the paywall/grind pattern the project directive forbids.
- **Skins** priced at ~400 gems; free season pass earned ~40 gems per season; "lucky draw" ~400 gems per skin (App Store review, 2023). Community: "pay to win characters that you literally have to spend money like a lot to even play them."
- **Season Pass**: 70 tiers, free + premium track, cosmetics + progression items; each season ~2 months.

### 2.4 Progression systems

- **Hall of Fame** (global trophy rank from casual/"Trophy Games").
- **Ranked** with tiered ranks: ... Diamond → Master → Superstar (confirmed in lobby screenshots; rank points e.g. 1597 = Diamond II). Ranked is role/team-size aware; "Ranked Party Rules" exists in the party UI.
- **Clash** — 3v3 elimination, **no respawns**, best-of-5 rounds, "heroes used in a winning round cannot be used for the rest of the match" (per-hero lock-out adds draft depth). This was a well-received ranked mode.
- **Clubs** (guilds) with club orders; friends/party system with in-lobby voice chat.

---

## 3. Game Modes & Maps (Fandom wiki)

| Mode | Rules | Maps (count) |
|---|---|---|
| Team Deathmatch | 3v3, first to 20 KOs | Crossroads, Octopolis, Penthouse Gallery, Service Station, Bravewalk Kingdom (5) |
| Crystal Assault | Defend your crystal, destroy enemy's; higher crystal HP at timeout wins | Terminal Station, Energy Canyon (2) |
| Free-for-All | Solo, first to 12 KOs | Gym Park, Cuenca del Piñata, Space Station Relight (3) |
| Control | Capture & hold to 100% | Elephant Istana, Arctic Express, Crispy County (3) |
| Payload Race | Each team pushes its own payload | Warehouse SODA-1 (1) |
| Payload Escort | Attackers push, defenders delay | Brauersdock (1) |
| Coin Rush | Limited-time event: collect coins, drop them on KO | 1 |
| Clash | 3v3 no-respawn BO5 elimination (ranked) | — |
| Practice Mode | Training ground, no goals | — |
| Private Games | Custom lobbies via Lobby ID | — |

Observations:

- Maps are **small, compact arenas** (fits 2–5 min matches) — good instinct; several themed (space station, canyon, istana, kingdom).
- Mode diversity was a launch strength ("2–5 min per match, several different modes"), but **only some modes/maps were in ranked**, which narrowed competitive play.
- No map voting; no community/LAN hosting (private lobbies only, server-hosted).

---

## 4. Progression Timeline (from wiki Version History + community)

1. **2022-03 (beta)**: launch as a Brawl-Stars-like 2–5 min MOBA shooter; per-hero rank grind to buy skins; no mid-match hero swaps; Rumble Boxes.
2. **2022-05 (launch)**: Season 1; 70-tier battle pass; 6-sec respawn design.
3. **2022-07**: first balance patch cycle (e.g., Johnny Jet base HP 3,700 → 4,000; Labula weapon damage 800 → 900; Diggy leap damage 860 → 1,100 with 7%/m decay) — note the **thousands-scale HP pool** (mobile "big number" design).
4. **2022-09/11**: ranked + **hero roles** announcement ("Arena News — Ranked, Hero Roles, More"); community begins OW-comparisons.
5. **2023–2024**: shift toward 5v5; "radical gameplay changes… not once but twice" (community); Clash mode era; game "turned more into OW" (community).
6. **2024-06**: "Sell the game" top post — population collapse visible.
7. **2025-07**: "32+ mins to enter ranked is crazy" — queue collapse.
8. **2026**: updates effectively stop; "destined to fail" post-mortems; 200+ ms (occasionally 20,000+ ms) ping complaints; wall-hack/anti-cheat complaints; game still runs but community is in mourning mode.

Community diagnosis (verbatim, r/T3Arena, 2026-05 post "No, the devs didn't abandon this game for no reason"):

- "Game died when they switched to 5v5. It just became a crap clone instead of something unique. **The 3v3 balance made every character able to take on every other character.** The game was a blast. The 5v5 balance was just a crap rock/paper/scissors that was inferior to what it was trying to copy."
- "It's actually less of a 50/50 and moreso a 90/10 since when [low regional population] happens everyone in the [high] bracket gets placed against the lower bracket (diamond)."
- "The main reason is ping 200 to 160+ always and sometimes 20000+ ping."
- "if they had released the game for free on pc or console and have cross platform support I feel like more people would've gave it a try."
- "Radical gameplay changes not once but twice… Problem with the rank focus is that only some maps and modes was in rank."

---

## 5. Monetization (observed)

- F2P + gems (premium currency) + T-Coins (soft currency) + Power Cores (hero upgrade material).
- Rumble Boxes (luck), Hero Tickets (deterministic, post-change), Season Pass (free + premium, 70 tiers), Subscription (loyalty program), shop offers, lucky draws, event modes (Coin Rush), hero exclusivity (some heroes only via pass/arcade).
- Skins are the main premium; no gameplay paywall *after* hero unlock in the final design — but **hero acquisition and hero level grinds were the paywall**.
- Ads: no in-game ads observed (F2P, mobile-first).

---

## 6. Community Complaints (ranked by frequency/severity)

1. **Population decline / matchmaking queues** — the defining problem. Long queues (32+ min ranked), then bot-filled matches, then "are all the players bots?", then exodus. Regional server population too small per region → wide skill spreads.
2. **Weak/absent bot behavior** — bots used as queue filler were noticed and resented ("They seem bot like"), but with no offline mode or dedicated bot matches, players had nowhere to go.
3. **Loss of 3v3 identity** — 5v5 pivot broke balance and identity; the 3v3 meta is what fans loved.
4. **Ping / server quality** — 160–200+ ms typical for many players, spikes to 20,000+ ms; no regional choice UI; no self-hosting.
5. **Balance whiplash** — "radical gameplay changes… twice"; hero power creep; per-hero level grinds changing hero power; ultimates tied to game mode ("when you forget to switch your ultimate before switching game modes").
6. **Monetization friction** — 400-gem skins, box luck for heroes (pre-ticket era), "P2W characters" perception, free pass earning far too little.
7. **Update cadence collapse** — after 2024, updates stopped; community felt abandoned ("Where did the devs go?").
8. **Anti-cheat / hacks** — wall hacking reports in 2026; mobile anti-cheat is hard (relevant to our authoritative-server plan).
9. **Technical issues** — crash-on-launch, download stalls after updates (2026), low-graphics perception at launch ("Gotta love low graphics").
10. **Accessibility vs. competitiveness tension** — Auto-Fire made it accessible but was resented in competitive play (no clear toggle/settings story).

## 7. Community Favorites (signals for design)

- **Heroes**: Lacia (repeated fan-art), Hua Ling (fan art + "best Hua Ling in South Korea" post), Diggy & Johnny Jet ("a couple"), Ruby, Aleta (deep-mechanics guide), Gloria (shotgun; "feels kinda weak" — balance), Fade & Jabali (top vanguards per a 2023 review), Neon & Chemist (healers), "Demion" + "the healer with the drone" (2026 comment).
- **Modes**: Clash (no-respawn elimination) and the 3v3 identity; TDM as the default.
- **Presentation**: stylized art, chibi avatars, colorful UI, club/friend social features, voice chat.
- **Meta description**: "my Marvel Rivals X overwatch experience" (TapTap, 2026) — the community itself positions it as the mobile hero-shooter.

---

## 8. Implications for Our Project

Direct design consequences (mapped to the directive):

1. **3v3 is the core identity — architecturally, not as a default setting.** T3 proved 3v3 makes every player matter and keeps balance tractable; 5v5 broke it. Our engine must *support* 1v1–6v6 but *design* for 3v3 (map scale, ability tuning, match length).
2. **Bots must be a first-class, fun destination** (offline matches, training, challenges, difficulty tiers), not a queue-filling embarrassment. T3's bots were the placeholder; ours are a feature (§13 of the directive).
3. **Never lock gameplay behind hero level.** Unlock = 100% competitive. Cosmetic progression only. (T3's Glory Level/Power Core grind is the anti-pattern.)
4. **Hero acquisition must be fair.** No luck-boxes for gameplay power. If there are boxes at all, they contain cosmetics.
5. **Auto-Fire lesson: accessibility systems need settings.** Keep a strong aim-assist/accessibility ladder (off/low/med/high, projectile speed, etc.) instead of a binary gimmick that splits the community.
6. **Matchmaking must have a bot-fill strategy with transparency** — strict → relaxed → bot-filled, with the queue strategy visible to the player (region, ping, party composition, approximate skill).
7. **Regional servers + low latency for LATAM/Paraguay** were a real T3 pain point; client must show Region/Ping/Server, and the architecture must allow community-hosted servers to fix it.
8. **Authoritative server** kills the wall-hack class of complaints and enables dedicated/community servers.
9. **Two maps first, compact and readable**, mode-per-map flexibility (like T3's per-mode map pools) but with *all* maps available in *all* modes to avoid "only some maps are in ranked."
10. **Short sessions preserved**: 3–8 minute matches, 5–10 s respawn, instant re-queue.
11. **Update cadence is a product feature.** Open source + community-server architecture is the answer to "devs disappear" (our §20/§31 goals).
12. **Health/armor design note**: T3's partial-regen + map potions is a proven mobile pattern — adopt regen-to-cap + pickups, not full regen.
13. **Perks that evolve in-match** (OW-style, which T3 fans already compare to) fit the 3–8 min match window well: one level-up per match is enough to feel progression without grind.
14. **Ultimate charging from combat** (T3) vs. time-based: keep combat-driven ult charge (rewards aggressive play, no idle charging) — and charge across modes/heroes consistently (fix T3's mode-specific ult complaint).

---

## 9. Source List

- Official site: https://t3.xd.com/ (Nuxt/SSR; store links, hero showcase videos, SEO meta "5v5 MOBA Shooter")
- Google Play: com.xd.t3.global · App Store: id1602814337 · TapTap: https://www.taptap.io/app/219804 (descriptions, 4.8★/81K, 8.9/10/11K, reviews)
- T3 Arena Fandom wiki (MediaWiki API): Heroes, Beginner Guide, Modes, Maps, Fort, Fade, Aleta, Seasons, Version History & Info — https://t3-arena.fandom.com/
- r/T3Arena full 2022–2026 post scan via Arctic Shift API (1,213 posts sampled; top 45 by score; comment threads on the 2026 "destined to fail" post, the "32+ mins ranked" post, "Are all the players bots?", anticheat threads)
- In-game lobby screenshot from community post (ranked tiers, hero levels, party UI, visual style)

*All facts above are from public web sources reviewed 2026-09-02. No T3 Arena source code or assets are used in this project.*
