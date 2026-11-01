extends GutTest
## Milestone 3: player and monster rules.

const H = preload("res://tests/helpers.gd")
var data: DSData


func before_each():
	data = H.data()


func _brute(sim_rules: Array = [], hp: int = 10000) -> Combatant:
	var m := DSFactory.make_monster(data, "orc_brute", 1)
	m.hp = hp
	m.max_hp = hp
	if not sim_rules.is_empty():
		m.rules = sim_rules
	return m


# --- rules engine ------------------------------------------------------------

func test_first_true_rule_fires():
	var sim := CombatSim.new(DSRng.new(1), data)
	var p := DSFactory.make_player(data, "warrior", 1, 2, {"rules": [
		{"if": "hp_below", "value": 50, "then": "bash"},
		{"if": "always", "then": "kick"}]})
	var m := _brute([])
	sim.begin(p, [m])
	var c := DSRules.new().choose(sim, p, p.rules, [m])
	assert_eq(c.get("ability"), "kick", "hp is full, so rule 1 is false")
	p.hp = 10
	c = DSRules.new().choose(sim, p, p.rules, [m])
	assert_eq(c.get("ability"), "bash")


func test_rule_on_cooldown_is_skipped():
	var sim := CombatSim.new(DSRng.new(1), data)
	var p := DSFactory.make_player(data, "warrior", 1, 2, {"rules": [
		{"if": "always", "then": "bash"}, {"if": "always", "then": "kick"}]})
	var m := _brute([])
	sim.begin(p, [m])
	p.cooldowns["bash"] = 2
	assert_eq(DSRules.new().choose(sim, p, p.rules, [m]).get("ability"), "kick")


func test_mana_short_rule_is_skipped():
	var sim := CombatSim.new(DSRng.new(1), data)
	var p := DSFactory.make_player(data, "mage", 1, 1, {"rules": [
		{"if": "always", "then": "shield"}, {"if": "always", "then": "magic fist"}]})
	var m := _brute([])
	sim.begin(p, [m])
	p.mana = 5  # shield costs 13, fist costs 3
	assert_eq(DSRules.new().choose(sim, p, p.rules, [m]).get("ability"), "magic fist")


func test_round_one_condition():
	var sim := CombatSim.new(DSRng.new(1), data)
	var p := DSFactory.make_player(data, "thief", 1, 1, {"rules": [{"if": "round_one", "then": "backstab"}]})
	var m := _brute([])
	sim.begin(p, [m])
	sim.round_num = 1
	assert_eq(DSRules.new().choose(sim, p, p.rules, [m]).get("ability"), "backstab")
	sim.round_num = 2
	assert_true(DSRules.new().choose(sim, p, p.rules, [m]).is_empty())


func test_unequipped_ability_never_fires():
	var sim := CombatSim.new(DSRng.new(1), data)
	var p := DSFactory.make_player(data, "warrior", 1, 1, {"actives": ["kick"], "rules": [{"if": "always", "then": "bash"}]})
	var m := _brute([])
	sim.begin(p, [m])
	assert_true(DSRules.new().choose(sim, p, p.rules, [m]).is_empty())


func test_class_ai_covers_the_whole_kit():
	# Every active a class knows at level 10 appears in its built-in priorities.
	for line in ["warrior", "thief", "mage", "knifer"]:
		var ai := DSFactory.class_ai(data, line, 3, 10)
		var refs := ai.map(func(r): return str(CombatSim.split_ref(str(r["then"]))[0]))
		for a in data.kit_abilities(line, 3, 10, "active"):
			assert_true(refs.has(a), "%s AI never mentions %s" % [line, a])


func test_and_conditions():
	var sim := CombatSim.new(DSRng.new(1), data)
	var p := DSFactory.make_player(data, "warrior", 3, 5)
	var m := _brute([])
	sim.begin(p, [m])
	var rules := [{"if": "always", "and": [{"if": "hp_below", "value": 50}], "then": "berserk"},
		{"if": "always", "then": "kick"}]
	assert_eq(DSRules.new().choose(sim, p, rules, [m]).get("ability"), "kick", "and-condition false")
	p.hp = 10
	assert_eq(DSRules.new().choose(sim, p, rules, [m]).get("ability"), "berserk")
	var nots := [{"if": "always", "and": [{"if": "hp_below", "value": 50, "not": true}], "then": "kick"}]
	assert_true(DSRules.new().choose(sim, p, nots, [m]).is_empty(), "not-condition blocks at low HP")


