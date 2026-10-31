extends Control
## Pick a class line. All four are open in the prototype (account unlocks come in milestone 8).


func _ready() -> void:
	var v := UI.screen(self)
	v.add_child(UI.label("Choose your path", 36, UI.ACCENT))
	for line in ["warrior", "thief", "mage", "knifer"]:
		var L: Dictionary = Game.data.classes.get(line, {})
		var card := PanelContainer.new()
		var cv := VBoxContainer.new()
		card.add_child(cv)
		cv.add_child(UI.label(str(L.get("display", line)), 30, UI.TEXT))
		cv.add_child(UI.label(str(L.get("role", "")), 20, UI.DIM))
		var kit := "Starts with: " + ", ".join(PackedStringArray(L.get("starting_actives", [])))
		cv.add_child(UI.label(kit, 18, UI.DIM))
		var ln: String = line
		cv.add_child(UI.button("Descend as %s" % str(L.get("display", line)), func(): _start(ln), 56))
		v.add_child(card)
	v.add_child(UI.spacer())
	v.add_child(UI.button("Back", func(): Game.goto("title"), 56))
	if Game.autoplay != "":
		print("[autoplay] class_select -> %s" % Game.autoplay)
		Game.auto_next("class_select", func(): _start(Game.autoplay))


func _start(line: String) -> void:
	var args := OS.get_cmdline_user_args()
	var si := args.find("--seed")
	Game.new_run(line, int(args[si + 1]) if si >= 0 and si + 1 < args.size() else 0)
	Game.goto("dungeon")
