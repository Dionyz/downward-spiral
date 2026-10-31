extends Control
## The Quartermaster: buys gear for the stash. Stock is sized to how deep you've been and
## restocks after every run. Selling happens at the Stash.

var list: VBoxContainer
var gold_label: Label
var status: Label


func _ready() -> void:
	var v := UI.screen(self)
	var head := HBoxContainer.new()
	var t := UI.label("The Quartermaster", 30, Color("#5f9fd3"), false)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	gold_label = UI.label("", 20, UI.ACCENT, false)
	head.add_child(gold_label)
	v.add_child(head)
	v.add_child(UI.label("\"Fresh stock after every run. Bought gear goes to your stash.\"", 17, UI.DIM))
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for b in [UI.button("Sell at the Stash", func(): Game.goto("stash"), 56), UI.button("Back to town", func(): Game.goto("town"), 56)]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	v.add_child(row)
	if Game.account["shop"].is_empty():
		DSAccount.roll_shop(Game.data, Game.account, DSRng.new(int(Time.get_ticks_usec()) % 2147483646 + 1))
		Game.save_account()
	_refresh()
	if Game.autoplay != "":
		Game.auto_next("shop", func(): Game.goto("upgrades"))


func _refresh() -> void:
	gold_label.text = "%d gold" % int(Game.account["gold"])
	for c in list.get_children():
		c.queue_free()
	var ch := Game.character()
	if Game.account["shop"].is_empty():
		list.add_child(UI.label("Sold out. Come back after your next run.", 18, UI.DIM))
	for i in Game.account["shop"].size():
		var it: Dictionary = Game.account["shop"][i]
		var price := DSAccount.buy_price(Game.data, it)
		var ii: int = i
		var eq = ch["loadout"].get(it.get("slot", "")) if not ch.is_empty() else null
		list.add_child(Cards.item_row(Game.data, it, eq, [["Buy %d" % price, func(): _buy(ii), int(Game.account["gold"]) < price]],
			"vs %s's gear" % str(ch.get("name", "your"))))


func _buy(i: int) -> void:
	var it: Dictionary = Game.account["shop"][i]
	if DSAccount.buy(Game.data, Game.account, i):
		Game.sfx("level_up")
		status.text = "Bought %s. It's in your stash." % str(it.get("name", "?"))
		Game.save_account()
	_refresh()
