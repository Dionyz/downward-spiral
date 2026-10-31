extends Control
## End of the prototype run.


func _ready() -> void:
	var v := UI.screen(self)
	v.add_child(UI.spacer())
	var msg := {"win": "Floor cleared.", "loss": "You have fallen.", "extract": "You climb back to the light."}
	var t := UI.label(str(msg.get(Game.result, "The run is over.")), 44, UI.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UI.label("Fights won: %d · Level reached: %d · Seed %d" % [Game.fights_won, Game.level, Game.seed_value], 20, UI.DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	v.add_child(UI.spacer())
	v.add_child(UI.button("New Run", func(): Game.goto("class_select"), 80))
	v.add_child(UI.button("Title", func(): Game.goto("title"), 56))
	if Game.autoplay != "":
		print("[autoplay] run_end: %s, fights won %d, level %d" % [Game.result, Game.fights_won, Game.level])
		Game.auto_next("run_end", func(): get_tree().quit())
