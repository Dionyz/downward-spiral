extends Control
## The run screen: floor map as connected nodes, then whatever the current room needs.
## Exploration is automatic along the path; the player picks at forks and makes room choices.

const TYPE_LABEL := {"fight": "Fight", "elite": "Elite", "boss": "Boss", "treasure": "Treasure",
	"shrine": "Shrine", "rest": "Rest", "event": "Event"}
const TYPE_COLOR := {"fight": "#c9c2b6", "elite": "#ff9a2e", "boss": "#ff5a3d", "treasure": "#d6a64f",
	"shrine": "#9d7cf2", "rest": "#5fd35f", "event": "#5f9fd3"}
const AUTO_DELAY := 1.1

var run: DSRunState
var header: Label
var subheader: Label
var map_box: VBoxContainer
var body: VBoxContainer
var overlay: Control = null
var auto_timer: Timer
var _auto_paused := false


func _ready() -> void:
	run = Game.run
	var v := UI.screen(self)
	header = UI.label("", 28, UI.ACCENT)
	v.add_child(header)
	subheader = UI.label("", 18, UI.DIM)
	v.add_child(subheader)
	map_box = VBoxContainer.new()
	map_box.add_theme_constant_override("separation", 4)
	v.add_child(map_box)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	v.add_child(scroll)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	for b in [UI.button("Rules", _open_rules, 56), UI.button("Gear", _open_gear, 56)]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(b)
	v.add_child(bar)
	auto_timer = Timer.new()
	auto_timer.one_shot = true
	auto_timer.timeout.connect(_auto_advance)
	add_child(auto_timer)
	if not Hint.seen("dungeon"):
		_auto_paused = true
	_refresh()
	Hint.show(self, "dungeon", func():
		_auto_paused = false
		if is_inside_tree():
			_refresh()
	)


# --- rendering ------------------------------------------------------------

func _refresh() -> void:
	if run.phase == "over":
		Game.goto("run_end")
		return
	var p := run.make_player()
	header.text = "Floor %d of %d · Level %d" % [run.floor_num, DSRunState.FLOORS, run.level]
	var parts: Array = ["HP %d/%d" % [p.hp, p.max_hp]]
	if p.max_mana > 0:
		parts.append("Mana %d/%d" % [p.mana, p.max_mana])
	parts.append("Gold %d" % run.gold)
	parts.append("XP %d/%d" % [run.xp, run.xp_to_next()])
	var pots := "Potions %d HP" % int(run.potions.get("hp", 0))
	if p.max_mana > 0:
		pots += " %d MP" % int(run.potions.get("mp", 0))
	parts.append(pots)
	subheader.text = "   ".join(PackedStringArray(parts))
	_draw_map()
	for c in body.get_children():
		c.queue_free()
	for m in run.messages:
		body.add_child(UI.label(str(m), 18, Color("#7fc8a9")))
		if str(m).begins_with("Level "):
			Game.sfx("level_up")
	run.messages.clear()
	match run.phase:
		"path":
			_show_path()
		"room":
			_show_room()
		"reward":
			_show_reward()
		"floor_end":
			_show_floor_end()
	var hid := ""
	if run.phase == "reward" and not run.room.get("reward", {}).get("offers", []).is_empty():
		hid = "reward"
	elif run.phase == "floor_end":
		hid = "floor_end"
	elif run.phase == "room" and run.room.get("type", "") in ["rest", "shrine", "event"]:
		hid = str(run.room["type"])
	if hid != "" and Hint.seen("dungeon"):
		Hint.show(self, hid)
	_maybe_autoplay()


