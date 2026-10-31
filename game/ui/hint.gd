class_name Hint
extends RefCounted
## One-time tutorial prompts. Each hint shows once per install (settings.hints_seen) as a dim
## overlay with a short card and a "Got it" button. `on_close` runs when it's dismissed (or
## immediately if the hint was already seen), so callers can pause timers meanwhile.

const TEXT := {
	"welcome": ["Welcome to the Spiral", "Six floors down, a boss at the bottom. Your character explores and fights on its own; you pick its boons and drink its potions.\n\nPick a class to begin. More classes unlock as your account levels up."],
	"dungeon": ["The floor", "Each floor is a fresh maze. Your character explores it on its own, picks up loot, opens chests and fights whatever wakes up, turn by turn, using its whole kit.\n\nYou drink the potions: tap Potion when things get rough. Tap the log to read the full blow-by-blow. Gear opens your bag."],
	"boon": ["Boons", "Level-ups, shrines and elite kills each grant a boon: pick one of three. Boons change how your abilities work for the rest of the run.\n\nSkip, Reroll and Banish are limited per run. Buy more between runs under Upgrades with the gold you bring home."],
	"event": ["Something strange", "Events are gambles. Read carefully: some choices cost HP or gold, some pay off."],
	"floor_end": ["Descend or extract", "From floor 2 on you can extract: you keep all your gold and XP. Dying keeps only half your XP and none of your gold.\n\nXP raises your account level, which unlocks classes and perks."],
	"run_end": ["Your account", "Every run banks XP into your account, win or lose. Account levels unlock new classes, extra starting potions, new boons and small permanent bonuses."],
}


static var _open := {}


static func seen(id: String) -> bool:
	return Game.settings.get("hints_seen", []).has(id)


## Show hint `id` over `parent` unless already seen. Returns true if shown.
static func show(parent: Control, id: String, on_close: Callable = Callable()) -> bool:
	if _open.has(id):
		return false
	if seen(id) or not TEXT.has(id):
		if on_close.is_valid():
			on_close.call()
		return false
	_open[id] = true
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Above everything the screen draws with a raised z (map tokens, the boon overlay):
	# input goes to the last child, so drawing must agree or the tip blocks clicks invisibly.
	layer.z_index = 100
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 20)
	m.add_theme_constant_override("margin_bottom", 40)
	layer.add_child(m)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_END
	m.add_child(col)
	var card := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#221f2b")
	st.border_color = UI.ACCENT
	st.set_border_width_all(2)
	st.set_corner_radius_all(12)
	st.set_content_margin_all(18)
	card.add_theme_stylebox_override("panel", st)
	col.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	v.add_child(UI.label(TEXT[id][0], 28, UI.ACCENT))
	v.add_child(UI.label(TEXT[id][1], 20))
	var close := func():
		var hs: Array = Game.settings.get("hints_seen", [])
		if not hs.has(id):
			hs.append(id)
		Game.settings["hints_seen"] = hs
		Game.save_settings()
		_open.erase(id)
		if is_instance_valid(layer):
			layer.queue_free()
		if on_close.is_valid():
			on_close.call()
	v.add_child(UI.button("Got it", close, 60))
	if Game.autoplay != "":
		Game.auto_next("hint_" + id, close, 0.1)
	return true
