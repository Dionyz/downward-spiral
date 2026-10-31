extends Control
## Gear and inventory. One item equipped per slot; everything else is in the bag (up to 500).
## Pick a slot, see what's equipped, and compare every bag item stat by stat before equipping.

var run: DSRunState
var slot := "weapon"
var tabs := {}
var summary: Label
var equipped_box: VBoxContainer
var list: VBoxContainer
var bag_label: Label


func _ready() -> void:
	run = Game.run
	var v := UI.screen(self)
	var head := HBoxContainer.new()
	var t := UI.label("Gear", 34, UI.ACCENT, false)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	bag_label = UI.label("", 18, UI.DIM, false)
	head.add_child(bag_label)
	v.add_child(head)
	summary = UI.label("", 18, UI.DIM)
	v.add_child(summary)
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	for s in DSRunState.SLOTS:
		var ss: String = s
		var b := UI.button(s.capitalize(), func(): _select(ss), 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		tab_row.add_child(b)
		tabs[s] = b
	v.add_child(tab_row)
	equipped_box = VBoxContainer.new()
	v.add_child(equipped_box)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	v.add_child(scroll)
	v.add_child(UI.button("Back to the dungeon", func(): Game.goto("dungeon"), 64))
	_select("weapon")
	if Game.autoplay != "":
		_select("armor")
		Game.auto_next("gear", func(): Game.goto("dungeon"))


func _select(s: String) -> void:
	slot = s
	for k in tabs.keys():
		tabs[k].button_pressed = k == s
	_refresh()


func _refresh() -> void:
	var p := run.make_player()
	var w = run.items.get("weapon")
	var dmg := "%s avg" % Cards._num((int(w.get("min", 0)) + int(w.get("max", 0))) / 2.0) if w != null else "-"
	summary.text = "HP %d · Weapon %s · Armor %d · Damroll %d · %d boons" % [p.max_hp, dmg, -p.ac, p.damroll, run.boons.size()]
	bag_label.text = "Bag %d/%d" % [run.inventory.size(), DSRunState.INVENTORY_MAX]
	for c in equipped_box.get_children():
		c.queue_free()
	for c in list.get_children():
		c.queue_free()
	var eq = run.items.get(slot)
	var card := PanelContainer.new()
	var cv := VBoxContainer.new()
	card.add_child(cv)
	cv.add_child(UI.label("Equipped %s" % slot, 16, UI.DIM))
	if eq == null:
		cv.add_child(UI.label("(nothing)", 22))
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(UI.icon("item_" + slot, 40, Cards.rarity_color(run.data, str(eq.get("rarity", "common")))))
		var nm := UI.label(str(eq.get("name", "?")), 22, Cards.rarity_color(run.data, str(eq.get("rarity", "common"))))
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		cv.add_child(row)
		cv.add_child(Cards.stat_flow(Cards.compare_lines(run.data, eq, null), 18))
	equipped_box.add_child(card)
	var items := run.inventory_for(slot)
	if items.is_empty():
		list.add_child(UI.label("No other %s in your bag yet. Loot drops after fights and in treasure rooms." % slot, 18, UI.DIM))
		return
	list.add_child(UI.label("In your bag (%d), strongest first" % items.size(), 18, UI.DIM))
	for entry in items:
		list.add_child(_bag_card(entry["item"], int(entry["i"]), eq))


func _bag_card(it: Dictionary, idx: int, eq) -> PanelContainer:
	var card := PanelContainer.new()
	var v := VBoxContainer.new()
	card.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var col := Cards.rarity_color(run.data, str(it.get("rarity", "common")))
	head.add_child(UI.icon("item_" + slot, 36, col))
	var nm := UI.label(str(it.get("name", "?")), 21, col)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	var delta := DSLoot.power(it) - (0 if eq == null else DSLoot.power(eq))
	head.add_child(UI.label(("+%d" % delta) if delta >= 0 else str(delta), 20, Color("#5fd35f") if delta >= 0 else Color("#ff8c7a"), false))
	var eb := UI.button("Equip", func():
		run.equip_from_inventory(idx)
		run.messages.clear()
		Game.save_run()
		_refresh()
	, 48)
	eb.custom_minimum_size.x = 110
	head.add_child(eb)
	v.add_child(head)
	v.add_child(UI.label("%s · ilvl %d" % [str(it.get("rarity", "")).capitalize(), int(it.get("ilvl", 1))], 15, UI.DIM))
	v.add_child(Cards.stat_flow(Cards.compare_lines(run.data, it, eq)))
	return card