func _draw_map() -> void:
	for c in map_box.get_children():
		c.queue_free()
	var steps := run.steps()
	for i in steps.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var marker := UI.label("▶" if i == run.step and run.phase in ["path", "room", "reward"] else "  ", 18, UI.ACCENT, false)
		marker.custom_minimum_size = Vector2(26, 0)
		row.add_child(marker)
		var options: Array = steps[i]
		for j in options.size():
			var rm: Dictionary = options[j]
			var t: String = rm.get("type", "fight")
			var chip := PanelContainer.new()
			chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var ch := HBoxContainer.new()
			ch.add_theme_constant_override("separation", 8)
			ch.add_child(UI.icon("room_" + t, 24, Color(TYPE_COLOR.get(t, "#c9c2b6"))))
			ch.add_child(UI.label(TYPE_LABEL.get(t, t), 18, Color(TYPE_COLOR.get(t, "#c9c2b6")), false))
			chip.add_child(ch)
			var done := i < run.step
			var taken := done or (i == run.step and run.phase != "path")
			var chosen_here := int(run.room.get("chosen", 0)) if i == run.step else -1
			if done or (i == run.step and run.phase != "path" and j != chosen_here):
				chip.modulate = Color(1, 1, 1, 0.35)
			if i > run.step:
				chip.modulate = Color(1, 1, 1, 0.6)
			if taken and j == chosen_here and i == run.step:
				chip.modulate = Color.WHITE
			row.add_child(chip)
		map_box.add_child(row)


func _room_title(rm: Dictionary) -> void:
	var t: String = rm.get("type", "")
	var nm: String = rm.get("name", "")
	if t == "event" and rm.has("event"):
		nm = str(run.data.events.get(rm["event"], {}).get("title", nm))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(UI.icon("room_" + t, 56, Color(TYPE_COLOR.get(t, "#e6e1d6"))))
	var tl := UI.label("%s — %s" % [TYPE_LABEL.get(t, t), nm], 26, Color(TYPE_COLOR.get(t, "#e6e1d6")))
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	body.add_child(head)
	if t != "event" or not rm.has("event"):
		body.add_child(UI.label(str(rm.get("desc", "")), 20, UI.DIM))


func _show_path() -> void:
	var options := run.current_step()
	if options.size() > 1:
		body.add_child(UI.label("The path splits.", 26, UI.ACCENT))
		for j in options.size():
			var rm: Dictionary = options[j]
			var t: String = rm.get("type", "")
			var jj := j
			body.add_child(UI.label("%s — %s" % [TYPE_LABEL.get(t, t), rm.get("name", "")], 22, Color(TYPE_COLOR.get(t, "#e6e1d6"))))
			body.add_child(UI.label(str(rm.get("desc", "")), 18, UI.DIM))
			body.add_child(UI.button("Go this way", func(): _enter(jj), 60))
	else:
		_room_title(options[0])
		body.add_child(UI.label("You press on...", 18, UI.DIM))
		body.add_child(UI.button("Enter", func(): _enter(0), 60))
		_schedule_auto()


func _show_room() -> void:
	var rm := run.room
	_room_title(rm)
	match rm.get("type", ""):
		"fight", "elite", "boss":
			var foes := run.fight_monsters()
			body.add_child(UI.label("Ahead: " + ", ".join(PackedStringArray(foes.map(func(f): return f.name))), 20))
			body.add_child(UI.button("Fight", _fight, 72))
			_schedule_auto()
		"treasure":
			body.add_child(UI.label("Take one.", 20))
			var offers: Array = rm.get("offers", [])
			for i in offers.size():
				_offer_card(offers[i], i)
			body.add_child(UI.button("Leave it", _skip, 56))
		"shrine":
			_show_shrine()
		"rest":
			body.add_child(UI.label("A quiet corner. You can rest, or drill your technique.", 20))
			body.add_child(UI.button("Rest (recover %d%% HP and mana)" % int(run._cfg().get("rest_heal_pct", 40)), _rest_heal, 64))
			body.add_child(UI.button("Train (swap abilities, edit rules)", _open_train, 64))
		"event":
			_show_event()


func _show_shrine() -> void:
	body.add_child(UI.label("Choose a boon.", 20))
	var offers: Array = run.room.get("offers", [])
	for i in offers.size():
		_offer_card(offers[i], i)
	var rr := UI.button("Re-roll the offers (%d gold)" % run.shrine_reroll_cost(), _reroll, 56)
	rr.disabled = run.gold < run.shrine_reroll_cost()
	body.add_child(rr)
	if not run.boons.is_empty():
		body.add_child(UI.label("Or pay %d gold to remove a boon:" % run.shrine_remove_cost(), 18, UI.DIM))
		for id in run.boons:
			var bid: String = id
			var b := UI.button("Remove %s" % run.data.boons.get(bid, {}).get("name", bid), func(): _remove_boon(bid), 52)
			b.disabled = run.gold < run.shrine_remove_cost()
			body.add_child(b)
	body.add_child(UI.button("Leave", _skip, 56))


