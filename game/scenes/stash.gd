extends Control
## The Stash: storage shared by every character, plus the current character's equipped gear.
## Equip from the stash, put gear back, sell one item or sell in bulk.

var slot := "weapon"
var tabs := {}
var top_label: Label
var equipped_box: VBoxContainer
var list: VBoxContainer
var status: Label


func _ready() -> void:
	var v := UI.screen(self)
	var head := HBoxContainer.new()
	var t := UI.label("The Stash", 32, Color("#7fc8a9"), false)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	top_label = UI.label("", 18, UI.ACCENT, false)
	head.add_child(top_label)
	v.add_child(head)
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	for s in DSAccount.SLOTS:
		var ss: String = s
		var b := UI.button(s.capitalize(), func(): _select(ss), 52)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_row.add_child(b)
		tabs[s] = b
	v.add_child(tab_row)
	equipped_box = VBoxContainer.new()
	v.add_child(equipped_box)
	var bulk := HBoxContainer.new()
	bulk.add_theme_constant_override("separation", 6)
	for spec in [["Sell commons", ["common"], false], ["Sell uncommons", ["uncommon"], false], ["Sell all weaker", ["common", "uncommon", "rare", "epic"], true]]:
		var sp: Array = spec
		var b := UI.button(str(sp[0]), func(): _bulk(sp[1], sp[2]), 48)
		b.add_theme_font_size_override("font_size", 16)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bulk.add_child(b)
	v.add_child(bulk)
	status = UI.label("", 16, Color("#7fc8a9"))
	v.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	v.add_child(scroll)
	v.add_child(UI.button("Back to town", func(): Game.goto("town"), 56))
	_select("weapon")
	if Game.autoplay != "":
		Game.auto_next("stash", func(): Game.goto("shop"))


func _select(s: String) -> void:
	slot = s
	for k in tabs.keys():
		tabs[k].button_pressed = k == s
	_refresh()


func _refresh() -> void:
	var ch := Game.character()
	top_label.text = "%d gold · %d/%d" % [int(Game.account["gold"]), Game.account["stash"].size(), DSAccount.stash_max(Game.data)]
	for c in equipped_box.get_children():
		c.queue_free()
	for c in list.get_children():
		c.queue_free()
	var eq = ch["loadout"].get(slot) if not ch.is_empty() else null
	equipped_box.add_child(UI.label("%s is wearing" % str(ch.get("name", "?")), 15, UI.DIM))
	if eq == null:
		equipped_box.add_child(UI.label("(nothing in this slot)", 18))
	else:
		var acts: Array = []
		if slot != "weapon":
			acts.append(["To stash", func():
				DSAccount.unequip(Game.account, slot)
				_saved()])
		equipped_box.add_child(Cards.item_row(Game.data, eq, null, acts))
	var idx: Array = []
	for i in Game.account["stash"].size():
		if Game.account["stash"][i].get("slot") == slot:
			idx.append(i)
	idx.sort_custom(func(a, b): return DSLoot.power(Game.account["stash"][a]) > DSLoot.power(Game.account["stash"][b]))
	if idx.is_empty():
		list.add_child(UI.label("No %s in the stash. Extract from a run to bring loot home." % slot, 17, UI.DIM))
	for i in idx:
		var it: Dictionary = Game.account["stash"][i]
		var ii: int = i
		list.add_child(Cards.item_row(Game.data, it, eq, [
			["Equip", func():
				DSAccount.equip_from_stash(Game.account, ii)
				_saved()],
			["Sell %d" % DSAccount.sell_value(Game.data, it), func():
				var g := DSAccount.sell(Game.data, Game.account, ii)
				Game.sfx("click")
				status.text = "Sold for %d gold." % g
				_saved()],
		]))


func _bulk(rarities: Array, only_worse: bool) -> void:
	var res := DSAccount.bulk_sell(Game.data, Game.account, rarities, only_worse)
	status.text = "Sold %d items for %d gold." % [int(res["count"]), int(res["gold"])] if int(res["count"]) > 0 else "Nothing to sell."
	_saved()


func _saved() -> void:
	Game.save_account()
	_refresh()
