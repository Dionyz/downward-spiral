extends Control
## Between runs: spend banked gold on extra boon-offer charges per run (Skip, Reroll, Banish).
## Each purchase adds one charge to every future run; prices double, up to 5 purchases each.

var list: VBoxContainer
var gold_label: Label


func _ready() -> void:
	var v := UI.screen(self)
	var t := UI.label("Upgrades", 40, UI.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UI.label("Extra charges for boon picks, every run. Bought with gold you bring home.", 18, UI.DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	gold_label = UI.label("", 24, UI.ACCENT)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(gold_label)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 14)
	v.add_child(list)
	v.add_child(UI.spacer())
	v.add_child(UI.button("Back", func(): Game.goto("title"), 64))
	_refresh()
	if Game.autoplay != "":
		Game.auto_next("upgrades", func(): Game.goto("title"))


func _refresh() -> void:
	gold_label.text = "Gold: %d" % int(Game.account.get("gold", 0))
	for c in list.get_children():
		c.queue_free()
	var defs: Dictionary = Game.data.meta.get("upgrades", {})
	var per_run := DSMeta.charges(Game.data, Game.account)
	var cap := int(Game.data.meta.get("upgrade_max", 5))
	for id in DSMeta.UPGRADES:
		var d: Dictionary = defs.get(id, {})
		var card := PanelContainer.new()
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		card.add_child(cv)
		var head := HBoxContainer.new()
		var n := UI.label(str(d.get("name", id)), 28, UI.ACCENT, false)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(n)
		head.add_child(UI.label("%d per run" % int(per_run[id]), 20, UI.TEXT, false))
		cv.add_child(head)
		cv.add_child(UI.label(str(d.get("desc", "")), 18, UI.DIM))
		var owned := DSMeta.owned(Game.account, id)
		cv.add_child(UI.label("Bought %d of %d" % [owned, cap], 16, UI.DIM))
		var price := DSMeta.upgrade_price(Game.data, Game.account, id)
		var uid: String = id
		var b := UI.button("Maxed" if price < 0 else "Buy +1 for %d gold" % price, func(): _buy(uid), 56)
		b.disabled = price < 0 or int(Game.account.get("gold", 0)) < price
		cv.add_child(b)
		list.add_child(card)


func _buy(id: String) -> void:
	if Game.buy_upgrade(id):
		Game.sfx("level_up")
	_refresh()
