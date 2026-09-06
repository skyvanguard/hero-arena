class_name MMConfig
extends Resource
## D28 (matchmaking v2): the data-driven matchmaking parameters.
##
## The 4-stage queue (strict -> skill -> region -> botfill) and its two
## D28 additions live here, not in the lobby server (no magic numbers):
##
## - STAGE WINDOWS (seconds of real queue time, strictly increasing):
##   strict_until / skill_until / region_until; after region_until the
##   queue is in BOTFILL stage (fill the emptiest match first).
## - WIN-PROBABILITY MODEL (the skill stage): the lobby keeps a per-match
##   skill ledger (ratings of the players it assigned, decayed
##   proportionally when the match server reports fewer humans). A party's
##   join is projected as EVEN SPLIT (the lobby does not see team
##   assignment - the match server does; bots fill the rest at the
##   neutral bot_skill) and the join is FAIR when the projected average
##   team delta stays within max_team_delta. win_prob() turns a signed
##   average delta into a side-A win chance (logistic): 0.5 at parity,
##   monotone. The SKILL stage admits only fair candidates; the REGION
##   stage prefers them in the sort. Unknown skill (a v1 client's 0 or an
##   empty ledger) is treated as neutral - exactly the v1 behavior.
## - GROUPING: a party is projected as a block (its size and its average
##   rating), so a big group's advantage is balanced against the other
##   team + neutral bots before it joins; parties still only enter when
##   the whole group fits (v1 rule).
##
## LATAM priority is the Regions table order (core/matchmaking/regions.gd)
## - the STAGE 3 widen order runs LATAM regions before NA/EU/ASIA - this
## config only sizes the windows and the fairness band.

const CONFIG_PATH := "res://content/matchmaking.tres"

## Stage 1 (strict, same region, any skill) window, seconds.
@export var strict_until := 5.0
## Stage 2 (skill: same region, fair joins only) window, seconds.
@export var skill_until := 15.0
## Stage 3 (region: full widen order, fair preferred) window, seconds;
## after this the queue is in BOTFILL stage.
@export var region_until := 60.0
## Kept for the D21-era vote docs: unused by the queue (the region stage
## uses region_until); preserved so old configs/loads do not shift fields.
@export var skill_window := 400.0
## Fairness band: max |projected average team delta| for a FAIR join.
@export var max_team_delta := 250.0
## Neutral rating used for bot-filled seats in the projection.
@export var bot_skill := 1000.0
## Logistic steepness for win_prob (per rating point of average delta).
## 0.004: a full-band delta (250) maps to ~73% for the stronger side.
@export var skill_k := 0.004

static func load_config() -> MMConfig:
	var r := ResourceLoader.load(ModLoader.resolve(CONFIG_PATH), "", ResourceLoader.CACHE_MODE_REUSE)
	if r is MMConfig:
		return r
	return MMConfig.new()

## Side-A win chance for a signed average skill delta (A - B): 0.5 at
## parity, monotone in delta, ~1 / ~0 for large deltas.
static func win_prob(k: float, delta_avg: float) -> float:
	return 1.0 / (1.0 + exp(-k * delta_avg))

## Even-split projection of a party join. Returns [avgA, avgB, delta] with
## A = the side the incoming party plays on. `ledger_sum/_humans` is the
## match's known human skill (the party is NOT part of it).
static func team_projection(ledger_sum: int, ledger_humans: int, party_size: int,
		party_skill_sum: int, bot_skill: float, team_size: int) -> Array:
	var h_total: int = maxi(ledger_humans + party_size, 1)
	var side_a_humans: int = int(ceil(float(h_total) / 2.0))
	var side_b_humans: int = h_total - side_a_humans
	var on_a: bool = party_size <= side_a_humans
	var rest_a: int = (side_a_humans - party_size) if on_a else side_a_humans
	var rest_b: int = side_b_humans if on_a else (side_b_humans - party_size)
	var ledger_avg: float = float(ledger_sum) / float(ledger_humans) \
			if ledger_humans > 0 else bot_skill
	var bots_a: int = maxi(team_size - (party_size + rest_a), 0)
	var bots_b: int = maxi(team_size - rest_b, 0)
	var avg_a: float = (float(party_skill_sum) + float(rest_a) * ledger_avg
			+ float(bots_a) * bot_skill) / float(team_size)
	var avg_b: float = (float(rest_b) * ledger_avg + float(bots_b) * bot_skill) \
			/ float(team_size)
	return [avg_a, avg_b, avg_a - avg_b]

## Fairness gate for the SKILL stage (and the REGION sort preference).
## Unknown skill on either side (v1 clients, empty ledger) = neutral = fair.
static func fair_join(cfg: MMConfig, ledger_sum: int, ledger_humans: int,
		party_size: int, party_skill_sum: int, team_size: int) -> bool:
	if ledger_humans <= 0 or party_skill_sum <= 0:
		return true
	var p: Array = team_projection(ledger_sum, ledger_humans, party_size,
			party_skill_sum, cfg.bot_skill, team_size)
	return absf(float(p[2])) <= cfg.max_team_delta
