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
	assert_eq(r2.potions, r.potions)
	assert_eq(int(r2.perks["hp_pct"]), int(r.perks["hp_pct"]))


func test_account_potion_perks():
	var r1 := DSRunState.new_run(data, "warrior", 1, DSMeta.perks(data, 1))
	var r3 := DSRunState.new_run(data, "warrior", 1, DSMeta.perks(data, 3))
	assert_eq(int(r3.potions["hp"]), int(r1.potions["hp"]) + 1)


func test_upgrade_prices_double_and_cap_at_five():
	var a := {"gold": 10000}
	assert_eq(DSMeta.upgrade_price(data, a, "skip"), 100)
	a = DSMeta.buy_upgrade(data, a, "skip")
	assert_eq(DSMeta.owned(a, "skip"), 1)
	assert_eq(int(a["gold"]), 9900)
	assert_eq(DSMeta.upgrade_price(data, a, "skip"), 200)
	for i in 10:
		a = DSMeta.buy_upgrade(data, a, "skip")
	assert_eq(DSMeta.owned(a, "skip"), 5, "capped at 5")
	assert_eq(DSMeta.upgrade_price(data, a, "skip"), -1)
	assert_eq(DSMeta.charges(data, a)["skip"], 6, "1 base + 5 bought")


func test_upgrade_needs_gold():
	var a := {"gold": 50}
	assert_eq(DSMeta.buy_upgrade(data, a, "banish"), a, "can't afford")
	assert_eq(DSMeta.charges(data, {}), {"skip": 1, "reroll": 0, "banish": 0})
