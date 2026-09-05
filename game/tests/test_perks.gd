extends Node
## D25 perk suite (Phase 7): data-driven in-match perks. 24 checks: pool
## content sanity, XP curve from the world's own events (hit/kill/heal),
## level-up choice rolling (role filter, distinctness, deterministic per
## seed), pick validation, the full modifier pipeline (every effect key,
## table-driven + one content-driven pick), max_hp + instant heal, bot
## picks (direct + controller auto-pick in the sim), world reset, and the
## wire codec (E_PERK + snapshot perk bytes incl. the backward-compat read).

var passed := 0
var failed := 0

func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		passed += 1
		print("  ok  " + name)
	else:
		failed += 1
		printerr("  FAIL " + name + ("  [" + detail + "]" if detail != "" else ""))

func _rel(a: float, b: float, tol := 0.05) -> bool:
	return absf(a - b) <= tol * absf(b)

func _world_with_perks(seed: int = 7) -> World:
	var w := World.new()
	w.name = "World"
	add_child(w)
	w.perk_system = PerkSystem.new()
	w.add_child(w.perk_system)
	w.perk_system.setup(w, load("res://content/perks/perks.tres"), seed)
	return w

func _hero(w: World, team: int, hid: String, pos: Vector3 = Vector3.ZERO) -> Hero:
	var hd: HeroData = null
	for h in HeroRegistry.HEROES:
		if (h as HeroData).id == hid:
			hd = h
			break
	var ch := HeroFactory.create(team, false, (hd as HeroData).color, hd)
	ch.position = pos
	ch.protected_until = -1.0  # tests deal damage immediately
	w.add_child(ch)
	w.register_character(ch)
	return ch

func _ready() -> void:
	_run()

