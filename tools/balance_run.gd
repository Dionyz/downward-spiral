extends SceneTree
## Full-run balance (spec milestone 6): N autopilot runs per class with default rules.
##   godot --headless --path . -s tools/balance_run.gd -- [--runs 1000]
## Prints win rate, average floor/level, and where runs die (floor and room type).
## Exits 1 if class win rates are more than 10 points apart.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var runs := 1000
	for i in args.size():
		if args[i] == "--runs" and i + 1 < args.size():
			runs = int(args[i + 1])
	var data := DSData.load_dir("res://game/data")
	var rates: Array = []
	print("class     win%   floor  level   deaths by floor 1-6          deaths by room")
	for line in ["warrior", "thief", "mage", "knifer"]:
		var wins := 0
		var floors := 0
		var levels := 0
		var by_floor := [0, 0, 0, 0, 0, 0]
		var by_room := {}
		for r in runs:
			var run := DSAutopilot.play(DSRunState.new_run(data, line, 5000 + r * 13))
			floors += run.floor_num
			levels += run.level
			if run.result == "victory":
				wins += 1
			else:
				by_floor[run.floor_num - 1] += 1
				var t := str(run.room.get("type", "?"))
				by_room[t] = int(by_room.get(t, 0)) + 1
		var rate := 100.0 * wins / runs
		rates.append(rate)
		print("%-8s %5.1f  %5.2f  %5.2f   %s   %s" % [line, rate, float(floors) / runs, float(levels) / runs,
			" ".join(PackedStringArray(by_floor.map(func(x): return "%4d" % x))), str(by_room)])
	var spread: float = rates.max() - rates.min()
	print("spread: %.1f points (target <= 10)" % spread)
	quit(0 if spread <= 10.0 else 1)
