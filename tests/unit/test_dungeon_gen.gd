extends GutTest
## Spec: a generator test confirms room-count and type rules over 1,000 seeds.


func test_rules_hold_over_1000_seeds():
	var bad: Array = []
	for seed_value in range(1, 1001):
		for fl in range(1, 7):
			var rng := DSRng.new(seed_value * 10 + fl)
			var f := DSDungeonGen.generate(rng, fl)
			var spec: Array = DSDungeonGen.FLOORS[fl]
			var steps: Array = f["steps"]
			var tag := "seed %d floor %d" % [seed_value, fl]
			if steps.size() < int(spec[0]) or steps.size() > int(spec[1]):
				bad.append("%s: %d rooms" % [tag, steps.size()])
			var forks := steps.filter(func(s): return s.size() > 1).size()
			if forks > 1 or (steps.size() < 4 and forks > 0):
				bad.append("%s: %d forks" % [tag, forks])
			if steps[steps.size() - 1].size() != 1:
				bad.append("%s: ending room forks" % tag)
			for path in DSDungeonGen.paths(f):
				if path[path.size() - 1] != spec[2]:
					bad.append("%s: ends with %s" % [tag, path[path.size() - 1]])
				var fights := path.filter(func(t): return t in ["fight", "elite", "boss"]).size()
				if fights * 2 < path.size():
					bad.append("%s: too few fights %s" % [tag, str(path)])
				for i in range(1, path.size()):
					if path[i] == "rest" and path[i - 1] == "rest":
						bad.append("%s: rests in a row %s" % [tag, str(path)])
	assert_eq(bad.slice(0, 10), [], "%d violations" % bad.size())


func test_same_seed_same_floor():
	var a := DSDungeonGen.generate(DSRng.new(77), 4)
	var b := DSDungeonGen.generate(DSRng.new(77), 4)
	assert_eq(JSON.stringify(a), JSON.stringify(b))


func test_rooms_have_names():
	var f := DSDungeonGen.generate(DSRng.new(3), 5)
	for step in f["steps"]:
		for room in step:
			assert_ne(room["name"], "")
			assert_ne(room["desc"], "")
