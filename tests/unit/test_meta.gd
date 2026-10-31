extends GutTest
## Milestone 8: account progression.

const H = preload("res://tests/helpers.gd")
var data: DSData


func before_each():
	data = H.data()


func test_account_levels_from_xp():
	assert_eq(DSMeta.level_for(data, 0), 1)
	assert_eq(DSMeta.level_for(data, 150), 2)
	assert_eq(DSMeta.level_for(data, 399), 2)
	assert_eq(DSMeta.level_for(data, 999999), 10)


func test_class_unlocks_follow_the_spec():
	assert_eq(DSMeta.perks(data, 1)["classes"], ["warrior"])
	assert_eq(DSMeta.class_unlock_level(data, "thief"), 2)
	assert_eq(DSMeta.class_unlock_level(data, "mage"), 4)
	assert_eq(DSMeta.class_unlock_level(data, "knifer"), 6)
	assert_eq(DSMeta.perks(data, 6)["classes"].size(), 4)


func test_permanent_bonuses_capped_at_ten_percent():
	var p := DSMeta.perks(data, 10)
	assert_true(int(p["hp_pct"]) <= 10)
	assert_true(int(p["damage_pct"]) <= 10)
	assert_eq(int(p["hp_pct"]), 10)


func test_third_starting_rule_slot():
	var r1 := DSRunState.new_run(data, "warrior", 1, DSMeta.perks(data, 1))
	var r3 := DSRunState.new_run(data, "warrior", 1, DSMeta.perks(data, 3))
	assert_eq(r1.rule_slots(), 2)
	assert_eq(r3.rule_slots(), 3)
	r3.level = 5
	assert_eq(r3.rule_slots(), 4, "max 4 rule slots")


func test_perks_change_the_player():
	var base := DSRunState.new_run(data, "warrior", 1, DSMeta.perks(data, 1)).make_player()
	var vet := DSRunState.new_run(data, "warrior", 1, DSMeta.perks(data, 10)).make_player()
	assert_gt(vet.max_hp, base.max_hp)
	assert_lt(vet.max_hp, int(base.max_hp * 1.11))


func test_locked_boons_stay_out_of_the_pool():
	var r := DSRunState.new_run(data, "warrior", 1, DSMeta.perks(data, 1))
	var pool := r.available_boons()
	assert_false(pool.has("momentum"), "tier-2 boon locked at account level 1")
	var r2 := DSRunState.new_run(data, "warrior", 1, DSMeta.perks(data, 7))
	assert_true(r2.available_boons().has("momentum"))
	assert_true(r2.available_boons().has("keen_edge"))


func test_locked_legendaries_stay_out():
	var rng := DSRng.new(3)
	for i in 60:
		var it := DSLoot.roll_item(data, rng, 5, "weapon", "legendary", "warrior", 1)
		assert_ne(it.get("passive"), "phantom_edge")


func test_perks_survive_save():
	var r := DSRunState.new_run(data, "warrior", 1, DSMeta.perks(data, 5))
	var r2 := DSRunState.from_dict(data, JSON.parse_string(JSON.stringify(r.to_dict())))
	assert_eq(r2.rule_slots(), r.rule_slots())
	assert_eq(int(r2.perks["hp_pct"]), int(r.perks["hp_pct"]))
