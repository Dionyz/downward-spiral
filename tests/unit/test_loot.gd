extends GutTest
## Item generation: our own stats, rarity tiers, legendary passives.

const H = preload("res://tests/helpers.gd")
var data: DSData


func before_each():
	data = H.data()


func test_same_seed_same_item():
	var a := DSLoot.roll_item(data, DSRng.new(5), 4)
	var b := DSLoot.roll_item(data, DSRng.new(5), 4)
	assert_eq(JSON.stringify(a), JSON.stringify(b))


func test_every_slot_and_rarity_rolls():
	var rng := DSRng.new(1)
	for slot in ["weapon", "armor", "trinket"]:
		for rar in ["common", "uncommon", "rare", "epic", "legendary"]:
			var it := DSLoot.roll_item(data, rng, 5, slot, rar, "warrior")
			assert_eq(it["slot"], slot)
			assert_ne(str(it["name"]), "", "%s %s has a name" % [rar, slot])


func test_only_legendaries_have_passives():
	var rng := DSRng.new(2)
	for i in 50:
		var it := DSLoot.roll_item(data, rng, 5, "", "epic")
		assert_false(it.has("passive"))
		var lg := DSLoot.roll_item(data, rng, 5, "", "legendary")
		assert_true(lg.has("passive"), "legendary %s has a special passive" % lg["slot"])
		assert_true(data.items["legendary_passives"].has(lg["passive"]))


func test_deeper_items_are_better():
	var rng := DSRng.new(3)
	var lo := 0
	var hi := 0
	for i in 40:
		lo += DSLoot.roll_item(data, rng, 1, "weapon", "common", "warrior")["power"]
		hi += DSLoot.roll_item(data, rng, 8, "weapon", "common", "warrior")["power"]
	assert_gt(hi, lo * 3)


func test_rarer_is_stronger_at_same_level():
	var rng := DSRng.new(4)
	var c := DSLoot.roll_item(data, rng, 5, "armor", "common")
	var l := DSLoot.roll_item(data, rng, 5, "armor", "legendary")
	assert_gt(l["power"], c["power"])


func test_rarity_weights_roughly_hold():
	var rng := DSRng.new(9)
	var counts := {}
	for i in 4000:
		var r := DSLoot.roll_rarity(data, rng)
		counts[r] = int(counts.get(r, 0)) + 1
	assert_gt(int(counts.get("common", 0)), 2000)
	assert_lt(int(counts.get("legendary", 0)), 80)


func test_class_weapon_types():
	var rng := DSRng.new(6)
	for i in 20:
		assert_eq(DSLoot.roll_item(data, rng, 3, "weapon", "", "thief")["type"], "dagger")


func test_items_apply_to_player():
	var rng := DSRng.new(7)
	var armor := DSLoot.roll_item(data, rng, 5, "armor", "rare")
	var plain := DSFactory.make_player(data, "warrior", 1, 5)
	var geared := DSFactory.make_player(data, "warrior", 1, 5, {"armor": armor})
	assert_lt(geared.ac, plain.ac, "armor lowers AC")


func test_quickened_legendary_hastes():
	var trinket := {"slot": "trinket", "passive": "quickened", "skill_bonus": {}}
	var p := DSFactory.make_player(data, "mage", 1, 1, {"trinket": trinket})
	assert_true(p.has_status("haste"))
