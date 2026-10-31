extends Control
## Title screen.


func _ready() -> void:
	var v := UI.screen(self)
	v.add_child(UI.spacer())
	var t := UI.label("DOWNWARD\nSPIRAL", 64, UI.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UI.label("A descent in rounds.", 22, UI.DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	v.add_child(UI.spacer())
	if Game.has_saved_run():
		v.add_child(UI.button("Continue", _continue, 80))
	v.add_child(UI.button("New Run", func(): Game.goto("class_select"), 80))
	var ver := UI.label("text prototype · milestone 5", 16, UI.DIM)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ver)
	if Game.autoplay != "":
		print("[autoplay] title")
		if OS.get_cmdline_user_args().has("--resume") and Game.has_saved_run():
			print("[autoplay] resuming saved run")
			Game.auto_next("title", _continue)
		else:
			Game.auto_next("title", func(): Game.goto("class_select"))


func _continue() -> void:
	if Game.load_run():
		Game.goto("dungeon")
