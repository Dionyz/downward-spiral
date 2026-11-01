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
		var b := UI.button(s.capitalize() + (" ▲" if run.upgrade_slots().has(s) else ""), func(): _select(ss), 56)
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for bt in [UI.button("Boons", _show_boons, 60), UI.button("Back to the dungeon", func(): Game.goto("dungeon"), 60)]:
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bt)
	v.add_child(row)
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
	summary.text = "HP %d · Weapon %s · +%s weapon damage · Armor %d · %d boons" % [p.max_hp, dmg, Cards._num(p.damroll / 10.0), -p.ac, run.boons.size()]
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
		for k in tabs.keys():
			tabs[k].text = str(k).capitalize() + (" ▲" if run.upgrade_slots().has(k) else "")
		_refresh()
	, 48)
	eb.custom_minimum_size.x = 110
	head.add_child(eb)
	v.add_child(head)
	var sub := "%s · ilvl %d" % [str(it.get("rarity", "")).capitalize(), int(it.get("ilvl", 1))]
	if DSRunState.is_pure_upgrade(it, eq):
		v.add_child(UI.label(sub + "  ·  ▲ UPGRADE", 15, Color("#5fd35f")))
	else:
		v.add_child(UI.label(sub, 15, UI.DIM))
	v.add_child(Cards.stat_flow(Cards.compare_lines(run.data, it, eq)))
	return card


## Boons taken this run (with stacks) and the family bonuses they've unlocked.
func _show_boons() -> void:
	var layer := PanelContainer.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.z_index = 60
	add_child(layer)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	layer.add_child(v)
	v.add_child(UI.label("Boons", 30, UI.ACCENT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 6)
	scroll.add_child(inner)
	v.add_child(scroll)
	var counts := DSFactory.family_counts(run.data, run.boons)
	inner.add_child(UI.label("Families (distinct boons)", 20, UI.DIM))
	for f in run.data.families.keys():
		var fam: Dictionary = run.data.families[f]
		var n := int(counts.get(f, 0))
		var col := Color(str(fam.get("color", "#e6e1d6")))
		inner.add_child(Tip.attach(UI.label("◆ %s  %d  — %s" % [str(fam["name"]), n, str(fam.get("desc", ""))], 18, col if n > 0 else UI.DIM), str(fam["name"])))
		for th in ["2", "4", "6"]:
			var on := n >= int(th)
			inner.add_child(UI.label("     %s %s: %s" % ["✓" if on else "·", th, str(fam["tiers"][th]["text"])], 16, col if on else UI.DIM))
	inner.add_child(UI.label("Your boons", 20, UI.DIM))
	if run.boons.is_empty():
		inner.add_child(UI.label("None yet. Level up or kill an elite to pick one.", 17, UI.DIM))
	var seen := {}
	for id in run.boons:
		if seen.has(id):
			continue
		seen[id] = true
		var b: Dictionary = run.data.boons.get(id, {})
		var n := run.boon_rank(id)
		inner.add_child(UI.label("%s%s" % [str(b.get("name", id)), (" ×%d" % n) if n > 1 else ""], 19, UI.ACCENT))
		inner.add_child(UI.label(run.boon_desc(id), 16))
	inner.add_child(Tip.attach(UI.label("Total damage reduction from boons is capped at 90%.", 15, UI.DIM), "damage reduction"))
	v.add_child(UI.button("Close", func(): layer.queue_free(), 56))
