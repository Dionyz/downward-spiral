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
		"telegraph", "telegraph_interrupted", "telegraph_strike", "backlash", "death", "fight_end"]
	for ev in _fight(11, "mage", 5):
		assert_true(ev.get("t") in allowed, "unknown event %s" % ev.get("t"))
		assert_true(ev.has("r"))


func test_stunned_combatant_loses_its_round():
	var sim := CombatSim.new(DSRng.new(3), data)
	var p := DSFactory.make_player(data, "warrior", 1, 1, {"rules": []})
	var m := DSFactory.make_monster(data, "goblin_cutter", 1)
	m.hp = 10000
	m.max_hp = 10000
	sim.begin(p, [m])
	p.add_status("stunned", 2)  # loses the next round
	var evs := sim.step()
	for ev in evs:
		if ev.get("t") == "damage":
			assert_ne(ev.get("src"), p.name, "stunned player must not attack")


func test_cooldown_blocks_reuse():
	var sim := CombatSim.new(DSRng.new(3), data)
	var p := DSFactory.make_player(data, "warrior", 1, 1, {"rules": [{"if": "always", "then": "bash"}]})
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
	# beats 10 -> 3 rounds of cooldown -> rounds 1, 5 (knocked-down target can't be bashed in between).
	assert_eq(bash_rounds, [1, 5])


func test_mage_spends_mana_and_regens():
	var sim := CombatSim.new(DSRng.new(3), data)
	var p := DSFactory.make_player(data, "mage", 1, 1, {"rules": [{"if": "always", "then": "magic fist"}]})
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
	var p := DSFactory.make_player(data, "mage", 3, 6, {"rules": [{"if": "always", "then": "chain lightning"}],
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
