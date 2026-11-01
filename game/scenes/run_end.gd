extends Control
## End of a run: death, extraction or victory. Brings gold and loot home (or loses it), then town.


func _ready() -> void:
	var run: DSRunState = Game.run
	var bank := Game.finish_run()
	var v := UI.screen(self)
	v.add_child(UI.spacer())
	var msg := {"death": "You have fallen.", "rescued": "Dragged out alive.", "extract": "You climb back to the light.", "victory": "The Spiral is broken."}
	var t := UI.label(str(msg.get(run.result, "The run is over.")), 44, UI.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var L: Dictionary = Game.data.classes.get(run.line, {})
	var ch := Game.character()
	var lines := [
		"%s the %s · reached floor %d · level %d" % [str(ch.get("name", "You")), str(L.get("display", run.line)), run.floor_num, run.level],
		"Kills %d · Gold found %d" % [int(run.stats["kills"]), int(run.stats["gold_earned"])],
	]
	if run.result == "rescued":
		lines.append("Something hauled you out of the dark as you fell. We're being kind this once: you keep the gear you brought in and %d gold (half your purse). Everything you found this run is lost." % int(bank.get("gold", 0)))
	elif run.result == "death":
		lines.append("Lost: %d gold and %d items you carried." % [run.gold, int(bank.get("lost", 0))])
	else:
		lines.append("Brought home: %d gold and %d items (equipped gear stays on, the rest is in the stash)." % [int(bank.get("gold", 0)), int(bank.get("items", 0))])
	lines.append("Town purse: %d gold" % int(Game.account.get("gold", 0)))
	for l in lines:
		var s := UI.label(l, 20, UI.DIM)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(s)
	if run.result == "rescued":
		var warn := PanelContainer.new()
		var st := StyleBoxFlat.new()
		st.bg_color = Color("#2a1414")
		st.border_color = UI.WARN
		st.set_border_width_all(2)
		st.set_corner_radius_all(10)
		st.set_content_margin_all(16)
		warn.add_theme_stylebox_override("panel", st)
		var wl := UI.label("This rescue happens only once, ever.\nFrom now on, dying loses everything you carry: your gold, everything you found, and the gear you brought in.\nUse Extract to get out with your loot.", 20, UI.WARN)
		wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn.add_child(wl)
		v.add_child(warn)
	v.add_child(UI.spacer())
	v.add_child(UI.button("Back to town", func(): Game.goto("town"), 80))
	Hint.show(self, "run_end")
	if Game.autoplay != "":
		print("[autoplay] run_end: %s, floor %d, level %d, bank %s" % [run.result, run.floor_num, run.level, str(bank)])
		if OS.get_cmdline_user_args().has("--town"):
			Game.auto_next("run_end", func(): Game.goto("stash"))
		else:
			Game.auto_next("run_end", func(): get_tree().quit())
