extends SceneTree
## Prints a full text combat log. Milestone 2 deliverable.
##
##   godot --headless --path . -s tools/combat_log.gd -- [--class warrior] [--level 1] [--seed 42]
##         [--enemy goblin_cutter] [--count 3] [--enemy-level 1]


func _init() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	var data := DSData.load_dir("res://game/data")
	var rng := DSRng.new(int(args.get("seed", "42")))
	var line := str(args.get("class", "warrior"))
	var level := int(args.get("level", "1"))
	var p := DSFactory.make_player(data, line, int(args.get("tier", "1")), level, {"rule_slots": int(args.get("slots", "4"))})
	var foes: Array = []
	var count := int(args.get("count", "3"))
	var eid := str(args.get("enemy", "goblin_cutter"))
	for i in count:
		var m := DSFactory.make_monster(data, eid, int(args.get("enemy-level", str(level))), i)
		if count > 1:
			m.name = "%s #%d" % [m.name, i + 1]
		foes.append(m)
	var sim := CombatSim.new(rng, data)
	print("%s L%d  HP %d  mana %d  weapon %s  actives %s" % [p.flags.get("class_name", line), level, p.max_hp, p.max_mana,
		p.weapon.get("type", "-") if p.weapon != null else "-", str(p.actives)])
	for r in p.rules:
		print("  rule: " + DSRules.describe(r))
	var history := sim.run(p, foes)
	for l in CombatText.render(history):
		print(l)
	print("Result: %s in %d rounds. HP %d/%d" % [sim.result, sim.round_num, p.hp, p.max_hp])
	quit(0 if sim.result != "" else 1)


func _parse(argv: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < argv.size():
		var a := argv[i]
		if a.begins_with("--") and i + 1 < argv.size():
			out[a.substr(2)] = argv[i + 1]
			i += 2
		else:
			i += 1
	return out
