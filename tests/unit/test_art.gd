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


func test_every_boon_has_an_icon():
	for id in data.boons.keys():
		assert_eq(Art.boon(str(id)), "boons/" + str(id), str(id))
		assert_not_null(Art.tex("boons/" + str(id)), str(id))


func test_every_skill_on_the_skills_screen_has_an_icon():
	for line in ["warrior", "thief", "mage", "knifer"]:
		for s in DSFactory.class_skills(data, line, 99):
			var nm := str(s["name"])
			assert_ne(Art.skill(nm), "", "%s: %s" % [line, nm])
			assert_not_null(Art.tex(Art.skill(nm)), nm)


func test_every_status_has_an_icon():
	var needed := ["stunned", "knocked_down", "asleep", "blind", "poisoned", "bleeding", "slowed", "frozen",
		"transfixed", "armor", "shield", "sanctuary", "haste", "berserk", "warcry", "dazed", "envenomed"]
	for s in needed:
		assert_has(Art.STATUSES, s)
	for s in Art.STATUSES:
		var id := Art.status(str(s))
		assert_eq(id, "status/" + str(s), str(s))
		var t := Art.tex(id)
		assert_eq(t.get_size() if t != null else Vector2.ZERO, Vector2(16, 16), str(s))


func test_status_icons_follow_priority_and_limit():
	var c := Combatant.new()
	for s in ["warcry", "poisoned", "stunned", "haste", "slowed"]:
		c.add_status(s, 3)
	assert_eq(GridView.status_ids(c, 3), ["stunned", "slowed", "poisoned"])


func test_hit_effects_have_two_to_four_frames():
	for fx in ["slash", "hit", "crit", "bolt", "zap", "frost", "poison", "burst", "dark", "heal", "levelup"]:
		var n := Art.frames(fx).size()
		assert_between(n, 2, 4, fx)
	assert_eq(Art.frames("no_such_effect"), [])


func test_ui_glyphs_and_family_badges_resolve_and_tint():
	for g in Art.GLYPHS:
		assert_eq(Art.for_icon(g), "ui/" + g, g)
		assert_true(Art.tintable("ui/" + g), g)
	for f in data.families.keys():
		assert_eq(Art.for_icon("family_" + str(f)), "ui/family_" + str(f))
		assert_true(Art.tintable("ui/family_" + str(f)))
	# World art is never tinted.
	assert_false(Art.tintable("monsters/ghoul"))
	assert_false(Art.tintable("ui/panel"))
	# A missing glyph still falls back to the SVG.
	assert_eq(Art.for_icon("ui_no_such_glyph"), "")


func test_ui_skin_builds_nine_patches_at_double_size():
	for n in ["panel", "popup", "chip", "button", "button_hover", "button_pressed", "button_disabled"]:
		var sb := Art.nine("ui/" + n, 4)
		assert_not_null(sb, n)
		if sb != null:
			assert_eq(sb.texture.get_size(), Art.tex("ui/" + n).get_size() * 2, n)
			assert_eq(sb.texture_margin_left, 8.0, n)
	for n in ["bar_bg", "bar_hp", "bar_mana", "bar_xp", "bar_enemy", "bar_shield"]:
		assert_not_null(Art.nine("ui/" + n, 2), n)
	assert_null(Art.nine("ui/no_such_skin", 4))
	assert_true(UI.skin("no_such_skin", StyleBoxFlat.new()) is StyleBoxFlat)


func test_title_banners_and_fonts():
	assert_eq(Art.tex("ui/title").get_size(), Vector2(192, 56))
	for d in data.dungeon_list():
		assert_eq(Art.tex("ui/banner_" + str(d["id"])).get_size(), Vector2(96, 48), str(d["id"]))
	assert_true(Art.has("ui/banner_abyss"))
	assert_not_null(UI.heading_font())
	assert_true(ResourceLoader.exists(UI.BODY_FONT))


func test_every_art_file_has_provenance_in_the_manifest():
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/assets/art/manifest.json"))
	var files: Array = []
	_pngs("res://game/assets/art", "", files)
	assert_gt(files.size(), 300)
	for f in files:
		assert_true(manifest.has(f), "%s.png has no manifest.json entry" % f)
	for k in manifest.keys():
		assert_has(["CC0-1.0", "OFL-1.1"], str(manifest[k].get("license", "")), str(k))


func _pngs(root: String, rel: String, out: Array) -> void:
	var d := DirAccess.open(root + ("/" + rel if rel != "" else ""))
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".png"):
			out.append((rel + "/" if rel != "" else "") + f.get_basename())
	for sub in d.get_directories():
		_pngs(root, (rel + "/" if rel != "" else "") + sub, out)
