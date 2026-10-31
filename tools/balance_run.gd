extends SceneTree
## Full-run balance: N autopilot runs per class with default rules.
##   godot --headless --path . -s tools/balance_run.gd -- [--runs 200]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var runs := 200
	for i in args.size():
		if args[i] == "--runs" and i + 1 < args.size():
			runs = int(args[i + 1])
	var data := DSData.load_dir("res://game/data")
	print("class     win%   avg floor  avg level  floor reached: 1   2   3   4   5   6")
	for line in ["warrior", "thief", "mage", "knifer"]:
		var wins := 0
		var floors := 0
		var levels := 0
		var reached := [0, 0, 0, 0, 0, 0]
		for r in runs:
			var run := DSAutopilot.play(DSRunState.new_run(data, line, 5000 + r * 13))
			wins += 1 if run.result == "victory" else 0
			floors += run.floor_num
			levels += run.level
			reached[run.floor_num - 1] += 1
		print("%-8s %5.1f %8.2f %10.2f   %s" % [line, 100.0 * wins / runs, float(floors) / runs, float(levels) / runs,
			"  ".join(PackedStringArray(reached.map(func(x): return "%3d" % x)))])
	quit()
