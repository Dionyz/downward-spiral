extends Control
## The town between runs. Talk to the people here: the Innkeeper (characters), the Quartermaster
## (buy and sell gear), the Stash (your shared storage and the current character's gear), the
## Trainer (power-ups), and the Spiral Gate to start a run.

const NPCS := [
	["gate", "The Spiral Gate", "Descend with your current character.", "town_gate", "#d6a64f"],
	["inn", "The Innkeeper", "Your characters: switch, create (up to 10) or retire.", "town_inn", "#ff9a2e"],
	["stash", "The Stash", "Shared storage. Equip your character, sell in bulk.", "town_stash", "#7fc8a9"],
	["shop", "The Quartermaster", "Sells gear (sell yours at the Stash). New stock after every run.", "town_shop", "#5f9fd3"],
	["trainer", "The Trainer", "Power-ups for every character, paid in gold.", "town_trainer", "#9d7cf2"],
]


func _ready() -> void:
	if Game.autoplay != "":
		Game.autoplay_character()
	var v := UI.screen(self)
	var top := HBoxContainer.new()
	var t := UI.label("Town", 36, UI.ACCENT, false)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	top.add_child(UI.icon("town_coins", 28, UI.ACCENT))
	top.add_child(UI.label(" %d gold" % int(Game.account.get("gold", 0)), 22, UI.ACCENT, false))
	v.add_child(top)
	v.add_child(_character_card())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	v.add_child(scroll)
	var has_char := not Game.character().is_empty()
	for n in NPCS:
		list.add_child(_npc(n, has_char or n[0] == "inn"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for b in [UI.button("Settings", func(): Game.goto("settings"), 52), UI.button("Title", func(): Game.goto("title"), 52)]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	v.add_child(row)
	Hint.show(self, "town")
	if Game.autoplay != "":
		print("[autoplay] town")
		Game.auto_next("town", _descend)
	elif not has_char:
		Game.goto.call_deferred("create")


func _character_card() -> PanelContainer:
	var card := PanelContainer.new()
	var ch := Game.character()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	card.add_child(h)
	if ch.is_empty():
		var nl := UI.label("No character yet. Visit the Innkeeper to create one.", 18, UI.DIM)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nl)
		return card
	var L: Dictionary = Game.data.classes.get(ch["line"], {})
	h.add_child(UI.icon("class_" + str(ch["line"]), 64, Color(str(L.get("color", "#d6a64f")))))
	var cv := VBoxContainer.new()
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(cv)
	cv.add_child(UI.label(str(ch["name"]), 26, UI.TEXT, false))
	var R: Dictionary = Game.data.races.get(ch["race"], {})
	cv.add_child(UI.label("%s %s · %d runs · best floor %d" % [str(R.get("name", ch["race"])), str(L.get("display", ch["line"])),
		int(ch.get("runs", 0)), int(ch.get("best_floor", 0))], 17, UI.DIM))
	var gear: Array = []
	for s in DSAccount.SLOTS:
		var it = ch["loadout"].get(s)
		if it != null:
			gear.append(str(it.get("name", "?")))
	var gl := UI.label("Gear: " + (", ".join(PackedStringArray(gear)) if not gear.is_empty() else "none"), 16, UI.DIM)
	gl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.add_child(gl)
	return card


func _npc(n: Array, enabled: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 92)
	b.disabled = not enabled
	b.pressed.connect(func(): Game.sfx("click"))
	b.pressed.connect(func(): _visit(str(n[0])))
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(h)
	var ic := UI.icon(str(n[3]), 56, Color(str(n[4])))
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)
	var cv := VBoxContainer.new()
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(cv)
	var nl := UI.label(str(n[1]), 24, Color(str(n[4])), false)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(nl)
	var dl := UI.label(str(n[2]), 16, UI.DIM)
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(dl)
	return b


func _visit(id: String) -> void:
	match id:
		"gate":
			_descend()
		"inn":
			Game.goto("characters")
		"stash":
			Game.goto("stash")
		"shop":
			Game.goto("shop")
		"trainer":
			Game.goto("upgrades")


func _descend() -> void:
	if Game.character().is_empty():
		return
	var args := OS.get_cmdline_user_args()
	var si := args.find("--seed")
	Game.new_run(int(args[si + 1]) if si >= 0 and si + 1 < args.size() else 0)
	Game.goto("dungeon")
