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
		v.add_child(UI.button("Continue", _continue, 80))
	v.add_child(UI.button("New Run", func(): Game.goto("class_select"), 80))
	v.add_child(UI.button("Upgrades  (%d gold)" % int(Game.account.get("gold", 0)), func(): Game.goto("upgrades"), 64))
	v.add_child(UI.button("Settings and credits", func(): Game.goto("settings"), 56))
	var lvl := Game.account_level()
	var acct := UI.label("Account level %d · %d XP" % [lvl, int(Game.account.get("xp", 0))], 18, UI.DIM)
	acct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(acct)
	var ver := UI.label("v1", 16, UI.DIM)
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
