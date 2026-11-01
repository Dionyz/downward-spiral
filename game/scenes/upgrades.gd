extends Control
## Between runs: spend banked gold on extra boon-offer charges per run (Skip, Reroll, Banish).
## Each purchase adds one charge to every future run; prices double, up to 5 purchases each.

var list: VBoxContainer
var gold_label: Label


func _ready() -> void:
	var v := UI.screen(self)
	var t := UI.label("The Trainer", 40, Color("#9d7cf2"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UI.label("\"Gold buys strength.\" Power-ups apply to every character, every run.", 18, UI.DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	gold_label = UI.label("", 24, UI.ACCENT)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(gold_label)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(list)
	v.add_child(scroll)
	v.add_child(UI.button("Back", func(): Game.goto("town"), 64))
	_refresh()
	if Game.autoplay != "":
		Game.auto_next("upgrades", func(): Game.get_tree().quit())


func _refresh() -> void:
	gold_label.text = "Gold: %d" % int(Game.account.get("gold", 0))
	for c in list.get_children():
		c.queue_free()
	var defs: Dictionary = Game.data.meta.get("upgrades", {})
	var per_run := DSMeta.charges(Game.data, Game.account)
	var pk := DSMeta.perks(Game.data, Game.account)
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
		var now := ""
		match id:
			"vitality":
				now = "+%d%% HP" % int(pk["hp_pct"])
			"might":
				now = "+%d%% damage" % int(pk["damage_pct"])
			"provisions":
				now = "+%d potions" % int(pk["potions"])
			"fortune":
				now = "Luck %d" % int(pk["boon_luck"])
			_:
				now = "%d per run" % int(per_run[id])
		head.add_child(UI.label(now, 20, UI.TEXT, false))
		cv.add_child(head)
		cv.add_child(UI.label(str(d.get("desc", "")), 18, UI.DIM))
		var owned := DSMeta.owned(Game.account, id)
		cv.add_child(UI.label("Bought %d of %d" % [owned, DSMeta.upgrade_cap(Game.data, id)], 16, UI.DIM))
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
