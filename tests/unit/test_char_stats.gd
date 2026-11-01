extends GutTest
## The in-run Character panel's numbers.

const H = preload("res://tests/helpers.gd")
var data: DSData


func before_each():
	data = H.data()


func test_sections_for_every_class():
	for line in ["warrior", "thief", "mage", "knifer"]:
		var run := DSRunState.new_run(data, line, 7)
		var secs := CharStats.sections(run)
		assert_eq(secs.size(), 4, line)
		for s in secs:
			assert_gt(s["rows"].size(), 0, "%s %s has rows" % [line, s["title"]])
			for r in s["rows"]:
				assert_ne(str(r[1]), "", "empty rows are dropped")


func test_shield_and_boons_show_up():
	var run := DSRunState.new_run(data, "warrior", 7)
	run.world.player.flags["b_bulwark"] = 6
	run.world.player.flags["shield_hp"] = 12
	var rows := {}
	for s in CharStats.sections(run):
		for r in s["rows"]:
			rows[r[0]] = r[1]
	assert_eq(rows.get("Shield"), "12")
	assert_true(rows.has("Shield after a hit"))
