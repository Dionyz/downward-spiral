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


func test_default_rules_exist_for_every_class():
	for line in ["warrior", "thief", "mage", "knifer"]:
		var p := DSFactory.make_player(data, line, 1, 1)
		assert_gt(p.rules.size(), 0, "%s has default rules at level 1" % line)
		assert_true(p.rules.size() <= 2, "two rule slots at run start")
		var p5 := DSFactory.make_player(data, line, 1, 5)
		assert_eq(p5.rules.size(), 3, "%s gets a third rule slot at level 5" % line)


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
			if ev.get("t") == "ability" and ev.get("ability") == "shadow_bolt":
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
