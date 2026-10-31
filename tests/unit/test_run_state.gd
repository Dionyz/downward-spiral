extends GutTest
## Milestone 5: run loop, rewards, boons, events, extraction, death, save and resume.

const H = preload("res://tests/helpers.gd")
var data: DSData


func before_each():
	data = H.data()


func test_new_run_starts_on_floor_one():
	var r := DSRunState.new_run(data, "warrior", 11)
	assert_eq(r.floor_num, 1)
	assert_eq(r.phase, "path")
	assert_eq(r.steps().size(), 3)
	assert_not_null(r.items["weapon"])
	assert_eq(r.potions["mp"], 0, "no MP potions for a class without mana")
	assert_eq(DSRunState.new_run(data, "mage", 11).potions["mp"], 2)


func test_full_runs_finish_for_every_class():
	for line in ["warrior", "thief", "mage", "knifer"]:
		for s in range(1, 9):
			var r := DSAutopilot.play(DSRunState.new_run(data, line, s * 31))
			assert_eq(r.phase, "over", "%s seed %d finished" % [line, s])
			assert_true(r.result in ["death", "victory"], "%s result %s" % [line, r.result])
			assert_gt(int(r.stats["fights"]), 0)


func test_some_run_reaches_the_boss_and_wins():
	var wins := 0
	for line in ["warrior", "thief", "mage", "knifer"]:
		for s in range(1, 21):
			var r := DSAutopilot.play(DSRunState.new_run(data, line, s * 7 + 3))
			if r.result == "victory":
				wins += 1
				assert_eq(r.floor_num, 6)
	assert_gt(wins, 0, "the full 6-floor run can be completed")


func test_save_and_resume_mid_fight_room_is_identical():
	var r := DSRunState.new_run(data, "knifer", 99)
	r.enter(0)
	while not r.is_fight_room():
		DSAutopilot.advance(r)
		if r.phase == "path":
			r.enter(0)
	var saved := JSON.stringify(r.to_dict())
	var a := DSAutopilot.fight(r, true)
	var r2 := DSRunState.from_dict(data, JSON.parse_string(saved))
	assert_eq(r2.phase, "room")
	assert_eq(r2.room["type"], r.room["type"])
	var b := DSAutopilot.fight(r2, true)
	assert_eq(JSON.stringify(a.history), JSON.stringify(b.history), "resumed fight replays exactly")
	assert_eq(JSON.stringify(r.to_dict()), JSON.stringify(r2.to_dict()), "state after the fight matches")


func test_save_round_trip_preserves_everything():
	var r := DSRunState.new_run(data, "mage", 5)
	for i in 6:
		DSAutopilot.advance(r)
	var d := r.to_dict()
	var r2 := DSRunState.from_dict(data, JSON.parse_string(JSON.stringify(d)))
	assert_eq(JSON.stringify(r2.to_dict()), JSON.stringify(d))


func test_resume_continues_the_same_run():
	var r := DSRunState.new_run(data, "thief", 42)
	for i in 5:
		DSAutopilot.advance(r)
	var r2 := DSRunState.from_dict(data, JSON.parse_string(JSON.stringify(r.to_dict())))
	DSAutopilot.play(r)
	DSAutopilot.play(r2)
	assert_eq(r.result, r2.result)
	assert_eq(r.floor_num, r2.floor_num)
	assert_eq(r.gold, r2.gold)


func test_extract_only_from_floor_two():
	var r := DSRunState.new_run(data, "warrior", 3)
	r.phase = "floor_end"
	assert_false(r.can_extract(), "no extract after floor 1")
	r.floor_num = 2
	assert_true(r.can_extract())
	r.gold = 120
	r.xp_total = 300
	r.extract()
	assert_eq(r.result, "extract")
	assert_eq(r.banked(), {"xp": 300, "gold": 120})


func test_death_keeps_half_xp_and_no_gold():
	var r := DSRunState.new_run(data, "warrior", 3)
	r.gold = 80
	r.xp_total = 200
	r.end_run("death")
	assert_eq(r.banked(), {"xp": 100, "gold": 0})
	var acct := DSRunState.bank_into({}, r)
	assert_eq(acct["xp"], 100)
	assert_eq(acct["deaths"], 1)


