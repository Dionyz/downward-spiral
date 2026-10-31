extends GutTest
## Whole-fight behaviour: determinism, round structure, abilities.

const H = preload("res://tests/helpers.gd")
var data: DSData


func before_each():
	data = H.data()


func _fight(seed_value: int, line: String = "warrior", level: int = 1) -> Array:
	var rng := DSRng.new(seed_value)
	var p := DSFactory.make_player(data, line, 1, level, {"rule_slots": 4})
	var foes: Array = []
	for i in 3:
		foes.append(DSFactory.make_monster(data, "goblin_cutter", level, i))
	var sim := CombatSim.new(rng, data)
	return sim.run(p, foes)


func test_same_seed_reproduces_the_same_fight():
	var a := _fight(42)
	var b := _fight(42)
	assert_eq(a.size(), b.size())
	assert_eq(JSON.stringify(a), JSON.stringify(b))


func test_mage_fight_is_deterministic_too():
	assert_eq(JSON.stringify(_fight(7, "mage", 3)), JSON.stringify(_fight(7, "mage", 3)))


func test_different_seeds_differ():
	assert_ne(JSON.stringify(_fight(1)), JSON.stringify(_fight(2)))


func test_fight_ends_with_a_result():
	var h := _fight(5)
	var last: Dictionary = h[h.size() - 1]
	assert_eq(last.get("t"), "fight_end")
	assert_true(last.get("result") in ["win", "loss", "timeout"])


func test_events_are_structured():
	var allowed := ["fight_start", "round", "damage", "miss", "parry", "dodge", "block", "ability", "cast",
		"ability_miss", "resist", "status_applied", "status_expired", "stance", "heal", "mana", "stunned",
		"death", "fight_end"]
	for ev in _fight(11, "mage", 5):
		assert_true(ev.get("t") in allowed, "unknown event %s" % ev.get("t"))
		assert_true(ev.has("r"))


func test_stunned_combatant_loses_its_round():
	var sim := CombatSim.new(DSRng.new(3), data)
	var p := DSFactory.make_player(data, "warrior", 1, 1, {"rules": [], "actives": []})
	var m := DSFactory.make_monster(data, "goblin_cutter", 1)
	m.hp = 10000
	m.max_hp = 10000
	sim.begin(p, [m])
	p.add_status("stunned", 2)  # still stunned after round 1's tick
	var evs := sim.step()
	for ev in evs:
		if ev.get("t") == "damage":
			assert_ne(ev.get("src"), p.name, "stunned player must not attack")


func test_cooldown_blocks_reuse():
	var sim := CombatSim.new(DSRng.new(3), data)
	var p := DSFactory.make_player(data, "warrior", 1, 1, {"rules": [{"if": "always", "then": "bash"}], "actives": ["bash"]})
	p.skills["bash"] = 1000
	var m := DSFactory.make_monster(data, "orc_brute", 1)
	m.hp = 10000
	m.max_hp = 10000
	m.rules = []
	sim.begin(p, [m])
	var bash_rounds: Array = []
	for i in 8:
		for ev in sim.step():
			if ev.get("t") == "ability" and ev.get("ability") == "bash":
				bash_rounds.append(ev.get("r"))
	# beats 10 -> 1 round cooldown, but a knocked-down target can't be bashed again until it's up.
	assert_eq(bash_rounds, [1, 3, 5, 7])


func test_mage_spends_mana_and_regens():
	var sim := CombatSim.new(DSRng.new(3), data)
	var p := DSFactory.make_player(data, "mage", 1, 1, {"rules": [{"if": "always", "then": "magic fist"}], "actives": ["magic fist"]})
	var m := DSFactory.make_monster(data, "goblin_cutter", 1)
	m.hp = 10000
	m.max_hp = 10000
	sim.begin(p, [m])
	var start := p.mana
	sim.step()  # round 1: regen +2 (capped at max), then fist -3
	assert_eq(p.mana, start - DSStats.mana_cost(10, data.balance))


func test_bash_knocks_down_and_dazes():
	var sim := CombatSim.new(DSRng.new(3), data)
	var p := DSFactory.make_player(data, "warrior", 1, 1, {"rules": [{"if": "always", "then": "bash"}]})
	p.skills["bash"] = 1000
	var m := DSFactory.make_monster(data, "orc_brute", 1)
	m.hp = 10000
	m.max_hp = 10000
	m.rules = []
	sim.begin(p, [m])
	sim.step()
	assert_true(m.has_status("knocked_down"))
	assert_true(m.has_status("dazed"))
	assert_false(m.can_act())


