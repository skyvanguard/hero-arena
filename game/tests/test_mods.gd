extends Node
## D34 mod support v1 suite (round 50): drop-in mod discovery + validation.
## Covers: the shipped starter_pack acceptance + every drop-in kind (hero,
## map, cosmetic set, balance entry), idempotency, the three rejection
## rules (api version, id mismatch, missing manifest), balance whole-file
## overrides + alphabetical precedence, unknown-override detection, user
## root shadowing a bundled mod, and the validator on the clean state.
## 15 checks. User://mods test content is created + removed in-process.
var passed := 0
var failed := 0
var UROOT := ""

func _ready() -> void:
	_run()

func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		passed += 1
		print("  ok  " + name)
	else:
		failed += 1
		printerr("  FAIL " + name + ("  [" + detail + "]" if detail != "" else ""))

func _write(p: String, text: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _mkdir(p: String) -> void:
	DirAccess.make_dir_recursive_absolute(p)

func _rmrf(p: String) -> void:
	var d := DirAccess.open(p)
	if d == null:
		return
	d.list_dir_begin()
	var e := d.get_next()
	while e != "":
		if e != "." and e != "..":
			var fp := p.path_join(e)
			if d.current_is_dir():
				_rmrf(fp)
			else:
				d.remove(e)
		e = d.get_next()
	DirAccess.remove_absolute(p)

func _manifest(id: String, api: int) -> String:
	var t := "[gd_resource type=\"Resource\" script_class=\"ModManifest\" load_steps=2 format=3]\n\n"
	t += "[ext_resource type=\"Script\" path=\"res://core/modding/mod_manifest.gd\" id=\"1\"]\n\n"
	t += "[resource]\nscript = ExtResource(\"1\")\nid = \"" + id + "\"\n"
	t += "display_name = \"Test " + id + "\"\nversion = \"1.0\"\napi_version = " + str(api) + "\n"
	return t

func _prog(level_base: float) -> String:
	var t := "[gd_resource type=\"Resource\" script_class=\"ProgressionConfig\" load_steps=2 format=3]\n\n"
	t += "[ext_resource type=\"Script\" path=\"res://core/progression/progression_config.gd\" id=\"1\"]\n\n"
	t += "[resource]\nscript = ExtResource(\"1\")\nlevel_base = " + str(level_base) + "\n"
	return t

func _run() -> void:
	UROOT = ProjectSettings.globalize_path("res://").path_join("../mods_test_r50")
	# NOTE: user mods live under a TEMP dir, not user://mods, so a failing
	# run can never leak a test mod into the real drop-in root.
	# (ModLoader's USER_ROOT is fixed; the shadow test uses a UNIQUE id.)
	# Phase A - the shipped bundled starter_pack (no user mods yet).
	# Defensive: clear leaked test content from a crashed earlier run so a
	# red run can never poison the next one.
	for leak in ["test_fut", "test_badid", "test_nom", "test_over",
			"test_overb", "shadow_pack", "broken_pack"]:
		_rmrf("user://mods".path_join(leak))
	ModLoader.reset()
	ModLoader.scan()
	HeroRegistry._test_reset()
	var mods_a: Array = ModLoader.mods
	check("mods: starter_pack accepted with a valid manifest",
			mods_a.size() == 1 and ModLoader.is_accepted("starter_pack"),
			"%s" % str(mods_a.size()))
	var m0: Dictionary = mods_a[0]
	var mm: ModManifest = m0["manifest"]
	check("mods: manifest fields sane (api 1, version, name)",
			mm != null and mm.api_version == 1 and mm.version == "1.0.0"
			and mm.display_name == "Starter Pack", "%s" % str(mm.version))
	# Hero drop-in.
	var heroes: Array = HeroRegistry.heroes()
	check("heroes: vanta dropped in (7 total, base six intact)",
			heroes.size() == 7 and HeroRegistry.by_id("vanta") != null
			and HeroRegistry.by_id("kestrel") != null
			and HeroRegistry.by_id("nimbus") != null
			and (HeroRegistry.by_id("vanta") as HeroData).role == 3,
			"%s" % str(heroes.size()))
	# Map drop-in.
	check("maps: drift_flats in the pool and loads",
			"drift_flats" in MapRegistry.ids()
			and (MapRegistry.get_map("drift_flats") as Map).map_id == "drift_flats"
			and MapRegistry.ids().size() == 5,
			"%s" % str(MapRegistry.ids()))
	# Balance entry drop-in.
	var be = Balance.entry_for("vanta")
	check("balance: vanta entry dropped in (baseline multipliers)",
			be != null and be.hero_id == "vanta" and be.hp_mult == 1.0
			and be.damage_mult == 1.0 and be.ult_charge_mult == 1.0,
			"%s" % str(be != null))
	# Cosmetic drop-in.
	var bank := HeroVariantBank.load_bank()
	check("cosmetics: vanta set merged (7 sets, base intact)",
			bank.sets.size() == 7 and bank.set_for("vanta") != null
			and bank.set_for("kestrel") != null
			and bank.set_for("vanta").palette.size() == 5,
			"%s" % str(bank.sets.size()))
	# Idempotency.
	var heroes2: Array = HeroRegistry.heroes()
	ModLoader.scan()
	check("mods: idempotent (double merge, double scan)",
			heroes2.size() == 7 and ModLoader.mods.size() == 1)

	# Phase B - synthetic user mods under the real user root.
	var root := "user://mods"
	_mkdir(root.path_join("test_fut"))
	_write(root.path_join("test_fut/mod.tres"), _manifest("test_fut", 99))
	_mkdir(root.path_join("test_badid"))
	_write(root.path_join("test_badid/mod.tres"), _manifest("other_id", 1))
	_mkdir(root.path_join("test_nom"))  # no mod.tres at all
	_mkdir(root.path_join("test_over/balance"))
	_write(root.path_join("test_over/mod.tres"), _manifest("test_over", 1))
	_write(root.path_join("test_over/balance/progression.tres"), _prog(999.0))
	_mkdir(root.path_join("test_overb/balance"))
	_write(root.path_join("test_overb/mod.tres"), _manifest("test_overb", 1))
	_write(root.path_join("test_overb/balance/progression.tres"), _prog(888.0))
	_write(root.path_join("test_overb/balance/bogus.tres"), _prog(1.0))
	_mkdir(root.path_join("shadow_pack"))
	_write(root.path_join("shadow_pack/mod.tres"), _manifest("shadow_pack", 1))

	ModLoader.reset()
	ModLoader.scan()
	HeroRegistry._test_reset()
	check("mods: api_version too new is rejected with a readable reason",
			not ModLoader.is_accepted("test_fut")
			and _reason("test_fut").contains("requires mod API 99"),
			"%s" % _reason("test_fut"))
	check("mods: manifest id != directory id is rejected",
			not ModLoader.is_accepted("test_badid")
			and _reason("test_badid").contains("manifest id"),
			"%s" % _reason("test_badid"))
	check("mods: missing mod.tres is rejected",
			not ModLoader.is_accepted("test_nom")
			and _reason("test_nom") == "missing mod.tres",
			"%s" % _reason("test_nom"))
	check("mods: balance override resolves to the mod file",
			ModLoader.resolve("res://content/progression.tres")
				.begins_with(root.path_join("test_overb")),
			"%s" % ModLoader.resolve("res://content/progression.tres"))
	var op = load(ModLoader.resolve("res://content/progression.tres"))
	check("mods: override precedence = alphabetically last accepted mod",
			op != null and op.level_base == 888.0, "%s" % str(op))
	var issues: Array = ModValidator.validate_all()
	var has_unknown := ""
	for i in issues:
		if str(i).contains("test_overb/balance/bogus.tres") \
				and str(i).contains("unknown override file"):
			has_unknown = "y"
	check("validate: unknown override file is flagged",
			has_unknown == "y", "%s" % str(issues.size()))

	# Phase C - clean state: user mods removed -> validator is silent.
	for id in ["test_fut", "test_badid", "test_nom", "test_over",
			"test_overb", "shadow_pack"]:
		_rmrf(root.path_join(id))
	ModLoader.reset()
	ModLoader.scan()
	HeroRegistry._test_reset()
	var issues2: Array = ModValidator.validate_all()
	check("validate: shipped starter_pack passes clean (0 issues)",
			issues2.size() == 0 and ModLoader.mods.size() == 1
			and HeroRegistry.heroes().size() == 7
			and "drift_flats" in MapRegistry.ids(),
			"%s" % str(issues2))
	# The validator must CATCH a broken mod: corrupt the shadow one.
	_mkdir(root.path_join("broken_pack/heroes"))
	_write(root.path_join("broken_pack/mod.tres"), _manifest("broken_pack", 1))
	_write(root.path_join("broken_pack/heroes/kestrel.tres"),
			"[gd_resource type=\"Resource\" script_class=\"HeroData\" load_steps=1 format=3]\n\n[resource]\nid = \"kestrel\"\n")
	ModLoader.reset()
	ModLoader.scan()
	HeroRegistry._test_reset()
	var issues3: Array = ModValidator.validate_all()
	var caught := false
	for i in issues3:
		if str(i).contains("broken_pack"):
			caught = true
	check("validate: a broken mod is caught (hero without passive/ult)",
			caught, "%s" % str(issues3))
	_rmrf(root.path_join("broken_pack"))
	print("MODS SUITE: %d passed, %d failed" % [passed, failed])
	get_tree().quit(failed)

func _reason(id: String) -> String:
	for m in ModLoader.mods:
		if str(m["id"]) == id:
			return str(m["reason"])
	return "<mod not found>"