func test_level_up_from_xp():
	var r := DSRunState.new_run(data, "warrior", 3)
	var before := r.make_player().max_hp
	assert_eq(r.add_xp(40), 1)
	assert_eq(r.level, 2)
	assert_gt(r.make_player().max_hp, before)


func test_rest_heals_40_percent():
	var r := DSRunState.new_run(data, "warrior", 3)
	var p := r.make_player()
	r.hp = 10
	r.room = {"type": "rest"}
	r.phase = "room"
	r.rest_heal()
	assert_eq(r.hp, 10 + int(p.max_hp * 0.4))
	assert_eq(r.phase, "path")


func test_rest_train_swaps_abilities():
	var r := DSRunState.new_run(data, "warrior", 3)
	r.level = 5
	r.room = {"type": "rest"}
	r.phase = "room"
	r.rest_train(["kick", "trip", "not_an_ability"], [{"if": "always", "then": "trip"}])
	assert_eq(r.actives, ["kick", "trip"])
	assert_eq(r.rules, [{"if": "always", "then": "trip"}])


func test_shrine_remove_and_reroll_cost_gold():
	var r := DSRunState.new_run(data, "warrior", 3)
	r.boons = ["opportunist"]
	r.room = {"type": "shrine", "offers": []}
	r.phase = "room"
	r.gold = 10
	assert_false(r.shrine_reroll(), "too poor")
	r.gold = 100
	assert_true(r.shrine_reroll())
	assert_eq(r.gold, 80)
	assert_eq(r.room["offers"].size(), 3)
	assert_true(r.shrine_remove("opportunist"))
	assert_eq(r.boons, [])
	assert_eq(r.gold, 50)


func test_every_event_option_runs():
	for id in data.events.keys():
		var opts: Array = data.events[id]["options"]
		for i in opts.size():
			var r := DSRunState.new_run(data, "mage", 17)
			r.room = {"type": "event", "event": id}
			r.phase = "room"
			var lines := r.event_choose(i)
			assert_gt(lines.size(), 0, "%s option %d says something" % [id, i])
			assert_true(r.phase in ["room", "reward"])


func test_boons_reference_real_abilities():
	var stat_words := ["hp", "damage", "gold", "xp", "potion"]
	assert_gt(data.boons.size(), 10)
	for id in data.boons.keys():
		for ref in data.boons[id].get("refs", []):
			assert_true(stat_words.has(ref) or not data.ability(ref).is_empty(), "boon %s refs missing %s" % [id, ref])
		for ln in data.boons[id].get("lines", []):
			assert_true(data.classes.has(ln), "boon %s line %s" % [id, ln])


func test_boons_apply_to_the_player():
	var r := DSRunState.new_run(data, "warrior", 3)
	var base := r.make_player()
	r.boons = ["hard_to_pin", "concussive_bash", "second_skin"]
	var p := r.make_player()
	assert_eq(p.skill("parry"), base.skill("parry") + 10)
	assert_true(p.flags.get("boon_bash_slow", false))
	assert_true(p.has_status("armor"))


func test_reward_offers_after_a_win():
	var r := DSRunState.new_run(data, "warrior", 8)
	r.enter(0)
	while not r.is_fight_room():
		DSAutopilot.advance(r)
		if r.phase == "path":
			r.enter(0)
	DSAutopilot.fight(r)
	if r.result == "death":
		pass_test("died in the first fight on this seed")
		return
	assert_eq(r.phase, "reward")
	assert_eq(r.room["reward"]["offers"].size(), 3)
	assert_gt(r.gold, 0)


func test_boss_has_phases():
	var m := DSFactory.make_monster(data, "spiral_warden", 10)
	assert_eq(m.flags["phases"].size(), 2)
	var sim := CombatSim.new(DSRng.new(1), data)
	var p := H.dummy("You", true)
	sim.begin(p, [m])
	sim.apply_damage(p, m, int(m.max_hp * 0.5), "hit", "slash", false)
	assert_eq(int(m.flags.get("phase", 0)), 1)
	assert_true(m.monster_abilities.has("coiling_lash"))
	sim.apply_damage(p, m, int(m.max_hp * 0.3), "hit", "slash", false)
	assert_eq(int(m.flags.get("phase", 0)), 2)