func _run() -> void:
	# ---- pool content ----
	var pool: PerkPool = load("res://content/perks/perks.tres")
	check("pool: 12 perks, 6 per tier, unique ids", pool.perks.size() == 12
		and pool.index_of("overclock") >= 0 and pool.index_of("overflow") >= 0,
		"n=%d" % pool.perks.size())
	var ids: Array = []
	var t1 := 0
	var t2 := 0
	var sane := true
	for p in pool.perks:
		var d: PerkData = p
		if d.id in ids or d.id == "":
			sane = false
		ids.append(d.id)
		if d.tier == 1:
			t1 += 1
		elif d.tier == 2:
			t2 += 1
		else:
			sane = false
		if d.effects.is_empty():
			sane = false
	check("pool: tiers balanced (6/6), every perk has effects", sane and t1 == 6 and t2 == 6)
	var roles_ok := true
	for p in pool.perks:
		var d: PerkData = p
		for r in d.roles:
			if int(r) < 0 or int(r) > 3:
				roles_ok = false
	check("pool: role filters use valid Role values", roles_ok)

	# ---- XP curve from the world's own events ----
	var w := _world_with_perks(42)
	var a := _hero(w, 0, "kestrel", Vector3(0, 0, 0))
	var b := _hero(w, 1, "mira", Vector3(2, 0, 0))
	var ps: PerkSystem = w.perk_system
	# 790 damage = 39.5 xp: just under the level-2 threshold (40).
	for i in 79:
		b.hp = 150.0
		w.damage(b, 10.0, a, false, b.global_position)
	check("xp: 790 damage (39.5 xp) stays level 1", ps.level_of(a) == 1 and not ps.has_pending(a))
	b.hp = 150.0
	w.damage(b, 10.0, a, false, b.global_position)
	check("xp: 40 xp crosses the threshold -> level 2 with 2 pending choices",
		ps.level_of(a) == 2 and ps.has_pending(a), "lvl=%d" % ps.level_of(a))
	var c0: Array = ps._pending[a]
	check("choices: two distinct tier-1 perks offered",
		c0.size() == 2 and (c0[0] as PerkData).id != (c0[1] as PerkData).id,
		"%s vs %s" % [str(c0[0].id if c0.size() > 0 else "-"), str(c0[1].id if c0.size() > 1 else "-")])

	# ---- role filter over several seeds ----
	var seen_aegis := false
	var assault_leak := false
	for i in 12:
		var w2 := _world_with_perks(100 + i)
		var at := _hero(w2, 1, "bastion", Vector3(4, 0, 0))
		var a2 := _hero(w2, 0, "kestrel", Vector3(0, 0, 0))
		for j in 81:
			a2.hp = 150.0
			w2.damage(a2, 10.0, at, false, a2.global_position)  # tank earns
			at.hp = 150.0
			w2.damage(at, 10.0, a2, false, at.global_position)  # assault earns
		var tw: PerkSystem = w2.perk_system
		if tw.has_pending(at):
			for d in tw._pending[at]:
				if (d as PerkData).id == "aegis":
					seen_aegis = true
		if tw.has_pending(a2):
			for d in tw._pending[a2]:
				if (d as PerkData).id == "iron_skin":
					assault_leak = true
		w2.free()
	check("choices: role filter over 4 seeds (tank offered Aegis; assault never Iron Skin)",
		seen_aegis and not assault_leak, "aegis=%s leak=%s" % [seen_aegis, assault_leak])

	# ---- determinism (same seed -> same offers) ----
	var w3 := _world_with_perks(42)
	var a3 := _hero(w3, 0, "kestrel", Vector3(0, 0, 0))
	var b3 := _hero(w3, 1, "mira", Vector3(2, 0, 0))
	for i in 80:
		b3.hp = 150.0
		w3.damage(b3, 10.0, a3, false, b3.global_position)
	var det: Array = w3.perk_system._pending[a3] if w3.perk_system.has_pending(a3) else []
	check("choices: same seed + same history -> same offers", det.size() == 2
		and (det[0] as PerkData).id == (c0[0] as PerkData).id and (det[1] as PerkData).id == (c0[1] as PerkData).id)
	w3.free()

	# ---- pick validation ----
	check("pick: rejected without a pending list", not ps.pick(b, 0))
	check("pick: rejected with a bad index", not ps.pick(a, 5))
	var ai := 0
	for i in 2:
		if (c0[i] as PerkData).id == "overclock":
			ai = i
	check("pick: a valid pick is accepted", ps.pick(a, ai))
	check("pick: the pending list is consumed", not ps.has_pending(a) and ps.pick(a, 0) == false)
	var picked0: PerkData = (ps.picks_of(a)[0] as PerkData)
	check("pick: the perk lands in the picked list + modifier table",
		ps.picks_of(a).size() == 1 and a.perk_mult(picked0.effects.keys()[0]) != 1.0)

	# ---- modifier pipeline: every effect key, table-driven ----
	var w4 := _world_with_perks(11)
	var p1 := _hero(w4, 0, "kestrel", Vector3(0, 0, 0))
	var p2 := _hero(w4, 1, "kestrel", Vector3(10, 0, 0))
	p1.perk_mults["damage"] = 1.15
	var dm_ok := _rel(p1.ability.damage_mult() / p2.ability.damage_mult(), 1.15)
	p1.perk_mults.erase("damage")
	check("pipeline: damage mult", dm_ok)
	p1.perk_mults["fire_rate"] = 1.12
	var fr_ok := _rel(p1.ability.fire_rate_mult() / p2.ability.fire_rate_mult(), 1.12)
	p1.perk_mults.erase("fire_rate")
	check("pipeline: fire_rate mult", fr_ok)
	p1.perk_mults["speed"] = 1.08
	var sp_ok := _rel(p1.ability.speed_mult() / p2.ability.speed_mult(), 1.08)
	p1.perk_mults.erase("speed")
	check("pipeline: speed mult", sp_ok)
	p1.perk_mults["spread"] = 0.85
	var sd_ok := _rel(p1.ability.spread_mult() / p2.ability.spread_mult(), 0.85)
	p1.perk_mults.erase("spread")
	check("pipeline: spread mult", sd_ok)
	# Cooldown: cast both fresh, compare the windows.
	p1.perk_mults["cooldown"] = 0.88
	p1.ability.cast(0)
	p2.ability.cast(0)
	var cd1: float = float(p1.ability._cooldown_until[0]) - w4.time
	var cd2: float = float(p2.ability._cooldown_until[0]) - w4.time
	p1.perk_mults.erase("cooldown")
	check("pipeline: cooldown mult scales the cast window", _rel(cd1 / cd2, 0.88), "%.3f vs %.3f" % [cd1, cd2])
	# Charge: kill with each twin.
	var d1 := _hero(w4, 0, "patch", Vector3(20, 0, 0))
	p1.perk_mults["charge"] = 1.25
	var c1 := p1.ability.charge
	w4.kill(d1, p1, false)
	p1.perk_mults.erase("charge")
	d1.hp = d1.max_hp
	d1.alive = true
	var c2 := p2.ability.charge
	w4.kill(d1, p2, false)
	check("pipeline: charge mult scales charge-per-kill", _rel((p1.ability.charge - c1) / maxf(p2.ability.charge - c2, 0.001), 1.25, 0.05))
	# Max HP + regen.
	var base_hp := p2.max_hp
	p1.perk_mults["max_hp"] = 1.15
	p1.refresh_max_hp()
	var hp_ok := _rel(p1.max_hp / base_hp, 1.15)
	p1.perk_mults.erase("max_hp")
	p1.refresh_max_hp()
	check("pipeline: max_hp mult re-derives the cap", hp_ok and _rel(p1.max_hp / base_hp, 1.0), "hp=%s base=%s" % [str(p1.max_hp), str(base_hp)])
	var r1 := _hero(w4, 0, "kestrel", Vector3(30, 0, 0))
	var r2 := _hero(w4, 1, "kestrel", Vector3(32, 0, 0))
	r1.perk_mults["regen"] = 1.5
	for c in [r1, r2]:
		c.hp = c.max_hp * 0.2
		c._since_damage = 10.0
	var h1 := r1.hp
	var h2 := r2.hp
	for i in 60:
		w4.step(1.0 / 60.0)
	r1.perk_mults.erase("regen")
	check("pipeline: regen mult -> 1.5x out-of-combat recovery", _rel((r1.hp - h1) / maxf(r2.hp - h2, 0.001), 1.5, 0.15),
		"%.2f vs %.2f" % [r1.hp - h1, r2.hp - h2])

	# ---- one content-driven pick (the data flows end-to-end) ----
	var pw: PerkSystem = w4.perk_system
	for i in 81:
		r2.hp = 150.0
		w4.damage(r2, 10.0, p1, false, r2.global_position)
	check("content: a leveled-up twin has pending offers", pw.has_pending(p1), "")
	if pw.has_pending(p1):
		var offer: PerkData = (pw._pending[p1][0] as PerkData)
		pw.pick(p1, 0)
		var applied := p1.perk_mult(offer.effects.keys()[0])
		check("content: the picked perk's declared effect is applied",
			_rel(applied, float(offer.effects[offer.effects.keys()[0]])),
			"%s -> %s (expected %s)" % [offer.id, str(applied), str(offer.effects[offer.effects.keys()[0]])])
	else:
		check("content: the picked perk's declared effect is applied", false, "no pending")
	w4.free()

	# ---- XP sources: kill (+ headshot) and heal ----
	var w5 := _world_with_perks(5)
	var x1 := _hero(w5, 0, "kestrel", Vector3(0, 0, 0))
	var x2 := _hero(w5, 1, "mira", Vector3(2, 0, 0))
	var pb: float = float(w5.perk_system._xp.get(x1, 0.0))
	w5.kill(x2, x1, false)
	check("xp: kill grants the pool's kill xp", _rel(float(w5.perk_system._xp.get(x1, 0.0)) - pb, w5.perk_system.pool.xp_kill))
	x2.alive = true
	x2.hp = x2.max_hp
	var pb2: float = float(w5.perk_system._xp.get(x1, 0.0))
	w5.kill(x2, x1, true)
	check("xp: headshot adds the bonus", _rel(float(w5.perk_system._xp.get(x1, 0.0)) - pb2, w5.perk_system.pool.xp_kill + w5.perk_system.pool.xp_headshot_bonus))
	var hb: float = float(w5.perk_system._xp.get(x2, 0.0))  # the HEALER earns
	x1.hp = 1.0
	x1.alive = true
	x2.hp = x2.max_hp
	x2.alive = true  # the healer must be alive to earn
	w5.heal(x1, 10.0, x2)
	check("xp: the healer earns heal xp", float(w5.perk_system._xp.get(x2, 0.0)) - hb > 0.0,
		"+%.3f" % (float(w5.perk_system._xp.get(x2, 0.0)) - hb))
	w5.free()

	# ---- level 3 + two-tier accumulation ----
	var w6 := _world_with_perks(9)
	var y1 := _hero(w6, 0, "kestrel", Vector3(0, 0, 0))
	var y2 := _hero(w6, 1, "mira", Vector3(2, 0, 0))
	var yw: PerkSystem = w6.perk_system
	# Two-stage: pick the level-2 offer, then earn through level 3 and pick
	# again — picks must accumulate across levels.
	for i in 81:
		y2.hp = 150.0
		w6.damage(y2, 10.0, y1, false, y2.global_position)
	check("level 2: 810 damage levels up with offers", yw.level_of(y1) == 2 and yw.has_pending(y1),
		"lvl=%d" % yw.level_of(y1))
	check("level 2: the pick is accepted", yw.pick(y1, 0))
	for i in 119:
		y2.hp = 150.0
		w6.damage(y2, 10.0, y1, false, y2.global_position)
	check("level 3: crossing 100 xp opens tier-2 offers", yw.level_of(y1) == 3 and yw.has_pending(y1))
	check("level 3: picks accumulate across levels (2 total)", yw.pick(y1, 0) and yw.picks_of(y1).size() == 2)
	w6.free()

	# ---- bots: direct bot_pick + the controller's auto-pick in the sim ----
	var w7 := _world_with_perks(3)
	var z1 := _hero(w7, 0, "kestrel", Vector3(0, 0, 0))
	var z2 := _hero(w7, 1, "mira", Vector3(2, 0, 0))
	for i in 81:
		z2.hp = 150.0
		w7.damage(z2, 10.0, z1, false, z2.global_position)
	var zw: PerkSystem = w7.perk_system
	check("bot: bot_pick() consumes the pending through pick()", zw.bot_pick(z1) and not zw.has_pending(z1))
	# Controller auto-pick: a real BotController must pick within the delay
	# while the sim runs (the production path).
	var zb := _hero(w7, 0, "blitz", Vector3(6, 0, 0))
	var bc := BotController.new()
	zb.add_child(bc)
	bc.setup(zb, null, w7, MatchConfig.difficulty)
	zb.controller = bc
	for i in 81:
		z2.hp = 150.0
		w7.damage(z2, 10.0, zb, false, z2.global_position)  # the blitz (zb) earns
	check("bot: pending offer reached the controller", zw.has_pending(zb), "")
	for i in 60:
		w7.step(1.0 / 60.0)
	check("bot: the controller auto-picks after the delay (1 s of sim)", not zw.has_pending(zb) and zw.picks_of(zb).size() == 1,
		"picks=%d" % zw.picks_of(zb).size())
	w7.free()

	# ---- world reset clears perk state ----
	var w8 := _world_with_perks(8)
	var u1 := _hero(w8, 0, "kestrel", Vector3(0, 0, 0))
	var u2 := _hero(w8, 1, "mira", Vector3(2, 0, 0))
	for i in 41:
		u2.hp = 150.0
		w8.damage(u2, 10.0, u1, false, u2.global_position)
	w8.perk_system.pick(u1, 0)
	w8.reset()
	check("reset: level/picks/pending all cleared", w8.perk_system.level_of(u1) == 1
		and (w8.perk_system.picks_of(u1) as Array).is_empty() and not w8.perk_system.has_pending(u1))
	w8.free()

	# ---- wire codec ----
	var ev := NetProtocol.pack_event_perk(3, 2, 4, 9, 255)
	var evd := NetProtocol.unpack_event(ev)
	check("wire: E_PERK round-trip (pending)", int(evd.type) == NetProtocol.E_PERK
		and int(evd.ch_id) == 3 and int(evd.level) == 2 and int(evd.choice0) == 4
		and int(evd.choice1) == 9 and int(evd.picked) == 255)
	var ev2 := NetProtocol.pack_event_perk(3, 3, 7, 255, 1)
	var evd2 := NetProtocol.unpack_event(ev2)
	check("wire: E_PERK round-trip (picked)", int(evd2.picked) == 1 and int(evd2.choice0) == 7 and int(evd2.choice1) == 255)
	var chars: Array = [{id = 0, team = 0, alive = true, hero_idx = 0,
		pos = Vector3(1, 2, 3), rot_y = 0.5, hp = 90.0, max_hp = 100.0,
		perk_extra = [3, 4, 9, 255, 255]}]
	var snap := NetProtocol.pack_snapshot(7, 12.5, 1, 0, -1, chars, [])
	var sd := NetProtocol.unpack_snapshot(snap)
	var sc0: Dictionary = (sd.chars[0] as Dictionary)
	check("wire: snapshot char perk bytes round-trip", (sc0.perk_extra as Array) == [3, 4, 9, 255, 255],
		str(sc0.perk_extra))
	# Backward compat: a char entry without the D25 bytes (older server).
	var ob := NetProtocol.u8(NetProtocol.M_SNAPSHOT) + NetProtocol.u16(9) + NetProtocol.f32(1.0) + NetProtocol.u8(0) + NetProtocol.u8(0) + NetProtocol.u8(0)
	ob += NetProtocol.u8(0) + NetProtocol.u8(2) + NetProtocol.u8(0)
	for i in 4:
		ob += NetProtocol.u8(0)
	ob += NetProtocol.u8(1)
	ob += NetProtocol.u8(1) + NetProtocol.u8(1) + NetProtocol.u8(1) + NetProtocol.u8(2)
	ob += NetProtocol.f32s([0, 0, 0]) + NetProtocol.f32(0.0) + NetProtocol.f32(50.0) + NetProtocol.f32(50.0)
	ob += NetProtocol.u8(0)
	var od := NetProtocol.unpack_snapshot(ob)
	var oc0: Dictionary = (od.chars[0] as Dictionary)
	check("wire: old snapshot (no perk bytes) still unpacks", int(oc0.id) == 1 and oc0.perk_extra is Array and (oc0.perk_extra as Array).is_empty())

	print("PERKS SUITE: %d passed, %d failed" % [passed, failed])
	get_tree().quit(failed)
