extends Control
## The Guide: every stat, item property, status, race, family and term, with a search box.

static var back_to := "settings"
var list: VBoxContainer
var search: LineEdit


func _ready() -> void:
	var v := UI.screen(self)
	v.add_child(UI.label("Guide", 34, UI.ACCENT))
	search = LineEdit.new()
	search.placeholder_text = "Search (e.g. vorpal, frost, extract)"
	search.custom_minimum_size = Vector2(0, 52)
	search.add_theme_font_size_override("font_size", 20)
	search.text_changed.connect(func(_t): _refresh())
	v.add_child(search)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	v.add_child(scroll)
	v.add_child(UI.button("Back", func(): Game.goto(back_to), 56))
	_refresh()
	if Game.autoplay != "":
		Game.auto_next("guide", func(): Game.get_tree().quit())


func _refresh() -> void:
	for c in list.get_children():
		c.queue_free()
	var q := search.text.strip_edges().to_lower()
	var cat := ""
	for e in Tip.entries():
		if q != "" and not (str(e["term"]).to_lower().contains(q) or str(e["long"]).to_lower().contains(q)):
			continue
		if e["cat"] != cat:
			cat = str(e["cat"])
			list.add_child(UI.label(cat, 22, UI.DIM))
		var card := PanelContainer.new()
		var cv := VBoxContainer.new()
		card.add_child(cv)
		cv.add_child(UI.label(str(e["term"]), 20, UI.ACCENT))
		cv.add_child(UI.label(str(e["long"]), 17))
		list.add_child(card)
