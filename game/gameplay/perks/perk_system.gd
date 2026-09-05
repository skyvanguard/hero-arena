class_name PerkSystem
extends Node
## D25 — in-match perks (Phase 7). Server-authoritative: XP accrues from the
## world's own events (hit / kill / heal), level-ups roll two role-filtered
## choices deterministically (seeded), picks validate and apply to the
## character's modifier pipeline. Bots pick through the same entry point
## (controller interface), on a small delay so a human watching a bot sees
## the cards before they vanish. Headless-safe: nothing here renders; the UI
## listens to the "perk_level_up" / "perk_picked" world events.
##
## World events this system consumes: "hit" {target, source, amount},
## "kill" {killer_ch, victim_ch, headshot} (entity refs added in D25),
## "heal" {target, source, amount}.

## Bots wait this long after a level-up before picking (deterministic).
const BOT_PICK_DELAY := 0.75

var world_: World = null
var pool: PerkPool = null
var seed_base := 0

var _xp: Dictionary = {}        # ch -> float
var _level: Dictionary = {}     # ch -> int (1 = base)
var _pending: Dictionary = {}   # ch -> Array[PerkData] (2, or 1 if exhausted)
var _picked: Dictionary = {}    # ch -> Array[PerkData]
var _pending_at: Dictionary = {}  # ch -> world time of the level-up

func setup(w: World, p: PerkPool, seed: int = 0) -> void:
	world_ = w
	pool = p
	seed_base = seed
	if w != null:
		w.world_event.connect(_on_event)
	for ch in w.characters:
		_register(ch)

func _register(ch: CharacterEntity) -> void:
	if _xp.has(ch):
		return
	_xp[ch] = 0.0
	_level[ch] = 1
	_picked[ch] = []

func _on_event(name: String, data: Dictionary) -> void:
	if pool == null or world_ == null:
		return
	match name:
		"hit":
			var src: CharacterEntity = data.source
			var tgt: CharacterEntity = data.target
			if src != null and src != tgt and src.alive:
				grant(src, float(data.amount) * pool.xp_per_damage)
		"kill":
			var killer: CharacterEntity = data.get("killer_ch", null)
			if killer != null:
				grant(killer, pool.xp_kill + (pool.xp_headshot_bonus if bool(data.headshot) else 0.0))
		"heal":
			var hsrc: CharacterEntity = data.source
			var htgt: CharacterEntity = data.target
			if hsrc != null and hsrc != htgt and hsrc.alive:
				grant(hsrc, float(data.amount) * pool.xp_per_heal)

## Authoritative XP grant + level check (also the test entry point).
func grant(ch: CharacterEntity, amount: float) -> void:
	if ch == null or pool == null or world_ == null:
		return
	_register(ch)
	_xp[ch] = float(_xp[ch]) + amount
	_check_level(ch)
	_maybe_bot_pick(ch)

func _check_level(ch: CharacterEntity) -> void:
	while true:
		var lvl: int = int(_level[ch])
		if lvl >= 3:
			return
		var thr: float = pool.level2_at if lvl == 1 else pool.level3_at
		if float(_xp[ch]) < thr:
			return
		_level[ch] = lvl + 1
		_roll_choices(ch)

## Two distinct seeded choices from the role-filtered tier pool (v1: no
## duplicate offers; if the pool is exhausted the level-up offers nothing
## and the character simply carries on).
func _roll_choices(ch: CharacterEntity) -> void:
	var tier := int(_level[ch]) - 1  # level 2 -> tier 1, level 3 -> tier 2
	var cands: Array = []
	for p in pool.perks:
		var d: PerkData = p
		if d.tier != tier:
			continue
		if not d.roles.is_empty() and not _has_role(ch, d.roles):
			continue
		var taken := false
		for q in _picked[ch]:
			var qd: PerkData = q
			if qd.id == d.id:
				taken = true
				break
		if not taken:
			cands.append(d)
	if cands.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _pick_seed(ch, tier, false)
	var picks: Array = []
	while picks.size() < 2 and cands.size() > 0:
		var i := rng.randi() % cands.size()
		var d: PerkData = cands[i]
		picks.append(d)
		cands.remove_at(i)
	_pending[ch] = picks
	_pending_at[ch] = world_.time
	world_.emit_event("perk_level_up", {"ch" = ch, "level" = int(_level[ch]),
		"choices" = picks})

