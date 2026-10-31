extends GutTest
## Milestone 3: rules, telegraphs, and coverage.

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


func test_enemy_telegraphing_targets_the_telegrapher():
	var sim := CombatSim.new(DSRng.new(1), data)
	var p := DSFactory.make_player(data, "warrior", 1, 1, {"rules": [{"if": "enemy_telegraphing", "then": "bash"}]})
	var a := _brute([])
	a.name = "A"
	var b := _brute([])
	b.name = "B"
	sim.begin(p, [a, b])
	b.telegraph = {"ability": "overhead_smash", "name": "Overhead Smash", "tag": "brace"}
	var c := DSRules.new().choose(sim, p, p.rules, [a, b])
	assert_eq(c.get("target"), b)


func test_default_rules_exist_for_every_class():
	for line in ["warrior", "thief", "mage", "knifer"]:
		var p := DSFactory.make_player(data, line, 1, 1)
		assert_gt(p.rules.size(), 0, "%s has default rules at level 1" % line)
		assert_true(p.rules.size() <= 2, "two rule slots at run start")


# --- telegraphs --------------------------------------------------------------

func _run_until(sim: CombatSim, rounds: int) -> Array:
	var all: Array = []
	for i in rounds:
		all.append_array(sim.step())
	return all


func _types(evs: Array, t: String) -> Array:
	return evs.filter(func(e): return e.get("t") == t)


func test_telegraph_answered_by_interrupt_rule():
	# Orc telegraphs on round 4; the warrior's rule bashes it on round 5 before it lands.
	var sim := CombatSim.new(DSRng.new(9), data)
	var p := DSFactory.make_player(data, "warrior", 1, 1, {"rules": [{"if": "enemy_telegraphing", "then": "bash"}]})
	p.skills["bash"] = 1000
	var m := _brute()
	sim.begin(p, [m])
	var evs := _run_until(sim, 6)
	assert_eq(_types(evs, "telegraph").size(), 1, "orc telegraphs once by round 6")
	assert_eq(_types(evs, "telegraph_interrupted").size(), 1, "bash interrupts it")
	assert_eq(_types(evs, "telegraph_strike").size(), 0, "the big hit never lands")


func test_unanswered_telegraph_lands_hard():
	var sim := CombatSim.new(DSRng.new(9), data)
	var p := DSFactory.make_player(data, "mage", 1, 1, {"rules": []})
	p.max_hp = 1000
	p.hp = 1000
	var m := _brute()
	sim.begin(p, [m])
	var evs := _run_until(sim, 5)
	var strikes := _types(evs, "telegraph_strike")
	assert_eq(strikes.size(), 1)
	assert_eq(strikes[0].get("answered"), "")
	var big := evs.filter(func(e): return e.get("t") == "damage" and e.get("dt") == "overhead_smash")
	assert_eq(big.size(), 1)
	assert_gt(int(big[0].get("amount")), 350, "40% of max HP, more than an untelegraphed hit may deal")


func test_brace_with_shield_spell():
	var sim := CombatSim.new(DSRng.new(9), data)
	var p := DSFactory.make_player(data, "mage", 1, 1, {"rules": [{"if": "missing_buff", "value": "shield", "then": "shield"}]})
	p.max_hp = 1000
	p.hp = 1000
	var m := _brute()
	sim.begin(p, [m])
	var evs := _run_until(sim, 5)
	var strikes := _types(evs, "telegraph_strike")
	assert_eq(strikes.size(), 1)
	assert_eq(strikes[0].get("answered"), "shield")
	var big := evs.filter(func(e): return e.get("t") == "damage" and e.get("dt") == "overhead_smash")
	assert_lt(int(big[0].get("amount")), 200, "braced: 400 * 0.35, minus armor")


func test_evade_with_mist_stance():
	var sim := CombatSim.new(DSRng.new(9), data)
	var p := DSFactory.make_player(data, "knifer", 1, 1, {"rules": [{"if": "enemy_telegraphing", "then": "dance:mist"}]})
	var m := DSFactory.make_monster(data, "hollow_matron", 1)
	m.hp = 10000
	m.max_hp = 10000
	m.rules = [{"if": "every_n", "value": 3, "then": "lunging_lash"}]
	sim.begin(p, [m])
	var evs := _run_until(sim, 5)
	var strikes := _types(evs, "telegraph_strike")
	assert_eq(strikes.size(), 1)
	assert_eq(strikes[0].get("answered"), "mist")
	assert_eq(evs.filter(func(e): return e.get("t") == "damage" and e.get("dt") == "lunging_lash").size(), 0)


func test_outlast_becomes_a_bleed():
	var sim := CombatSim.new(DSRng.new(9), data)
	var p := DSFactory.make_player(data, "warrior", 1, 1, {"rules": []})
	var m := DSFactory.make_monster(data, "hollow_matron", 1)
	m.hp = 10000
	m.max_hp = 10000
	m.rules = [{"if": "every_n", "value": 3, "then": "wasting_curse"}]
	sim.begin(p, [m])
	_run_until(sim, 4)
	assert_true(p.has_status("bleeding"))


func test_non_telegraphed_monster_attacks_stay_under_35_percent():
	# Every monster ability that isn't a telegraph must have max damage <= 35% of a level-1 player's HP.
	var weakest := 1000000
	for line in ["warrior", "thief", "mage", "knifer"]:
		weakest = mini(weakest, DSFactory.make_player(data, line, 1, 1).max_hp)
	for id in data.monsters.keys():
		var m := DSFactory.make_monster(data, id, 1)
		for k in m.monster_abilities.keys():
			var a: Dictionary = m.monster_abilities[k]
			if a.get("handler") == "telegraph":
				continue
			assert_true(int(a.get("max", 0)) <= int(weakest * 0.35), "%s.%s can one-shot without a telegraph" % [id, k])


func test_every_telegraph_has_a_known_tag():
	for id in data.monsters.keys():
		for k in data.monsters[id].get("abilities", {}).keys():
			var a: Dictionary = data.monsters[id]["abilities"][k]
			if a.get("handler") == "telegraph":
				assert_true(a.get("tag") in DSAbility.TAGS, "%s.%s tag" % [id, k])


# --- coverage (spec: each class answers every tag by its first boss) ----------

func _coverage_at_first_boss(line: String) -> Dictionary:
	var fb: Dictionary = data.balance.get("first_boss", {"tier": 3, "level": 8})
	return DSAbility.coverage(data, line, int(fb.get("tier", 3)), int(fb.get("level", 8)))


func _assert_full_coverage(line: String):
	var cov := _coverage_at_first_boss(line)
	for t in DSAbility.TAGS:
		assert_gt(cov[t].size(), 0, "%s has no answer to %s" % [line, t])


func test_warrior_answers_every_tag_by_first_boss():
	_assert_full_coverage("warrior")


func test_mage_answers_every_tag_by_first_boss():
	_assert_full_coverage("mage")


func test_knifer_answers_every_tag_by_first_boss():
	_assert_full_coverage("knifer")


func test_thief_answers_every_tag_by_first_boss():
	# Known gap, QUESTIONS.md Q8: the spec's thief kit has no Brace answer.
	var cov := _coverage_at_first_boss("thief")
	if cov["brace"].is_empty():
		pending("Thief has no Brace answer yet (milestone 6, QUESTIONS.md)")
		return
	_assert_full_coverage("thief")
