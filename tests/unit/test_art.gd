extends GutTest
## Every monster, class/race and dungeon theme has its pixel art, and lookups resolve.

const H = preload("res://tests/helpers.gd")
var data: DSData


func before_each():
	data = H.data()


func test_every_monster_has_a_sprite():
	for id in data.monsters.keys():
		assert_true(Art.has("monsters/" + str(id)), str(id))


func test_every_class_and_race_has_a_player_sprite():
	for line in ["warrior", "thief", "mage", "knifer"]:
		for race in data.races.keys():
			assert_true(Art.has("player/%s_%s" % [line, race]), "%s %s" % [line, race])
	assert_eq(Art.player("mage", "no_such_race"), "player/mage_human")


func test_every_dungeon_theme_has_tiles():
	for theme in ["spiral", "deep_spiral", "black_spiral", "abyss"]:
		for kind in ["floor", "corridor", "wall"]:
			assert_gt(Art.tiles(theme, kind).size(), 0, "%s %s" % [theme, kind])


func test_items_resolve_to_pictures():
	var rng := DSRng.new(3)
	for slot in ["weapon", "armor", "trinket"]:
		for i in 20:
			var it := DSLoot.roll_item(data, rng, 1 + i % 10, slot)
			var id := Art.item(data, it)
			assert_true(Art.has(id), "%s -> %s" % [str(it.get("name")), id])
	# Old saves have no "base": the name still finds the picture.
	assert_eq(Art.item(data, {"slot": "armor", "name": "Brutal Hauberk of the Fox"}), "items/armor_hauberk")
