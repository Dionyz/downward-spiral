extends Control
## End of a run: death, extraction or victory. Banks XP (and gold if kept) into the account.


func _ready() -> void:
	var run: DSRunState = Game.run
	var bank := Game.finish_run()
	var v := UI.screen(self)
	v.add_child(UI.spacer())
	var msg := {"death": "You have fallen.", "extract": "You climb back to the light.", "victory": "The Spiral is broken."}
	var t := UI.label(str(msg.get(run.result, "The run is over.")), 44, UI.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var L: Dictionary = Game.data.classes.get(run.line, {})
	var lines := [
		"%s · reached floor %d · level %d" % [str(L.get("display", run.line)), run.floor_num, run.level],
		"Fights %d · Kills %d · Gold found %d" % [int(run.stats["fights"]), int(run.stats["kills"]), int(run.stats["gold_earned"])],
		"Banked: %d account XP%s" % [int(bank.get("xp", 0)), (" and %d gold" % int(bank["gold"])) if int(bank.get("gold", 0)) > 0 else ""],
	]
	if run.result == "death":
		lines.append("Death keeps half your XP and none of the gold.")
	lines.append("Account: %d XP · %d gold · %d runs" % [int(Game.account.get("xp", 0)), int(Game.account.get("gold", 0)), int(Game.account.get("runs", 0))])
	for l in lines:
		var s := UI.label(l, 20, UI.DIM)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(s)
	v.add_child(UI.spacer())
	v.add_child(UI.button("New Run", func(): Game.goto("class_select"), 80))
	v.add_child(UI.button("Title", func(): Game.goto("title"), 56))
	if Game.autoplay != "":
		print("[autoplay] run_end: %s, floor %d, level %d, banked %s" % [run.result, run.floor_num, run.level, str(bank)])
		Game.auto_next("run_end", func(): get_tree().quit())
