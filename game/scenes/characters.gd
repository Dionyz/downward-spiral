extends Control
## The Innkeeper: your characters (up to 10). Pick who descends next, create new ones, or retire
## one (its gear goes to the stash).

var list: VBoxContainer
var _confirm := -1


func _ready() -> void:
	var v := UI.screen(self)
	v.add_child(UI.label("The Innkeeper", 34, Color("#ff9a2e")))
	v.add_child(UI.label("\"Who's going down this time?\"", 18, UI.DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	v.add_child(scroll)
	var full: bool = Game.account["characters"].size() >= DSAccount.max_characters(Game.data)
	var nb := UI.button("Full roster (%d)" % DSAccount.max_characters(Game.data) if full else "New character", func(): Game.goto("create"), 64)
	nb.disabled = full
	v.add_child(nb)
	v.add_child(UI.button("Back to town", func(): Game.goto("town"), 56))
	_refresh()


func _refresh() -> void:
	for c in list.get_children():
		c.queue_free()
	var chars: Array = Game.account["characters"]
	if chars.is_empty():
		list.add_child(UI.label("No characters yet.", 20, UI.DIM))
	for i in chars.size():
		list.add_child(_card(i, chars[i]))


func _card(i: int, ch: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	card.add_child(h)
	var L: Dictionary = Game.data.classes.get(ch["line"], {})
	h.add_child(UI.icon("class_" + str(ch["line"]), 52, Color(str(L.get("color", "#d6a64f")))))
	var cv := VBoxContainer.new()
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(cv)
	var cur := i == int(Game.account["current"])
	cv.add_child(UI.label(str(ch["name"]) + ("  (current)" if cur else ""), 22, UI.ACCENT if cur else UI.TEXT, false))
	var R: Dictionary = Game.data.races.get(ch["race"], {})
	cv.add_child(UI.label("%s %s · mastery %d · %d runs · best floor %d · %d wins" % [str(R.get("name", "")), str(L.get("display", "")),
		DSMeta.mastery_level(Game.data, Game.account, str(ch["line"])),
		int(ch.get("runs", 0)), int(ch.get("best_floor", 0)), int(ch.get("victories", 0))], 15, UI.DIM))
	var ii := i
	var pick := UI.button("Play", func():
		Game.account["current"] = ii
		Game.save_account()
		Game.goto("town"), 48)
	pick.disabled = cur
	h.add_child(pick)
	var del := UI.button("Sure?" if _confirm == i else "Retire", func(): _retire(ii), 48)
	del.add_theme_color_override("font_color", UI.WARN)
	h.add_child(del)
	return card


func _retire(i: int) -> void:
	if _confirm != i:
		_confirm = i
		_refresh()
		return
	_confirm = -1
	DSAccount.delete_character(Game.data, Game.account, i)
	Game.save_account()
	_refresh()
