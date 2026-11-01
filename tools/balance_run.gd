extends SceneTree
## Full-run balance: N autopilot runs per class through one dungeon (no account power-ups, no stash
## gear, all boons open, autopilot drinks potions at 30% HP and takes the first boon).
##   godot --headless --path . -s tools/balance_run.gd -- [--runs 200] [--classes warrior,thief] [--seed0 5000]
##       [--mastery 1] [--dungeon spiral]
## --mastery is the class mastery the run starts at (1 = a fresh character; 10 = everything learned).
## Prints win rate, average floor/level/turns, deaths per floor, and how often the killer was an
## elite or the boss. Exits 1 if class win rates are more than 10 points apart.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var runs := 200
	var classes := ["warrior", "thief", "mage", "knifer"]
	var seed0 := 5000
	var mastery := 1
	var dungeon := "spiral"
	for i in args.size():
		if args[i] == "--runs" and i + 1 < args.size():
			runs = int(args[i + 1])
		if args[i] == "--classes" and i + 1 < args.size():
			classes = Array(args[i + 1].split(","))
		if args[i] == "--seed0" and i + 1 < args.size():
			seed0 = int(args[i + 1])
		if args[i] == "--mastery" and i + 1 < args.size():
			mastery = int(args[i + 1])
		if args[i] == "--dungeon" and i + 1 < args.size():
			dungeon = str(args[i + 1])
	var data := DSData.load_dir("res://game/data")
	var rates: Array = []
	var nfloors := int(data.dungeons.get("floors", 10))
	print("dungeon %s, mastery %d, seeds %d+13n" % [dungeon, mastery, seed0])
	print("class     win%%   floor  level  turns  deaths by floor 1-%d   killed by elite/boss" % nfloors)
	for line in classes:
		var wins := 0
		var floors := 0
		var levels := 0
		var turns := 0
		var by_floor: Array = []
		by_floor.resize(nfloors)
		by_floor.fill(0)
		var elite_deaths := 0
		var boss_deaths := 0
		var t0 := Time.get_ticks_msec()
		for r in runs:
			var perks := DSMeta.perks(data, {})
			perks["mastery"] = mastery
			var run := DSRunState.new_run(data, str(line), seed0 + r * 13, perks, "human", {}, dungeon, false)
			var n := 0
			while run.phase != "over" and n < 30000:
				DSAutopilot.advance(run)
				n += 1
			floors += run.floor_num
			levels += run.level
			turns += run.world.turn if run.world != null else 0
			if run.result == "victory":
				wins += 1
			else:
				by_floor[clampi(run.floor_num - 1, 0, nfloors - 1)] += 1
				if run.world != null:
					for m in run.world.monsters:
						if m["c"].is_alive() and m["state"] == "hunt" and DSWorld.cheb(m["pos"], run.world.ppos) <= 2:
							if m["boss"]:
								boss_deaths += 1
								break
							if m["elite"]:
								elite_deaths += 1
								break
		var rate := 100.0 * wins / runs
		rates.append(rate)
		print("%-8s %5.1f  %5.2f  %5.2f  %5d  %s   elite %d boss %d   (%.1fs)" % [line, rate, float(floors) / runs, float(levels) / runs,
			turns / runs, " ".join(PackedStringArray(by_floor.map(func(x): return "%3d" % x))), elite_deaths, boss_deaths,
			(Time.get_ticks_msec() - t0) / 1000.0])
	var spread: float = rates.max() - rates.min()
	print("spread: %.1f points (target <= 10)" % spread)
	quit(0 if spread <= 10.0 else 1)
