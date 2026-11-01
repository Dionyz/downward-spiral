extends Control
## Settings, account summary and credits.

var _confirm_reset := false
var reset_btn: Button


func _ready() -> void:
	var v := UI.screen(self)
	v.add_child(UI.label("Settings", 36, UI.ACCENT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 12)
	scroll.add_child(inner)
	v.add_child(scroll)

	inner.add_child(UI.label("Sound volume", 20, UI.DIM))
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = float(Game.settings.get("sfx_volume", 0.8))
	vol.custom_minimum_size = Vector2(0, 48)
	vol.value_changed.connect(func(x):
		Game.settings["sfx_volume"] = x
		Game.save_settings()
		Game.sfx("hit")
	)
	inner.add_child(vol)

	inner.add_child(UI.label("Fight speed", 20, UI.DIM))
	var sp := OptionButton.new()
	sp.custom_minimum_size = Vector2(0, 56)
	for s in [1, 2, 4]:
		sp.add_item("%dx" % s)
	sp.select([1.0, 2.0, 4.0].find(float(Game.settings.get("speed", 1.0))) if [1.0, 2.0, 4.0].has(float(Game.settings.get("speed", 1.0))) else 0)
	sp.item_selected.connect(func(i):
		Game.settings["speed"] = [1.0, 2.0, 4.0][i]
		Game.speed = Game.settings["speed"]
		Game.save_settings()
	)
	inner.add_child(sp)

	var log_cb := CheckBox.new()
	log_cb.text = "Show the full combat log by default"
	log_cb.add_theme_font_size_override("font_size", 20)
	log_cb.button_pressed = bool(Game.settings.get("log_open", false))
	log_cb.toggled.connect(func(on):
		Game.settings["log_open"] = on
		Game.save_settings()
	)
	inner.add_child(log_cb)

	inner.add_child(UI.button("Guide: stats, items and terms", func():
		load("res://game/scenes/guide.gd").back_to = "settings"
		Game.goto("guide"), 56))
	inner.add_child(UI.button("Show tips again", func():
		Game.settings["hints_seen"] = []
		Game.save_settings()
	, 56))

	inner.add_child(UI.label("Account", 26, UI.ACCENT))
	inner.add_child(UI.label("%d characters · %d gold · %d items stashed" % [Game.account["characters"].size(), int(Game.account.get("gold", 0)), Game.account["stash"].size()], 20))
	inner.add_child(UI.label("Runs %d · victories %d · extractions %d · deaths %d · best floor %d" % [int(Game.account.get("runs", 0)),
		int(Game.account.get("victories", 0)), int(Game.account.get("extracts", 0)), int(Game.account.get("deaths", 0)), int(Game.account.get("best_floor", 0))], 18, UI.DIM))
	reset_btn = UI.button("Reset all progress", _reset, 56)
	inner.add_child(reset_btn)

	inner.add_child(UI.label("Credits", 26, UI.ACCENT))
	inner.add_child(UI.label("Rules adapted from the Devil's Silence MUD (ROM/ROT lineage); all code and text written fresh.", 18, UI.DIM))
	inner.add_child(UI.label("Icons from game-icons.net (CC BY 3.0) by Lorc, Delapouite, Skoll, Carl Olsen and Cathelineau.", 18, UI.DIM))
	inner.add_child(UI.label("Sound effects synthesized for this game. Tests use GUT (MIT).", 18, UI.DIM))
	inner.add_child(UI.label("Built with Godot Engine (MIT).", 18, UI.DIM))

	v.add_child(UI.button("Back", func(): Game.goto("town" if not Game.account["characters"].is_empty() else "title"), 64))


func _reset() -> void:
	if not _confirm_reset:
		_confirm_reset = true
		reset_btn.text = "Tap again to erase your account"
		return
	Game.account = DSAccount.fresh()
	Game.save_account()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game._path(Game.RUN_SAVE)))
	Game.goto("settings")
