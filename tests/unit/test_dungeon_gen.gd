extends GutTest
## Rogue-style floors: the spec's 1,000-seed generator test, now for tile levels.


func test_levels_hold_over_1000_seeds():
	var data := DSData.load_dir("res://game/data")
	var bad: Array = []
	for seed_value in range(1, 1001):
		var fl := 1 + seed_value % 6
		var lv := DSLevelGen.generate(data, DSRng.new(seed_value), fl)
		var tag := "seed %d floor %d" % [seed_value, fl]
		if not DSLevelGen.fully_connected(lv):
			bad.append("%s: not connected" % tag)
		var rows: Array = lv["tiles"]
		var at := func(x: int, y: int) -> String: return str(rows[y]).substr(x, 1)
		var s: Array = lv["start"]
		var st: Array = lv["stairs"]
		if at.call(int(s[0]), int(s[1])) == " " or at.call(int(st[0]), int(st[1])) == " ":
			bad.append("%s: start/stairs in rock" % tag)
		if s == st:
			bad.append("%s: start on stairs" % tag)
		for o in lv["objects"]:
			if at.call(int(o["x"]), int(o["y"])) == " ":
				bad.append("%s: object in rock" % tag)
		var elites := 0
		var bosses := 0
		for sp in lv["spawns"]:
			if at.call(int(sp["x"]), int(sp["y"])) == " ":
				bad.append("%s: monster in rock" % tag)
			if [int(sp["x"]), int(sp["y"])] == [int(s[0]), int(s[1])]:
				bad.append("%s: monster on start" % tag)
			elites += 1 if sp.get("elite", false) else 0
			bosses += 1 if sp.get("boss", false) else 0
		if fl in [2, 4] and elites != 1:
			bad.append("%s: %d elites" % [tag, elites])
		if fl == 6 and bosses != 1:
			bad.append("%s: %d bosses" % [tag, bosses])
		if lv["rooms"].size() < 6:
			bad.append("%s: only %d rooms" % [tag, lv["rooms"].size()])
	assert_eq(bad.slice(0, 10), [], "%d violations" % bad.size())


func test_same_seed_same_level():
	var data := DSData.load_dir("res://game/data")
	var a := DSLevelGen.generate(data, DSRng.new(77), 4)
	var b := DSLevelGen.generate(data, DSRng.new(77), 4)
	assert_eq(JSON.stringify(a), JSON.stringify(b))