func _show_event() -> void:
	var ev := run.event_def()
	body.add_child(UI.label(str(ev.get("text", "")), 20))
	if run.room.has("outcome"):
		for line in run.room["outcome"]:
			body.add_child(UI.label(str(line), 20, Color("#7fc8a9")))
		body.add_child(UI.button("Continue", _complete, 60))
		return
	var opts: Array = ev.get("options", [])
	for i in opts.size():
		var ii := i
		body.add_child(UI.button(str(opts[i].get("label", "?")), func(): _event_choose(ii), 60))


func _show_reward() -> void:
	var rw: Dictionary = run.room.get("reward", {})
	if run.room.get("type") == "event":
		for line in run.room.get("outcome", []):
			body.add_child(UI.label(str(line), 20, Color("#7fc8a9")))
	else:
		body.add_child(UI.label("Victory", 30, UI.ACCENT))
		var bits: Array = ["+%d gold" % int(rw.get("gold", 0)), "+%d XP" % int(rw.get("xp", 0))]
		if rw.has("potion"):
			bits.append("+1 %s potion" % str(rw["potion"]).to_upper())
		body.add_child(UI.label("   ".join(PackedStringArray(bits)), 20))
	var offers: Array = rw.get("offers", [])
	if not offers.is_empty():
		body.add_child(UI.label("Pick one:", 20))
		for i in offers.size():
			_offer_card(offers[i], i)
		body.add_child(UI.button("Take nothing", _skip, 56))
	else:
		body.add_child(UI.button("Continue", _skip, 60))


func _show_floor_end() -> void:
	body.add_child(UI.label("Floor %d cleared." % run.floor_num, 30, UI.ACCENT))
	body.add_child(UI.label("The stair spirals down into the dark.", 20, UI.DIM))
	body.add_child(UI.button("Descend to floor %d" % (run.floor_num + 1), _descend, 72))
	if run.can_extract():
		var bank := {"xp": run.xp_total, "gold": run.gold}
		body.add_child(UI.button("Extract (keep %d gold, %d XP)" % [bank["gold"], bank["xp"]], _extract, 64))
	else:
		body.add_child(UI.label("You can extract from the end of floor 2.", 16, UI.DIM))


func _offer_card(o: Dictionary, i: int) -> void:
	var ii := i
	if o.get("kind") == "item":
		var it: Dictionary = o["item"]
		body.add_child(Cards.item_card(run.data, it, run.items.get(it.get("slot", "")), func(): _take(ii)))
	else:
		body.add_child(Cards.boon_card(run.data, str(o.get("id", "")), func(): _take(ii)))


# --- actions --------------------------------------------------------------

func _after() -> void:
	Game.save_run()
	_refresh()


func _enter(choice: int) -> void:
	auto_timer.stop()
	if run.phase != "path":
		return
	run.enter(choice)
	_after()


func _fight() -> void:
	auto_timer.stop()
	Game.save_run()
	Game.goto("combat")


func _take(i: int) -> void:
	run.take_offer(i)
	_after()


func _skip() -> void:
	run.skip()
	_after()


func _complete() -> void:
	run.complete_room()
	_after()


func _reroll() -> void:
	run.shrine_reroll()
	_after()


func _remove_boon(id: String) -> void:
	run.shrine_remove(id)
	_after()


func _rest_heal() -> void:
	run.rest_heal()
	_after()


func _event_choose(i: int) -> void:
	run.event_choose(i)
	_after()


func _descend() -> void:
	run.descend()
	_after()


func _extract() -> void:
	run.extract()
	_after()


# --- auto exploration -------------------------------------------------------

func _schedule_auto() -> void:
	if Game.autoplay == "" and not _auto_paused and overlay == null:
		auto_timer.start(AUTO_DELAY)


func _auto_advance() -> void:
	if overlay != null:
		return
	if run.phase == "path" and not run.at_fork():
		_enter(0)
	elif run.is_fight_room():
		_fight()


var _auto_pending := false


