class_name Tip
extends RefCounted
## Glossary lookups and tap-for-tooltip. Any label can be made "tippable": tap (or hover) it and
## a short explanation from the guide pops up. Full entries live on the Guide screen.

static var _all: Array = []


## Every entry: glossary.json plus boon families and legendary powers.
static func entries() -> Array:
	if not _all.is_empty():
		return _all
	var data: DSData = Game.data
	_all = data.glossary.duplicate(true)
	for f in data.families.keys():
		var fam: Dictionary = data.families[f]
		var tiers: Array = []
		for th in ["2", "4", "6"]:
			tiers.append("%s boons: %s" % [th, str(fam["tiers"][th]["text"])])
		_all.append({"cat": "Boon families", "term": str(fam["name"]), "short": "%s family: %s" % [fam["name"], fam.get("desc", "")],
			"long": "%s\n%s\n(Counts distinct boons, not stacks.)" % [str(fam.get("desc", "")), "\n".join(PackedStringArray(tiers))],
			"keys": [str(fam["name"]).to_lower()]})
	var lp: Dictionary = data.items.get("legendary_passives", {})
	for k in lp.keys():
		_all.append({"cat": "Legendary powers", "term": str(lp[k].get("name", k)), "short": str(lp[k].get("desc", "")),
			"long": str(lp[k].get("desc", "")), "keys": [str(lp[k].get("name", k)).to_lower()]})
	for r in data.races.keys():
		var rd: Dictionary = data.races[r]
		_all.append({"cat": "Races", "term": str(rd["name"]), "short": str(rd.get("perk", "")),
			"long": "%s\n%s" % [str(rd.get("desc", "")), str(rd.get("perk", ""))], "keys": [str(rd["name"]).to_lower()]})
	return _all


## Best entry for a piece of UI text: the longest key the text starts with (or contains).
static func find(text: String) -> Dictionary:
	var t := text.to_lower().strip_edges().trim_prefix("+").trim_prefix("no ")
	var best := {}
	var best_len := 0
	for e in entries():
		for k in e["keys"]:
			var key := str(k)
			if key.length() > best_len and (t.begins_with(key) or (key.length() > 3 and t.contains(key))):
				best = e
				best_len = key.length()
	return best


## Make a label tappable: shows its glossary tip. Returns the label for chaining.
static func attach(l: Control, text: String = "") -> Control:
	var e := find(text if text != "" else str(l.get("text")))
	if e.is_empty():
		return l
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.mouse_default_cursor_shape = Control.CURSOR_HELP
	l.tooltip_text = str(e["short"])
	l.gui_input.connect(func(ev):
		if (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and ev.pressed):
			show_tip(l, e))
	return l


## Small card near the bottom of the screen; tap anywhere to close.
static func show_tip(from: Control, e: Dictionary) -> void:
	var root: Node = from.get_tree().current_scene
	var old := root.get_node_or_null("TipLayer")
	if old != null:
		old.queue_free()
	var layer := Control.new()
	layer.name = "TipLayer"
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.z_index = 150
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.gui_input.connect(func(ev):
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
			layer.queue_free())
	root.add_child(layer)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 24)
	m.add_theme_constant_override("margin_bottom", 120)
	layer.add_child(m)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(col)
	var card := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#221f2b")
	st.border_color = UI.ACCENT
	st.set_border_width_all(2)
	st.set_corner_radius_all(12)
	st.set_content_margin_all(16)
	card.add_theme_stylebox_override("panel", st)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(card)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	v.add_child(UI.label(str(e["term"]), 24, UI.ACCENT))
	v.add_child(UI.label(str(e["short"]), 19))
	v.add_child(UI.label("More in the Guide (Settings). Tap to close.", 14, UI.DIM))
