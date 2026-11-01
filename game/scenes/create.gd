extends Control
## Character creation: a name, a class and a race.

const NAMES := ["Aldric", "Brana", "Corvin", "Dessa", "Eamon", "Fenra", "Garrick", "Hesper", "Isolde", "Jorund",
	"Kael", "Liora", "Maddoc", "Nyx", "Orrin", "Perrin", "Quill", "Rhosyn", "Sable", "Tamsin", "Ulric", "Vesna", "Wren", "Yorick"]

var name_edit: LineEdit
var line := "warrior"
var race := "human"
var class_btns := {}
var race_btns := {}
var info: VBoxContainer
var create_btn: Button


func _ready() -> void:
	var v := UI.screen(self)
	v.add_child(UI.label("New character", 34, UI.ACCENT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 10)
	scroll.add_child(inner)
	v.add_child(scroll)

	inner.add_child(UI.label("Name", 18, UI.DIM))
	var nr := HBoxContainer.new()
	name_edit = LineEdit.new()
	name_edit.max_length = 16
	name_edit.custom_minimum_size = Vector2(0, 52)
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_size_override("font_size", 22)
	name_edit.text = NAMES[randi() % NAMES.size()]
	name_edit.text_changed.connect(func(_t): _update())
	nr.add_child(name_edit)
	nr.add_child(UI.button("Random", func():
		name_edit.text = NAMES[randi() % NAMES.size()]
		_update(), 52))
	inner.add_child(nr)

	inner.add_child(UI.label("Class", 18, UI.DIM))
	var cg := GridContainer.new()
	cg.columns = 2
	cg.add_theme_constant_override("h_separation", 8)
	cg.add_theme_constant_override("v_separation", 8)
	for l in ["warrior", "thief", "mage", "knifer"]:
		var L: Dictionary = Game.data.classes.get(l, {})
		var ll: String = l
		var b := UI.button(str(L.get("display", l)), func():
			line = ll
			_update(), 56)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.icon = load("res://game/assets/icons/class_%s.svg" % l)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 36)
		cg.add_child(b)
		class_btns[l] = b
	inner.add_child(cg)

	inner.add_child(UI.label("Race", 18, UI.DIM))
	var rg := GridContainer.new()
	rg.columns = 4
	rg.add_theme_constant_override("h_separation", 6)
	rg.add_theme_constant_override("v_separation", 6)
	for r in Game.data.races.keys():
		var rr: String = r
		var b := UI.button(str(Game.data.races[r].get("name", r)), func():
			race = rr
			_update(), 50)
		b.add_theme_font_size_override("font_size", 17)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rg.add_child(b)
		race_btns[r] = b
	inner.add_child(rg)

	info = VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	var ip := PanelContainer.new()
	ip.add_child(info)
	inner.add_child(ip)

	create_btn = UI.button("Create", _create, 68)
	v.add_child(create_btn)
	v.add_child(UI.button("Back", func(): Game.goto("characters" if not Game.account["characters"].is_empty() else "title"), 52))
	_update()
	Hint.show(self, "welcome")


func _update() -> void:
	for k in class_btns.keys():
		class_btns[k].button_pressed = k == line
	for k in race_btns.keys():
		race_btns[k].button_pressed = k == race
	for c in info.get_children():
		c.queue_free()
	var L: Dictionary = Game.data.classes.get(line, {})
	var R: Dictionary = Game.data.races.get(race, {})
	info.add_child(UI.label("%s %s" % [str(R.get("name", race)), str(L.get("display", line))], 24, Color(str(L.get("color", "#d6a64f")))))
	info.add_child(UI.label(str(L.get("role", "")), 17, UI.DIM))
	info.add_child(UI.label(str(R.get("desc", "")), 17))
	info.add_child(UI.label(str(R.get("perk", "")), 17, Color("#7fc8a9")))
	var res: Array = []
	for k in ["resist", "immune", "vuln"]:
		if not R.get(k, []).is_empty():
			res.append("%s: %s" % [{"resist": "Resists", "immune": "Immune to", "vuln": "Weak to"}[k], ", ".join(PackedStringArray(R[k]))])
	if not res.is_empty():
		info.add_child(UI.label(" · ".join(PackedStringArray(res)), 15, UI.DIM))
	var at: Dictionary = R.get("attributes", {})
	info.add_child(UI.label("Str %d · Int %d · Wis %d · Dex %d · Con %d · %s" % [int(at.get("str", 0)), int(at.get("int", 0)),
		int(at.get("wis", 0)), int(at.get("dex", 0)), int(at.get("con", 0)), str(R.get("size", "medium")).capitalize()], 15, UI.DIM))
	create_btn.disabled = name_edit.text.strip_edges() == ""


func _create() -> void:
	if DSAccount.create_character(Game.data, Game.account, name_edit.text, line, race):
		if Game.account["shop"].is_empty():
			DSAccount.roll_shop(Game.data, Game.account, DSRng.new(int(Time.get_ticks_usec()) % 2147483646 + 1))
		Game.save_account()
		Game.goto("town")