func _maybe_autoplay() -> void:
	if Game.autoplay == "" or _auto_pending:
		return
	_auto_pending = true
	var shot := "%d_%d_%s_%s" % [run.floor_num, run.step, run.phase, str(run.room.get("type", ""))]
	Game.auto_next(shot, _autoplay_step)


func _autoplay_step() -> void:
	_auto_pending = false
	if not is_inside_tree():
		return
	print("[autoplay] at floor %d step %d phase %s room %s" % [run.floor_num, run.step, run.phase, run.room.get("type", "-")])
	if run.is_fight_room():
		_fight()
		return
	if run.phase == "floor_end":
		print("[autoplay] floor %d cleared, level %d, HP %d, gold %d" % [run.floor_num, run.level, run.make_player().hp, run.gold])
	DSAutopilot.advance(run)
	_after()


# --- overlays: rules, gear, training ---------------------------------------

func _close_overlay() -> void:
	if overlay != null:
		overlay.queue_free()
		overlay = null
	_auto_paused = false
	_refresh()


func _make_overlay(title: String) -> VBoxContainer:
	auto_timer.stop()
	_auto_paused = true
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var v := UI.screen(overlay)
	v.add_child(UI.label(title, 30, UI.ACCENT))
	return v


func _open_rules() -> void:
	var v := _make_overlay("Rules")
	v.add_child(UI.label("Checked top to bottom every round. If none fires, your character picks for itself.", 18, UI.DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var ed := RuleEditor.new()
	ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(ed)
	v.add_child(scroll)
	ed.setup(run.actives, run.rules, run.rule_slots())
	Hint.show(overlay, "rules")
	v.add_child(UI.button("Done", func():
		run.set_rules(ed.get_rules())
		Game.save_run()
		_close_overlay()
	, 64))


func _open_train() -> void:
	var v := _make_overlay("Train")
	v.add_child(UI.label("Pick up to %d abilities to carry, then set your rules." % int(run.data.balance.get("max_actives", 4)), 18, UI.DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	v.add_child(scroll)
	var boxes := {}
	for a in run.known_actives():
		var cb := CheckBox.new()
		cb.text = str(a)
		cb.button_pressed = run.actives.has(a)
		cb.add_theme_font_size_override("font_size", 22)
		cb.custom_minimum_size = Vector2(0, 52)
		inner.add_child(cb)
		boxes[a] = cb
	var ed := RuleEditor.new()
	ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(ed)
	var refresh_rules := func():
		var picked: Array = []
		for a in boxes.keys():
			if boxes[a].button_pressed:
				picked.append(a)
		ed.setup(picked, run.rules, run.rule_slots())
	for a in boxes.keys():
		boxes[a].toggled.connect(func(_on): refresh_rules.call())
	refresh_rules.call()
	v.add_child(UI.button("Done training", func():
		var picked: Array = []
		for a in boxes.keys():
			if boxes[a].button_pressed:
				picked.append(a)
		run.rest_train(picked, ed.get_rules())
		Game.save_run()
		_close_overlay()
	, 64))


func _open_gear() -> void:
	var v := _make_overlay("Gear and boons")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 8)
	scroll.add_child(inner)
	v.add_child(scroll)
	for slot in DSRunState.SLOTS:
		var it = run.items.get(slot)
		inner.add_child(UI.label(slot.capitalize(), 18, UI.DIM))
		if it == null:
			inner.add_child(UI.label("(empty)", 20))
		else:
			inner.add_child(UI.label(str(it.get("name", "?")), 22, Cards.rarity_color(run.data, str(it.get("rarity", "common")))))
			inner.add_child(UI.label(" · ".join(PackedStringArray(Cards.item_lines(run.data, it))), 18))
	inner.add_child(UI.label("Abilities: " + ", ".join(PackedStringArray(run.actives)), 20))
	inner.add_child(UI.label("Boons", 18, UI.DIM))
	if run.boons.is_empty():
		inner.add_child(UI.label("(none yet)", 20))
	for id in run.boons:
		var b: Dictionary = run.data.boons.get(id, {})
		inner.add_child(UI.label("%s — %s" % [b.get("name", id), b.get("desc", "")], 20))
	v.add_child(UI.button("Close", _close_overlay, 64))