## Server-side pick (validates): idx into the pending choice list.
func pick(ch: CharacterEntity, idx: int) -> bool:
	if pool == null or ch == null or not _pending.has(ch):
		return false
	var c: Array = _pending[ch]
	if idx < 0 or idx >= c.size():
		return false
	var d: PerkData = c[idx]
	_apply(ch, d)
	_pending.erase(ch)
	(_picked[ch] as Array).append(d)
	world_.emit_event("perk_picked", {"ch" = ch, "perk" = d,
		"level" = int(_level[ch]), "choice_idx" = idx})
	return true

## Bots: deterministic seeded choice through the SAME pick() path (AGENTS.md:
## anything a human does, a bot does through the same entry points).
func bot_pick(ch: CharacterEntity) -> bool:
	if not has_pending(ch):
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = _pick_seed(ch, int(_level[ch]), true)
	return pick(ch, rng.randi_range(0, int((_pending[ch] as Array).size()) - 1))

func _maybe_bot_pick(ch: CharacterEntity) -> void:
	# Humans pick through input; the bot delay is checked by the bot's own
	# controller each tick (BotController), not here, so this method only
	# covers characters that have no controller at all (test worlds).
	if not has_pending(ch):
		return
	if ch.controller != null:
		return
	if world_.time - float(_pending_at.get(ch, 0.0)) >= BOT_PICK_DELAY:
		bot_pick(ch)

func _apply(ch: CharacterEntity, d: PerkData) -> void:
	for k in d.effects:
		var cur: float = float(ch.perk_mults.get(k, 1.0))
		ch.perk_mults[k] = cur * float(d.effects[k])
	if float(d.heal_on_pick) > 0.0:
		world_.heal(ch, float(d.heal_on_pick), ch)
	ch.refresh_max_hp()

func _has_role(ch: CharacterEntity, roles: Array) -> bool:
	var h: Hero = ch as Hero
	if h == null or h.hero_data == null:
		return false
	return roles.has(int(h.hero_data.role))

## World clock the bot delay and the UI countdown share.
func _pick_seed(ch: CharacterEntity, tier: int, is_bot: bool) -> int:
	return seed_base + _idx(ch) * 131 + tier * 7919 + (101 if is_bot else 0)

func _idx(ch: CharacterEntity) -> int:
	var i := 0
	for c in world_.characters:
		if c == ch:
			return i
		i += 1
	return 0

# ---- accessors (UI / snapshot / tests) ----

func has_pending(ch: CharacterEntity) -> bool:
	return _pending.has(ch)

func pending_since(ch: CharacterEntity) -> float:
	return float(_pending_at.get(ch, 0.0))

func level_of(ch: CharacterEntity) -> int:
	return int(_level.get(ch, 1))

func picks_of(ch: CharacterEntity) -> Array:
	return _picked.get(ch, [])

## Snapshot extras per character: [level, perk0, perk1, pend0, pend1] as
## pool indices, 255 = none (protocol v1.6 char fields).
func char_extra(ch: CharacterEntity) -> Array:
	var p0 := 255
	var p1 := 255
	var pl: Array = picks_of(ch)
	if pl.size() > 0:
		p0 = _idx_of(pl[0])
	if pl.size() > 1:
		p1 = _idx_of(pl[1])
	var c0 := 255
	var c1 := 255
	if has_pending(ch):
		var c: Array = _pending[ch]
		c0 = _idx_of(c[0])
		if c.size() > 1:
			c1 = _idx_of(c[1])
	return [level_of(ch), p0, p1, c0, c1]

func _idx_of(d: PerkData) -> int:
	var i := pool.index_of(d.id)
	return i if i >= 0 else 255

## World reset (in-place re-match): all perk state is match-local.
func reset() -> void:
	_xp.clear()
	_level.clear()
	_pending.clear()
	_picked.clear()
	_pending_at.clear()