func test_enemy_has_status_targets_the_matching_enemy():
	var sim := CombatSim.new(DSRng.new(1), data)
	var p := DSFactory.make_player(data, "knifer", 1, 8, {"rules": [{"if": "enemy_has_status", "value": "blind", "then": "cross slash"}],
		"actives": ["cross slash"]})
	var a := _brute([])
	a.name = "A"
	var b := _brute([])
	b.name = "B"
	sim.begin(p, [a, b])
	b.add_status("blind", 3)
	assert_eq(DSRules.new().choose(sim, p, p.rules, [a, b]).get("target"), b)


func test_monster_rules_fire():
	var sim := CombatSim.new(DSRng.new(2), data)
	var p := DSFactory.make_player(data, "warrior", 1, 1, {"rules": [], "actives": []})
	p.max_hp = 100000
	p.hp = 100000
	var m := DSFactory.make_monster(data, "hooded_cultist", 1)
	m.hp = 100000
	m.max_hp = 100000
	sim.begin(p, [m])
	var bolts := 0
	for i in 6:
		for ev in sim.step():
			if ev.get("t") == "ability" and ev.get("id") == "shadow_bolt":
				bolts += 1
	assert_gt(bolts, 1)


func test_no_single_enemy_hit_exceeds_the_cap():
	# Every fight, every class: no enemy damage event above 35% of the player's max HP.
	for line in ["warrior", "thief", "mage", "knifer"]:
		for id in data.monsters.keys():
			var sim := CombatSim.new(DSRng.new(7), data)
			var p := DSFactory.make_player(data, line, 1, 1)
			var m := DSFactory.make_monster(data, id, 3)
			for ev in sim.run(p, [m]):
				if ev.get("t") == "damage" and ev.get("dst") == p.name and ev.get("dt") not in ["poison", "bleed"]:
					assert_true(int(ev["amount"]) <= int(p.max_hp * 0.35), "%s vs %s: %d" % [line, id, ev["amount"]])


func test_skill_order_and_off():
	var data := H.data()
	var def := DSFactory.class_ai(data, "warrior", 3, 10)
	assert_eq(DSFactory.class_ai(data, "warrior", 3, 10, [], []), def, "empty order = default")
	var custom := DSFactory.class_ai(data, "warrior", 3, 10, ["kick", "bash"], ["charge"])
	assert_eq(str(custom[0]["then"]), "kick")
	assert_eq(str(custom[1]["then"]), "kick", "both kick entries move together")
	assert_eq(str(custom[2]["then"]), "bash")
	assert_false(custom.any(func(r): return r["then"] == "charge"), "switched off")
	var skills := DSFactory.class_skills(data, "knifer", 3)
	assert_true(skills.any(func(s): return s["name"] == "dance" and s["rules"].size() == 3), "three dances on one card")
	for l in ["warrior", "thief", "mage", "knifer"]:
		for s in DSFactory.class_skills(data, l, 3):
			assert_true(str(data.skills.get(s["name"], "")) != "", "%s has a description" % s["name"])
			for r in s["rules"]:
				assert_false(DSRules.plain(r).contains("_"), DSRules.plain(r))


func test_run_uses_character_skill_order():
	var data := H.data()
	var a := DSAccount.fresh()
	DSAccount.create_character(data, a, "Ash", "warrior", "human")
	DSAccount.current(a)["skill_order"] = ["kick"]
	DSAccount.current(a)["skill_off"] = ["bash"]
	var r := DSAccount.start_run(data, a, 3)
	var p := r.make_player()
	assert_eq(str(p.rules[0]["then"]), "kick")
	assert_false(p.rules.any(func(x): return x["then"] == "bash"))


func test_plain_rule_text_has_whole_numbers():
	assert_eq(DSRules.plain({"if": "hp_below", "value": 35.0, "then": "berserk"}), "when your HP is below 35%")
