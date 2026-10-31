extends Control
## Title screen.


func _ready() -> void:
	var v := UI.screen(self)
	v.add_child(UI.spacer())
	var logo := UI.icon("title", 220, UI.ACCENT)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(logo)
	var t := UI.label("DOWNWARD\nSPIRAL", 64, UI.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UI.label("A descent in rounds.", 22, UI.DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	v.add_child(UI.spacer())
	if Game.has_saved_run():
		v.add_child(UI.button("Continue run", _continue, 80))
	if Game.has_saved_run():
		var n := UI.label("Finish your run to return to town.", 16, UI.DIM)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(n)
	else:
		v.add_child(UI.button("Enter town" if not Game.account["characters"].is_empty() else "Create a character", _town, 80))
	v.add_child(UI.button("Settings and credits", func(): Game.goto("settings"), 56))
	var ver := UI.label("v1", 16, UI.DIM)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ver)
	if Game.autoplay != "":
		print("[autoplay] title")
		if OS.get_cmdline_user_args().has("--resume") and Game.has_saved_run():
			print("[autoplay] resuming saved run")
			Game.auto_next("title", _continue)
		else:
			Game.auto_next("title", _town)


func _continue() -> void:
	if Game.load_run():
		Game.goto("dungeon")


func _town() -> void:
	if Game.has_saved_run() and Game.autoplay == "":
		return   # finish (or die in) the saved run first: its gear is out of the stash
	Game.goto("town" if not Game.account["characters"].is_empty() or Game.autoplay != "" else "create")
