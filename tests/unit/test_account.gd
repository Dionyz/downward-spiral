extends GutTest
## Characters, the shared stash, the shop, races, and banking runs.

const H = preload("res://tests/helpers.gd")
var data: DSData


func before_each():
	data = H.data()


func test_eight_races_with_perks():
	assert_eq(data.races.size(), 8)
	for id in data.races.keys():
		var r: Dictionary = data.races[id]
		assert_true(str(r.get("perk", "")) != "", id)
		assert_eq(r["attributes"].size(), 5, id)


func test_races_change_the_character():
	var hu := DSRunState.new_run(data, "warrior", 1, {}, "human").make_player()
	var dw := DSRunState.new_run(data, "warrior", 1, {}, "dwarf").make_player()
	var gm := DSRunState.new_run(data, "warrior", 1, {}, "golem").make_player()
	var mi := DSRunState.new_run(data, "warrior", 1, {}, "minotaur").make_player()
	assert_gt(dw.max_hp, hu.max_hp, "dwarves are stout")
	assert_true(dw.resist.has("bash"))
	assert_eq(int(gm.flags.get("b_dr_flat", 0)), 2)
	assert_true(mi.immune.has("poison"))
	assert_eq(mi.size, "huge")


func test_up_to_ten_characters():
	var a := DSAccount.fresh()
	for i in 10:
		assert_true(DSAccount.create_character(data, a, "Hero %d" % i, "thief", "halfling"))
	assert_false(DSAccount.create_character(data, a, "Eleven", "mage", "human"), "roster full")
	assert_eq(a["characters"].size(), 10)
	assert_eq(int(a["current"]), 9)
	assert_false(DSAccount.create_character(data, DSAccount.fresh(), "  ", "mage", "human"), "needs a name")
	DSAccount.delete_character(data, a, 9)
	assert_eq(a["characters"].size(), 9)
	assert_eq(a["stash"].size(), 1, "deleted character's weapon goes to the stash")


func _bank(result: String) -> Dictionary:
	var a := DSAccount.fresh()
	DSAccount.create_character(data, a, "Ash", "warrior", "dwarf")
	var r := DSAccount.start_run(data, a, 7)
	assert_eq(r.race, "dwarf")
	assert_null(DSAccount.current(a)["loadout"]["weapon"], "the loadout is carried into the run")
	r.items["armor"] = DSLoot.roll_item(data, DSRng.new(1), 3, "armor", "rare", "warrior")
	r.inventory = [DSLoot.roll_item(data, DSRng.new(2), 3, "trinket", "", "warrior"), DSLoot.roll_item(data, DSRng.new(3), 3, "weapon", "", "warrior")]
	r.gold = 90
	r.floor_num = 3
	r.end_run(result)
	var out := DSAccount.bank_run(data, a, r)
	return {"a": a, "out": out}


func test_extract_brings_loot_home():
	var res := _bank("extract")
	var a: Dictionary = res["a"]
	var ch := DSAccount.current(a)
	assert_eq(int(a["gold"]), 90)
	assert_eq(a["stash"].size(), 2, "bag goes to the stash")
	assert_not_null(ch["loadout"]["armor"], "equipped gear comes back on the character")
	assert_eq(int(ch["best_floor"]), 3)


func test_death_loses_everything_carried():
	var res := _bank("death")
	var a: Dictionary = res["a"]
	var ch := DSAccount.current(a)
	assert_eq(int(a["gold"]), 0)
	assert_eq(a["stash"].size(), 0)
	assert_null(ch["loadout"]["armor"])
	assert_not_null(ch["loadout"]["weapon"], "a plain starting weapon so the character can go again")
	assert_eq(int(res["out"]["lost"]), 4, "weapon, armor and 2 bag items")


func test_stash_loadout_and_shared_between_characters():
	var a := DSAccount.fresh()
	DSAccount.create_character(data, a, "One", "warrior", "human")
	DSAccount.create_character(data, a, "Two", "mage", "high_elf")
	var armor := DSLoot.roll_item(data, DSRng.new(4), 2, "armor", "rare", "")
	DSAccount.stash_add(data, a, [armor])
	a["current"] = 1
	assert_true(DSAccount.equip_from_stash(a, 0))
	assert_eq(DSAccount.current(a)["loadout"]["armor"], armor)
	assert_eq(a["stash"].size(), 0)
	assert_true(DSAccount.unequip(a, "armor"))
	assert_eq(a["stash"].size(), 1)
	assert_false(DSAccount.unequip(a, "weapon"), "weapon slot can't be empty")


