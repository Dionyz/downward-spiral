extends GutTest
## Data import checks (milestone 1 acceptance, from the game side).

const H = preload("res://tests/helpers.gd")
var data: DSData


func before_each():
	data = H.data()


func test_every_ability_has_a_source():
	assert_gt(data.abilities.size(), 30)
	for n in data.abilities.keys():
		var src: String = data.abilities[n].get("source", "")
		assert_true(src.find(".c:") > 0, "%s source should name a C function, got '%s'" % [n, src])


func test_four_class_lines_with_three_tiers():
	for line in ["warrior", "thief", "mage", "knifer"]:
		assert_true(data.classes.has(line))
		assert_eq(data.classes[line]["tiers"].size(), 3)
	assert_eq(data.tier_class("mage", 3), "sorcerer")
	assert_eq(data.tier_class("warrior", 3), "knight")
	assert_eq(data.tier_class("thief", 3), "blade")
	assert_eq(data.tier_class("knifer", 3), "wardancer")
	assert_eq(data.classes["knifer"]["display"], "Jackal", "Devil's Silence names are renamed")
	assert_eq(data.classes["knifer"]["tiers"][2]["name"], "Tarantella")


func test_every_kit_ability_exists():
	for line in data.classes.keys():
		for key in ["passives", "starting_actives", "signature"]:
			for n in data.classes[line].get(key, []):
				assert_false(data.ability(n).is_empty(), "%s kit references missing ability %s" % [line, n])


func test_class_ai_references_kit_abilities():
	for line in data.classes.keys():
		assert_gt(data.classes[line].get("ai", []).size(), 3, "%s has a built-in priority list" % line)
		for r in data.classes[line].get("ai", []):
			var n := str(CombatSim.split_ref(r["then"])[0])
			assert_false(data.ability(n).is_empty(), "%s default rule uses missing %s" % [line, n])
			assert_true(r.get("if") in DSRules.CONDITIONS, "%s rule condition %s" % [line, r.get("if")])


func test_unlock_levels_follow_ceil_mud_level_over_10():
	# trip: warrior 40 -> 4, gladiator 30 -> 3; chain lightning: mage 60 -> 6, sorcerer 40 -> 4
	assert_eq(data.unlock_level("trip", "warrior", 1), 4)
	assert_eq(data.unlock_level("trip", "warrior", 2), 3)
	assert_eq(data.unlock_level("kick", "warrior", 1), 1, "spec starting actives are forced to level 1 (MUD: 12 -> 2)")
	assert_eq(data.unlock_level("chain lightning", "mage", 1), 6)
	assert_eq(data.unlock_level("chain lightning", "mage", 3), 4)


func test_overrides_merge_over_import():
	assert_true(data.classes["warrior"].has("stats"), "overrides/classes.json merged")
	assert_eq(int(data.abilities["sanctuary"]["params"]["duration_rounds"]), 6)
	assert_eq(data.abilities["sanctuary"]["source"], "magic.c:spell_sanctuary", "import fields survive the merge")


func test_deep_merge():
	var a := {"x": {"y": 1, "z": 2}, "k": [1]}
	var b := {"x": {"y": 5}, "k": [9]}
	assert_eq(DSData.deep_merge(a, b), {"x": {"y": 5, "z": 2}, "k": [9]})


func test_starting_weapon():
	var w := DSFactory.starting_weapon(data, "dagger", 1)
	assert_eq([w["min"], w["max"]], [8, 16])
	var w10 := DSFactory.starting_weapon(data, "dagger", 10)
	assert_eq([w10["min"], w10["max"]], [44, 88])


func test_glossary_covers_item_words():
	var data := H.data()
	var keys := {}
	for e in data.glossary:
		for k in e["keys"]:
			keys[str(k)] = true
	for af in data.items["affixes"].values():
		for f in af.get("flags", []):
			assert_true(keys.has(str(f)), "glossary explains %s" % f)
		for sk in af.get("skill_bonus", {}).keys():
			assert_true(keys.has(str(sk)), "glossary explains %s" % sk)
	for k in ["avg dmg", "armor", "hp", "mana", "weapon damage", "extract", "damage reduction"]:
		assert_true(keys.has(k), k)