func test_backstab_needs_a_healthy_target():
	var sim := CombatSim.new(DSRng.new(3), data)
	var p := DSFactory.make_player(data, "thief", 1, 1)
	var m := DSFactory.make_monster(data, "goblin_cutter", 1)
	sim.begin(p, [m])
	assert_true(sim.can_use(p, "backstab", m))
	m.hp = int(m.max_hp / 4)
	assert_false(sim.can_use(p, "backstab", m), "do_backstab refuses below 1/3 HP")


func test_stance_changes_and_cooldown():
	var sim := CombatSim.new(DSRng.new(3), data)
	var p := DSFactory.make_player(data, "knifer", 1, 1, {"rules": [{"if": "always", "then": "dance:storm"}]})
	var m := DSFactory.make_monster(data, "goblin_cutter", 1)
	m.hp = 10000
	m.max_hp = 10000
	sim.begin(p, [m])
	sim.step()
	assert_eq(p.stance, "storm")
	assert_true(p.has_status("stance_storm"))
	assert_false(sim.can_use(p, "dance:storm", p), "already in that stance")


func test_chain_lightning_jumps_between_targets():
	var sim := CombatSim.new(DSRng.new(3), data)
	var p := DSFactory.make_player(data, "mage", 1, 6, {"rules": [{"if": "always", "then": "chain lightning"}],
		"actives": ["chain lightning"]})
	var foes: Array = []
	for i in 3:
		var m := DSFactory.make_monster(data, "goblin_cutter", 1, i)
		m.name = "g%d" % i
		m.hp = 10000
		m.max_hp = 10000
		foes.append(m)
	sim.begin(p, foes)
	var hit := {}
	for ev in sim.step():
		if ev.get("t") == "damage" and ev.get("dt") == "chain lightning":
			hit[ev.get("dst")] = true
	# mud level 60: 60, 52, 44 ... 4 -> 8 hits spread over all three targets.
	assert_eq(hit.size(), 3)


func test_chain_lightning_fizzles_on_a_single_target():
	var sim := CombatSim.new(DSRng.new(3), data)
	var p := DSFactory.make_player(data, "mage", 1, 6, {"rules": [{"if": "always", "then": "chain lightning"}],
		"actives": ["chain lightning"]})
	var m := DSFactory.make_monster(data, "goblin_cutter", 1)
	m.hp = 10000
	m.max_hp = 10000
	sim.begin(p, [m])
	var hp_before := p.hp
	var bolts := 0
	for ev in sim.step():
		if ev.get("t") == "damage" and ev.get("dt") == "chain lightning":
			bolts += 1
			assert_ne(ev.get("dst"), p.name, "no backlash into the caster")
	assert_eq(bolts, 1)


func test_class_plays_itself_without_rules():
	# No rules at all: the character still uses its equipped actives.
	var sim := CombatSim.new(DSRng.new(4), data)
	var p := DSFactory.make_player(data, "warrior", 1, 3, {"rules": []})
	var m := DSFactory.make_monster(data, "orc_brute", 1)
	m.hp = 10000
	m.max_hp = 10000
	m.rules = []
	sim.begin(p, [m])
	var used := 0
	for i in 5:
		for ev in sim.step():
			if ev.get("t") in ["ability", "cast"] and ev.get("src") == p.name:
				used += 1
	assert_gt(used, 2)


func test_sidestep_chance():
	var sim := CombatSim.new(DSRng.new(3), data)
	var atk := H.dummy("atk")
	var v := H.dummy("v", true)
	assert_eq(sim.sidestep_chance(atk, v), 0, "no skill, no floor")
	v.skills["sidestep"] = 60
	assert_eq(sim.sidestep_chance(atk, v), 30)
	v.skills["sidestep"] = 200
	assert_eq(sim.sidestep_chance(atk, v), 50)


func test_thief_gets_sidestep():
	var p := DSFactory.make_player(data, "thief", 1, 3)
	assert_gt(p.skill("sidestep"), 0)


func test_legendary_second_wind_fires_once():
	var sim := CombatSim.new(DSRng.new(3), data)
	var p := DSFactory.make_player(data, "warrior", 1, 1, {"rules": [], "actives": []})
	p.flags["passives"] = ["second_wind"]
	var m := H.dummy("mob")
	sim.begin(p, [m])
	sim.apply_damage(m, p, int(p.max_hp * 0.4), "hit", "bash", false, {"uncapped": true})
	assert_false(p.flags.get("second_wind_used", false))
	sim.apply_damage(m, p, int(p.max_hp * 0.4), "hit", "bash", false, {"uncapped": true})
	assert_true(p.flags.get("second_wind_used", false))
	assert_gt(p.hp_pct(), 45.0, "~60% -> ~21% -> healed +30%")
