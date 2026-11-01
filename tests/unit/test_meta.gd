extends GutTest
## Between runs: town power-ups bought with gold (no account levels).

const H = preload("res://tests/helpers.gd")
var data: DSData


func before_each():
	data = H.data()


func test_everything_unlocked_from_the_start():
	var p := DSMeta.perks(data, {})
	assert_eq(p["classes"].size(), 4)
	var r := DSRunState.new_run(data, "warrior", 1, p)
	assert_true(r.available_boons().has("executioner"), "every boon open")
	assert_true(r.available_boons().has("last_stand"), "tier-3 boons open")


func test_power_ups_change_the_player():
	var base := DSRunState.new_run(data, "warrior", 1, DSMeta.perks(data, {})).make_player()
	var a := {"upgrades": {"vitality": 5, "provisions": 2}}
	var r := DSRunState.new_run(data, "warrior", 1, DSMeta.perks(data, a))
	var vet := r.make_player()
	assert_gt(vet.max_hp, base.max_hp)
	assert_eq(int(r.potions["hp"]), 5, "3 + 2 provisions")


func test_perks_survive_save():
	var r := DSRunState.new_run(data, "warrior", 1, DSMeta.perks(data, {"upgrades": {"vitality": 2}}), "dwarf")
	var r2 := DSRunState.from_dict(data, JSON.parse_string(JSON.stringify(r.to_dict())))
	assert_eq(r2.potions, r.potions)
	assert_eq(int(r2.perks["hp_pct"]), int(r.perks["hp_pct"]))
	assert_eq(r2.race, "dwarf")
	assert_eq(r2.make_player().max_hp, r.make_player().max_hp)


func test_upgrade_prices_double_and_cap():
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
	var b := {"gold": 100000}
	for i in 10:
		b = DSMeta.buy_upgrade(data, b, "provisions")
	assert_eq(DSMeta.owned(b, "provisions"), 3, "provisions cap at 3")


func test_upgrade_needs_gold():
	var a := {"gold": 50}
	assert_eq(DSMeta.buy_upgrade(data, a, "banish"), a, "can't afford")
	assert_eq(DSMeta.charges(data, {}), {"skip": 1, "reroll": 0, "banish": 0})


func test_locked_legendaries_param_still_works():
	var rng := DSRng.new(3)
	for i in 60:
		var it := DSLoot.roll_item(data, rng, 5, "weapon", "legendary", "warrior", 1)
		assert_ne(it.get("passive"), "phantom_edge")