func test_sell_and_bulk_sell():
	var a := DSAccount.fresh()
	DSAccount.create_character(data, a, "One", "warrior", "human")
	var rng := DSRng.new(9)
	for i in 6:
		DSAccount.stash_add(data, a, [DSLoot.roll_item(data, rng, 2, ["armor", "trinket"][i % 2], "common", "warrior")])
	DSAccount.stash_add(data, a, [DSLoot.roll_item(data, rng, 2, "", "rare", "warrior")])
	var g := DSAccount.sell(data, a, 0)
	assert_gt(g, 0)
	var res := DSAccount.bulk_sell(data, a, ["common"])
	assert_eq(int(res["count"]), 5)
	assert_eq(a["stash"].size(), 1, "the rare stays")
	assert_eq(int(a["gold"]), g + int(res["gold"]))


func test_shop_buy():
	var a := DSAccount.fresh()
	DSAccount.create_character(data, a, "One", "thief", "human")
	DSAccount.roll_shop(data, a, DSRng.new(5))
	assert_eq(a["shop"].size(), 6)
	assert_false(DSAccount.buy(data, a, 0), "no gold")
	a["gold"] = 100000
	var it: Dictionary = a["shop"][0]
	assert_true(DSAccount.buy(data, a, 0))
	assert_true(a["stash"].has(it))
	assert_eq(int(a["gold"]), 100000 - DSAccount.buy_price(data, it))
	assert_gt(DSAccount.buy_price(data, it), DSAccount.sell_value(data, it))


func test_migrates_old_saves():
	var a := DSAccount.migrate({"xp": 900, "gold": 40, "runs": 3})
	assert_false(a.has("xp"))
	assert_eq(int(a["gold"]), 40)
	assert_eq(a["characters"], [])


func test_bulk_sell_keeps_legendaries_and_upgrades():
	var a := DSAccount.fresh()
	DSAccount.create_character(data, a, "One", "warrior", "human")
	var weak := {"slot": "weapon", "rarity": "common", "min": 1, "max": 2, "flags": [], "name": "Stick"}
	var great := {"slot": "weapon", "rarity": "common", "min": 900, "max": 999, "flags": [], "name": "Godblade"}
	var leg := {"slot": "trinket", "rarity": "legendary", "flags": [], "name": "Relic", "passive": "x"}
	DSAccount.stash_add(data, a, [weak, great, leg])
	var pick := DSAccount.bulk_preview(data, a, ["common", "legendary"])
	assert_eq(pick, [0], "only the stick: the godblade is an upgrade, the relic is legendary")
	assert_eq(DSAccount.preview_gold(data, a, pick), DSAccount.sell_value(data, weak))


func test_class_mastery_unlocks_skills_and_grows():
	var a := DSAccount.fresh()
	DSAccount.create_character(data, a, "Ash", "warrior", "human")
	var r := DSAccount.start_run(data, a, 7)
	assert_eq(r.mastery, 1)
	var known := r.known_actives()
	assert_true(known.has("bash"))
	assert_false(known.has("charge"), "charge needs mastery 6")
	assert_false(known.has("berserk"), "berserk needs mastery 3")
	var p1 := r.make_player()
	r.level = 8
	assert_eq(r.known_actives(), known, "in-run levels no longer unlock skills")
	r.xp_total = 6400
	r.end_run("death")
	var out := DSAccount.bank_run(data, a, r)
	assert_eq(int(out["mastery_after"]), 4, "6400 XP = mastery 4")
	var r2 := DSAccount.start_run(data, a, 8)
	assert_true(r2.known_actives().has("berserk"))
	assert_gt(r2.make_player().skill("parry"), p1.skill("parry"), "mastery raises proficiency")
	DSAccount.create_character(data, a, "Bo", "warrior", "dwarf")
	assert_eq(DSMeta.mastery_level(data, a, "warrior"), 4, "mastery is shared by the class")
	assert_eq(DSMeta.mastery_level(data, a, "mage"), 1)


func test_dungeons_unlock_in_order_and_abyss_trophy():
	var a := DSAccount.fresh()
	DSAccount.create_character(data, a, "Ash", "warrior", "human")
	assert_true(DSAccount.dungeon_unlocked(data, a, "spiral"))
	assert_false(DSAccount.dungeon_unlocked(data, a, "deep_spiral"))
	assert_null(DSAccount.start_run(data, a, 3, "deep_spiral"), "locked")
	assert_null(DSAccount.start_run(data, a, 3, "spiral", true), "no Abyss before clearing")
	var r := DSAccount.start_run(data, a, 3, "spiral")
	r.end_run("victory")
	var out := DSAccount.bank_run(data, a, r)
	assert_eq(out.get("unlocked", ""), "deep_spiral")
	assert_true(DSAccount.dungeon_unlocked(data, a, "deep_spiral"))
	var ab := DSAccount.start_run(data, a, 4, "spiral", true)
	assert_true(ab.abyss)
	ab.end_run("victory")
	var out2 := DSAccount.bank_run(data, a, ab)
	assert_eq(out2.get("trophy", ""), "spiral")
	assert_true(a["abyss_cleared"].has("spiral"))
