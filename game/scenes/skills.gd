extends Control
## Skills: every skill the class has, in the order the character tries them each turn. Drag a
## card onto another to move it (or use the arrows); switch skills off. Saved on the character;
## mid-run changes apply right away and are kept for later runs.

var line := ""
var level := 1
var order: Array = []          # skill names, top = tried first
var off: Array = []
var list: VBoxContainer
var skills: Array = []         # DSFactory.class_skills


func _ready() -> void:
	var ch := Game.character()
	var in_run := Game.run != null and Game.run.phase != "over" and Game.has_saved_run()
	line = str(Game.run.line if in_run else ch.get("line", "warrior"))
	level = Game.run.level if in_run else 1
	var saved_order: Array = (Game.run.skill_order if in_run else ch.get("skill_order", [])).duplicate()
	off = (Game.run.skill_off if in_run else ch.get("skill_off", [])).duplicate()
	skills = DSFactory.class_skills(Game.data, line, 3)
	order = saved_order.filter(func(n): return skills.any(func(s): return s["name"] == n))
	for s in skills:
		if not order.has(s["name"]):
			order.append(s["name"])
	var v := UI.screen(self)
	v.add_child(UI.label("Skills", 34, UI.ACCENT))
	v.add_child(UI.label("Your character tries these top to bottom every turn and uses the first one that's ready and makes sense. Drag to reorder; switch off what you don't want used.", 16, UI.DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	v.add_child(scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var reset := UI.button("Reset to default", func():
		order = skills.map(func(s): return s["name"])
		off = []
		_save(true)
		_refresh(), 56)
	var back := UI.button("Back", func(): Game.goto("dungeon" if in_run else "town"), 56)
	for b in [reset, back]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	v.add_child(row)
	_refresh()
	if Game.autoplay != "":
		Game.auto_next("skills", func(): Game.goto("town"))


func _skill(name: String) -> Dictionary:
	for s in skills:
		if s["name"] == name:
			return s
	return {}


func _refresh() -> void:
	for c in list.get_children():
		c.queue_free()
	for i in order.size():
		list.add_child(_card(i, _skill(str(order[i]))))


func _card(i: int, s: Dictionary) -> SkillCard:
	var card := SkillCard.new()
	card.index = i
	card.set_meta("skill_name", s["name"])
	card.moved.connect(_move)
	var nm: String = s["name"]
	var is_off := off.has(nm)
	var locked := int(s["unlock"]) > level
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var grip := UI.label("%d ≡" % (i + 1), 20, UI.DIM, false)
	grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(grip)
	var title := UI.label(nm.capitalize(), 22, UI.DIM if is_off else UI.ACCENT, false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)
	var up := UI.button("▲", func(): _move(i, i - 1), 40)
	up.disabled = i == 0
	var dn := UI.button("▼", func(): _move(i, i + 1), 40)
	dn.disabled = i == order.size() - 1
	var tog := UI.button("Off" if is_off else "On", func(): _toggle(nm), 40)
	tog.add_theme_color_override("font_color", UI.WARN if is_off else Color("#7fc8a9"))
	for b in [up, dn, tog]:
		b.custom_minimum_size.x = 52
		head.add_child(b)
	v.add_child(head)
	var a: Dictionary = Game.data.ability(nm)
	var bits: Array = []
	var cd := int(a["cooldown"]) if a.has("cooldown") else DSStats.cooldown_rounds(int(a.get("beats", 0)), Game.data.balance)
	bits.append("Cooldown: %s" % ("none" if cd <= 0 else ("%d turn%s" % [cd, "" if cd == 1 else "s"])))
	var cost := DSStats.mana_cost(int(a.get("min_mana", 0)), Game.data.balance) if line == "mage" else 0
	bits.append("Cost: %s" % ("%d mana" % cost if cost > 0 else "free"))
	if locked:
		bits.append("unlocks at level %d" % int(s["unlock"]))
	var meta := UI.label(" · ".join(PackedStringArray(bits)), 15, UI.WARN if locked else UI.DIM)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(meta)
	var d := UI.label(str(Game.data.skills.get(nm, "")), 17, UI.DIM if is_off else UI.TEXT)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(d)
	var whens: Array = s["rules"].map(func(r): return DSRules.plain(r))
	var w := UI.label("Used " + "; or ".join(PackedStringArray(whens)) + ".", 15, Color("#7fc8a9"))
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(w)
	if is_off:
		card.modulate = Color(1, 1, 1, 0.6)
	return card


func _move(from: int, to: int) -> void:
	if to < 0 or to >= order.size() or from == to:
		return
	var n = order[from]
	order.remove_at(from)
	order.insert(to, n)
	_save()
	_refresh()


func _toggle(nm: String) -> void:
	if off.has(nm):
		off.erase(nm)
	else:
		off.append(nm)
	_save()
	_refresh()


## Saves to the character (for future runs) and, mid-run, to the run (applies right away).
func _save(reset: bool = false) -> void:
	var o: Array = [] if reset else order.duplicate()
	var ch := Game.character()
	if not ch.is_empty():
		ch["skill_order"] = o
		ch["skill_off"] = off.duplicate()
		Game.save_account()
	if Game.run != null and Game.run.phase != "over" and Game.has_saved_run():
		Game.run.skill_order = o
		Game.run.skill_off = off.duplicate()
		Game.run._sync_to_world()
		Game.save_run()
