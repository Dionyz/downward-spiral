extends Control
## The run screen. The floor is a Rogue-style tile map; your character explores and fights on
## its own, turn by turn, and monsters wander and hunt on the same map. Under the map: the three
## latest log lines (tap to expand the full log), the potion button(s), speed and Gear.
## Boon picks take over the whole screen; events and the end of a floor show as panels.

const EXPLORE_TURN := 0.25     # seconds per turn at 1x while exploring
const COMBAT_TURN := 0.5       # seconds per turn at 1x while fighting
const LOG_LINES := 3

var run: DSRunState
var header: Label
var hp_bar: ProgressBar
var hp_label: Label
var mana_bar: ProgressBar
var grid: GridView
var log_strip: VBoxContainer
var log_full: CombatLog
var log_layer: Control
var pot_hp: Button
var pot_mp: Button
var speed_btn: Button
var gear_btn: Button
var extract_btn: Button
var overlay: Control           # boon / event / floor end
var timer: Timer
var _recent: Array = []        # latest log lines as [text, color]
var _paused := false
var _shots_left := 0
static var _gear_shown := false


func _ready() -> void:
	run = Game.run
	var v := UI.screen(self)
	v.add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	header = UI.label("", 22, UI.ACCENT, false)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.clip_text = true
	top.add_child(header)
	extract_btn = UI.button("Extract", _extract_pressed, 44)
	extract_btn.add_theme_font_size_override("font_size", 18)
	extract_btn.add_theme_color_override("font_color", Color("#7fc8a9"))
	top.add_child(extract_btn)
	var set_btn := UI.button("Settings", _open_settings, 44)
	set_btn.add_theme_font_size_override("font_size", 18)
	top.add_child(set_btn)
	v.add_child(top)
	var bars := HBoxContainer.new()
	bars.add_theme_constant_override("separation", 10)
	var bv := VBoxContainer.new()
	bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bv.add_theme_constant_override("separation", 2)
	hp_bar = UI.bar(UI.HP, 18)
	bv.add_child(hp_bar)
	mana_bar = UI.bar(UI.MANA, 8)
	bv.add_child(mana_bar)
	bars.add_child(bv)
	hp_label = UI.label("", 17, UI.TEXT, false)
	bars.add_child(hp_label)
	v.add_child(bars)

	grid = GridView.new()
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grid)

	# Log strip: last three lines; tap to open the full log.
	var strip_frame := PanelContainer.new()
	strip_frame.custom_minimum_size = Vector2(0, 96)
	strip_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	strip_frame.gui_input.connect(func(e):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			_toggle_log())
	log_strip = VBoxContainer.new()
	log_strip.add_theme_constant_override("separation", 0)
	log_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip_frame.add_child(log_strip)
	v.add_child(strip_frame)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	pot_hp = UI.button("", func(): _drink("hp"), 60)
	pot_mp = UI.button("", func(): _drink("mp"), 60)
	speed_btn = UI.button("", _toggle_speed, 60)
	gear_btn = UI.button("Gear", _open_gear, 60)
	var skills_btn := UI.button("Skills", func():
		timer.stop()
		_paused = true
		Game.save_run()
		Game.goto("skills"), 60)
	for b in [pot_hp, pot_mp, speed_btn, gear_btn, skills_btn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 19)
		b.clip_text = true
		row.add_child(b)
	v.add_child(row)

	# Full log (hidden until the strip is tapped): covers the map.
	log_layer = PanelContainer.new()
	log_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	log_layer.offset_top = 90
	log_layer.offset_bottom = -100
	log_layer.offset_left = 12
	log_layer.offset_right = -12
	var lv := VBoxContainer.new()
	log_layer.add_child(lv)
	log_full = CombatLog.new()
	log_full.player_name = run.world.player.name if run.world != null else "You"
	lv.add_child(log_full)
	lv.add_child(UI.button("Close log", _toggle_log, 56))
	log_layer.visible = false
	log_layer.z_index = 40
	add_child(log_layer)

	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.z_index = 50
	add_child(overlay)

	timer = Timer.new()
	timer.one_shot = true
	timer.timeout.connect(_turn)
	add_child(timer)
	if Game.autoplay != "":
		_shots_left = 6 if OS.get_cmdline_user_args().has("--shots") else 0

	grid.setup.call_deferred(run)
	_refresh()
	_paused = true
	Hint.show(self, "dungeon", func():
		_paused = false
		if is_inside_tree():
			_resume())


# --- the turn loop -----------------------------------------------------------

func _turn_time() -> float:
	var t := COMBAT_TURN if run.world != null and run.world.in_combat else EXPLORE_TURN
	return t / Game.speed


func _resume() -> void:
	if run.phase == "over":
		Game.goto("run_end")
		return
	if run.phase != "explore":
		_show_phase()
		return
	overlay.visible = false
	if not _paused and timer.is_stopped():
		timer.start(_turn_time())


func _turn() -> void:
	if _paused or not is_inside_tree() or run.phase != "explore":
		return
	if Game.autoplay != "":
		run.world.auto_potions = true
	var floor_before := run.floor_num
	var bag := run.inventory.size()
	var evs := run.tick()
	if Game.autoplay != "" and run.inventory.size() != bag:
		DSAutopilot.equip_best(run)
	grid.set_move_time(_turn_time() * 0.9)
	grid.sync_tokens()      # move first, so hits animate from where everyone ends up
	_play(evs)
	grid.redraw()
	_refresh()
	if run.floor_num != floor_before:
		grid.setup(run)
	_check_low_hp()
	if run.phase == "explore":
		if _shots_left > 0 and run.world.turn % 40 == 0:
			_shot("f%d_t%d" % [run.floor_num, run.world.turn], func(): timer.start(_turn_time()))
		else:
			timer.start(_turn_time())
		return
	Game.save_run()
	if run.phase == "over":
		# Let the last blows land before leaving.
		get_tree().create_timer(1.2 if Game.autoplay == "" else 0.1).timeout.connect(func():
			if is_inside_tree():
				Game.sfx("victory" if run.result != "death" else "defeat")
				Game.goto("run_end"))
		return
	_show_phase()


## Animate a turn's events on the map and add them to the log.
func _play(evs: Array) -> void:
	log_full.add_events(evs)
	var pname := run.world.player.name
	for ev in evs:
		var t: String = ev.get("t", "")
		var src: String = ev.get("src", "")
		var dst: String = ev.get("dst", "")
		var line := CombatText.line(ev)
		if line != "" and t not in ["round", "status_expired"]:
			var col: String = CombatLog.COLORS.get(t, "#e6e1d6")
			if t == "damage" and dst == pname:
				col = "#ff8c7a"
			if t == "shrine":
				col = "#9d7cf2"
			if t == "pickup":
				col = Cards.rarity_color(run.data, str(ev.get("rarity", "common"))).to_html(false)
			_recent.append([line, col])
		match t:
			"damage":
				var amt := int(ev.get("amount", 0))
				var crit: bool = ev.get("crit", false)
				grid.lunge(src, dst)
				grid.flash(dst, Color(1.0, 0.35, 0.3))
				grid.float_text(dst, str(amt), Color("#ffd24a") if crit else (Color("#ff8c7a") if dst == pname else Color.WHITE), 22 if crit else 18)
				Game.sfx("crit" if crit else "hit", randf_range(0.9, 1.1))
				if dst == pname and amt >= int(run.world.player.max_hp * 0.12):
					grid.shake(6.0)
			"miss", "parry", "dodge", "block":
				var who := src if t in ["parry", "dodge", "block"] else dst
				grid.float_text(who, t, UI.DIM, 14)
				Game.sfx("block" if t in ["block", "parry"] else "miss", randf_range(0.9, 1.1))
			"cast":
				grid.flash(src, Color(0.7, 0.5, 1.0))
				Game.sfx("spell")
			"heal":
				if int(ev.get("amount", 0)) > 0:
					grid.float_text(dst, "+%d" % int(ev.get("amount", 0)), Color("#5fd35f"), 18)
				Game.sfx("heal")
			"status_applied":
				grid.float_text(dst, str(ev.get("status", "")).replace("_", " "), Color("#7fc8a9"), 14)
			"phase":
				grid.shake(10.0)
			"death":
				Game.sfx("death")
			"pickup":
				grid.float_text(pname, str(ev.get("name", "")), Cards.rarity_color(run.data, str(ev.get("rarity", "common"))), 14)
			"shrine":
				grid.float_text(pname, "blessed", Color("#9d7cf2"), 18)
				Game.sfx("heal")
			"wake":
				grid.float_text(src, "!", UI.WARN, 22)
	for m in run.messages:
		_recent.append([str(m), "#7fc8a9"])
		log_full.append_text("[color=#7fc8a9]%s[/color]\n" % str(m).replace("[", "[lb]"))
		if str(m).begins_with("Level "):
			Game.sfx("level_up")
	run.messages.clear()
	if _recent.size() > 50:
		_recent = _recent.slice(_recent.size() - 50)


func _refresh() -> void:
	if run.world == null:
		return
	var p := run.world.player
	var L: Dictionary = run.data.classes.get(run.line, {})
	header.text = "Floor %d/%d · %s lv %d · Gold %d" % [run.floor_num, DSRunState.FLOORS, str(L.get("display", run.line)), run.level, run.gold]
	hp_bar.max_value = p.max_hp
	hp_bar.value = p.hp
	mana_bar.visible = p.max_mana > 0
	mana_bar.max_value = maxi(1, p.max_mana)
	mana_bar.value = p.mana
	hp_label.text = "%d/%d" % [maxi(0, p.hp), p.max_hp]
	pot_hp.text = "Potion ×%d" % int(run.potions.get("hp", 0))
	pot_hp.add_theme_color_override("font_color", UI.WARN if p.hp_pct() < 30.0 and not pot_hp.disabled else UI.TEXT)
	pot_hp.disabled = int(run.potions.get("hp", 0)) <= 0 or p.hp >= p.max_hp
	pot_mp.visible = p.max_mana > 0
	pot_mp.text = "Mana ×%d" % int(run.potions.get("mp", 0))
	pot_mp.disabled = int(run.potions.get("mp", 0)) <= 0 or p.mana >= p.max_mana
	speed_btn.text = "Speed %dx" % int(Game.speed)
	extract_btn.disabled = run.world.ambush or run.phase != "explore"
	extract_btn.text = "Ambush!" if run.world.ambush else ("Cancel Extract" if run.world.extracting else "Extract")
	var ups := run.upgrade_slots()
	gear_btn.text = "Gear"
	gear_btn.icon = UI.tex("ui_upgrade") if not ups.is_empty() else null
	gear_btn.expand_icon = true
	gear_btn.add_theme_constant_override("icon_max_width", 24)
	gear_btn.add_theme_color_override("icon_normal_color", Color("#5fd35f"))
	gear_btn.add_theme_color_override("icon_hover_color", Color("#5fd35f"))
	_set_gear_glow(not ups.is_empty())
	for c in log_strip.get_children():
		c.queue_free()
	var shown := _recent.slice(maxi(0, _recent.size() - LOG_LINES))
	for e in shown:
		var l := UI.label(str(e[0]), 17, Color(str(e[1])), false)
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		log_strip.add_child(l)


# --- phases: boon, event, end of floor -------------------------------------------

func _clear_overlay() -> void:
	for c in overlay.get_children():
		c.queue_free()


func _overlay_box() -> VBoxContainer:
	_clear_overlay()
	overlay.visible = true
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.05, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 24)
	m.add_theme_constant_override("margin_top", 60)
	m.add_theme_constant_override("margin_bottom", 40)
	overlay.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	m.add_child(v)
	return v


func _show_phase() -> void:
	_refresh()
	match run.phase:
		"boon":
			_show_boons()
		"event":
			_show_event()
		"floor_end":
			_show_floor_end()
		"extract_choice":
			_show_extract_choice()


## Boon pick: takes over the whole screen.
func _show_boons() -> void:
	var v := _overlay_box()
	var src := {"level": "Level up!", "shrine": "A shrine hums with power", "elite": "Trophy of the hunt"}
	var t := UI.label(str(src.get(run.offer_source, "A boon")), 22, UI.DIM)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var h := UI.label("Choose a boon", 40, UI.ACCENT)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	Game.sfx("level_up")
	var banish_left := int(run.charges.get("banish", 0))
	for i in run.offer.size():
		var ii := i
		var card := _big_boon(str(run.offer[i]), str(run.offer_rarity[i]) if i < run.offer_rarity.size() else "common", func(): _take_boon(ii))
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if banish_left > 0:
			# Small Banish button in the card's top-right corner.
			var bb := UI.button("Banish", func(): _banish_boon(ii), 40)
			bb.add_theme_font_size_override("font_size", 16)
			bb.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			bb.position = Vector2(-110, 8)
			bb.size = Vector2(100, 40)
			bb.add_theme_color_override("font_color", UI.WARN)
			card.add_child(bb)
			card.resized.connect(func(): bb.position = Vector2(card.size.x - 110, 8))
		v.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var skip := UI.button("Skip (%d)" % int(run.charges.get("skip", 0)), _skip_boon, 56)
	skip.disabled = int(run.charges.get("skip", 0)) <= 0
	var rr := UI.button("Reroll (%d)" % int(run.charges.get("reroll", 0)), _reroll_boons, 56)
	rr.disabled = int(run.charges.get("reroll", 0)) <= 0
	for b in [skip, rr]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	v.add_child(row)
	if banish_left > 0:
		var bl := UI.label("Banish left this run: %d" % banish_left, 16, UI.DIM)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(bl)
	Hint.show(self, "boon")
	if Game.autoplay != "":
		_shot("boon_f%d" % run.floor_num, func(): _take_boon(0))


func _big_boon(id: String, rarity: String, on_take: Callable) -> Button:
	var b: Dictionary = run.data.boons.get(id, {})
	var has_rarity: bool = not b.get("effect", {}).get("stats", {}).is_empty() or b.has("fixed_rarity")
	var rcol := Color(str(run.data.boon_rarities().get(rarity, {}).get("color", "#d6a64f"))) if has_rarity else UI.ACCENT
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 190)
	btn.pressed.connect(func(): Game.sfx("click"))
	btn.pressed.connect(on_take)
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#1d1a26")
	st.border_color = rcol.darkened(0.2)
	st.set_border_width_all(3 if has_rarity and rarity != "common" else 2)
	st.set_corner_radius_all(14)
	st.set_content_margin_all(18)
	btn.add_theme_stylebox_override("normal", st)
	var hv := st.duplicate()
	hv.border_color = rcol
	hv.bg_color = Color("#2a2534")
	btn.add_theme_stylebox_override("hover", hv)
	btn.add_theme_stylebox_override("pressed", hv)
	btn.add_theme_stylebox_override("focus", st)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 18)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	var ic := UI.icon("boon", 72, rcol)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var n := UI.label(str(b.get("name", id)), 28, UI.ACCENT)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(n)
	if has_rarity:
		var rl := UI.label(rarity.capitalize(), 17, rcol)
		rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(rl)
	var mx := run.boon_max(id)
	if mx > 1:
		var have := run.boon_rank(id)
		var rk := UI.label("Stackable · you have %d" % have if have > 0 else "Stackable", 16, Color("#7fc8a9"))
		rk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(rk)
	var d := UI.label(run.boon_desc(id, rarity), 19)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(d)
	# Families: progress toward the next bonus if you take this boon.
	var counts := DSFactory.family_counts(run.data, run.boons)
	for t in b.get("tags", []):
		var fam: Dictionary = run.data.families.get(t, {})
		var now := int(counts.get(t, 0))
		var after := now + (0 if run.boons.has(id) else 1)
		var next_txt := ""
		for th in ["2", "4", "6"]:
			if after < int(th):
				next_txt = "next at %s: %s" % [th, str(fam.get("tiers", {}).get(th, {}).get("text", ""))]
				break
			if after == int(th) and now < int(th):
				next_txt = "unlocks: %s" % str(fam.get("tiers", {}).get(th, {}).get("text", ""))
				break
		var ftxt := "%s %d to %d · %s" % [str(fam.get("name", t)), now, after, next_txt] if after != now else "%s %d · %s" % [str(fam.get("name", t)), now, next_txt]
		var fl := UI.tag("ui_family", ftxt, 15, Color(str(fam.get("color", "#e6e1d6"))))
		col.add_child(fl)
	return btn


func _take_boon(i: int) -> void:
	if run.phase != "boon":
		return
	run.take_boon(i)
	_after_choice()


func _skip_boon() -> void:
	if run.skip_boon():
		_after_choice()


func _reroll_boons() -> void:
	if run.reroll_boons():
		Game.save_run()
		_show_boons()


func _banish_boon(i: int) -> void:
	if run.banish_boon(i):
		Game.save_run()
		if run.phase == "boon":
			_show_boons()
		else:
			_after_choice()


func _show_event() -> void:
	var v := _overlay_box()
	var ev := run.event_def()
	v.add_child(UI.label(str(ev.get("title", "Something strange")), 32, Color("#5f9fd3")))
	v.add_child(UI.label(str(ev.get("text", "")), 20))
	if not run.event_outcome.is_empty():
		for line in run.event_outcome:
			v.add_child(UI.label(str(line), 20, Color("#7fc8a9")))
		v.add_child(UI.spacer())
		v.add_child(UI.button("Continue", func():
			run.event_done()
			_after_choice(), 64))
		if Game.autoplay != "":
			Game.auto_next("event_done", func():
				run.event_done()
				_after_choice())
		return
	v.add_child(UI.spacer())
	var opts: Array = ev.get("options", [])
	for i in opts.size():
		var ii := i
		v.add_child(UI.button(str(opts[i].get("label", "?")), func():
			run.event_choose(ii)
			_show_event(), 64))
	Hint.show(self, "event")
	if Game.autoplay != "":
		_shot("event_f%d" % run.floor_num, func():
			run.event_choose(0)
			_show_event())


func _show_floor_end() -> void:
	var v := _overlay_box()
	v.add_child(UI.spacer())
	var t := UI.label("Floor %d cleared" % run.floor_num, 38, UI.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UI.label("The stair spirals down into the dark.", 20, UI.DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	# No input for 3 seconds: carry on down on your own.
	var cd := UI.label("", 24, UI.ACCENT)
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cd)
	v.add_child(UI.spacer())
	v.add_child(UI.button("Descend to floor %d" % (run.floor_num + 1), _descend, 72))
	v.add_child(UI.label("To leave with your loot, use Extract during the floor.", 16, UI.DIM))
	v.add_child(UI.button("Gear", _open_gear, 56))
	if Game.autoplay == "":
		Hint.show(self, "floor_end", func(): _auto_descend(cd, 3))
	else:
		Hint.show(self, "floor_end")
	if Game.autoplay != "":
		print("[autoplay] floor %d cleared, level %d, HP %d, gold %d, turn %d" % [run.floor_num, run.level, run.world.player.hp, run.gold, run.world.turn])
		if run.floor_num == 1 and OS.get_cmdline_user_args().has("--shots") and not _gear_shown:
			_gear_shown = true
			_shot("floor_end", func(): Game.goto("gear"))
			return
		_shot("floor_end", _descend)


## Countdown on the floor-cleared panel. Stops if the panel goes away (a button was pressed).
func _auto_descend(lbl: Label, left: int) -> void:
	if not is_instance_valid(lbl) or not lbl.is_inside_tree() or run.phase != "floor_end":
		return
	if left <= 0:
		_descend()
		return
	lbl.text = "Descending in %d..." % left
	get_tree().create_timer(1.0).timeout.connect(func(): _auto_descend(lbl, left - 1))


## Extract: the character walks back to this floor's entrance first.
func _extract_pressed() -> void:
	if run.world.extracting:
		run.cancel_extract()
		_recent.append(["Extraction cancelled. Exploring again.", "#7fc8a9"])
		Game.save_run()
		_refresh()
		return
	if not run.can_extract():
		return
	run.request_extract()
	_recent.append(["Heading back to the entrance to extract...", "#7fc8a9"])
	Game.save_run()
	_refresh()


func _show_extract_choice() -> void:
	var v := _overlay_box()
	v.add_child(UI.spacer())
	var t := UI.label("The way out", 38, Color("#7fc8a9"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var carried := run.inventory.size() + run.items.values().filter(func(x): return x != null).size()
	var s := UI.label("You're back at the entrance with %d gold and %d items.\n\nThe way up is watched: %d%% of the time you'll be ambushed and have to fight through one last stretch before you're out." % [run.gold, carried, int(run._cfg().get("ambush_pct", 80))], 20)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	v.add_child(UI.spacer())
	v.add_child(UI.button("Attempt extraction", func():
		run.extract_choice(true)
		if run.phase == "over":
			Game.save_run()
			Game.goto("run_end")
			return
		grid.setup(run)
		_recent.append(["Ambush! Clear them out to escape.", "#ff7a3d"])
		Game.sfx("defeat")
		_after_choice(), 72))
	v.add_child(UI.button("Keep exploring", func():
		run.extract_choice(false)
		_after_choice(), 60))
	if Game.autoplay != "":
		_shot("extract_choice", func():
			run.extract_choice(true)
			if run.phase == "over":
				Game.goto("run_end")
			else:
				grid.setup(run)
				_after_choice())


func _descend() -> void:
	if run.phase != "floor_end":
		return
	run.descend()
	grid.setup(run)
	_recent.append(["You descend to floor %d." % run.floor_num, "#d6a64f"])
	_after_choice()


func _after_choice() -> void:
	Game.save_run()
	_clear_overlay()
	overlay.visible = false
	grid.sync_tokens(true)
	grid.redraw()
	_refresh()
	_resume()


# --- buttons -------------------------------------------------------------------

func _drink(kind: String) -> void:
	if run.world == null or not run.world.drink(kind):
		return
	_play(run.world.events.slice(run.world.events.size() - 1))
	grid.sync_tokens()
	_refresh()
	Game.save_run()


## Dropping under 30% HP slows the game to 1x once, so there's time to reach for a potion.
## It re-arms when HP climbs back above 50%.
var _low_hp_armed := true


func _check_low_hp() -> void:
	if run.world == null or Game.autoplay != "":
		return
	var pct := run.world.player.hp_pct()
	if pct >= 50.0:
		_low_hp_armed = true
	elif pct < 30.0 and _low_hp_armed and run.world.player.is_alive():
		_low_hp_armed = false
		if Game.speed > 1.0:
			Game.speed = 1.0
			_recent.append(["Low health! Slowed to 1x.", "#ff7a3d"])
			grid.float_text(run.world.player.name, "LOW HP", UI.WARN, 20)
			_refresh()


## In-run settings: volume, and a way back to the title (the run is saved).
func _open_settings() -> void:
	_paused = true
	timer.stop()
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.z_index = 90
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 32)
	layer.add_child(m)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(col)
	var card := PanelContainer.new()
	col.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)
	v.add_child(UI.label("Settings", 30, UI.ACCENT))
	v.add_child(UI.label("Sound volume", 20, UI.DIM))
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = float(Game.settings.get("sfx_volume", 0.8))
	vol.custom_minimum_size = Vector2(0, 48)
	vol.value_changed.connect(func(x):
		Game.settings["sfx_volume"] = x
		Game.save_settings()
		Game.sfx("hit"))
	v.add_child(vol)
	v.add_child(UI.button("Resume", func():
		layer.queue_free()
		_paused = false
		_resume(), 60))
	v.add_child(UI.button("Guide", func():
		Game.save_run()
		load("res://game/scenes/guide.gd").back_to = "dungeon"
		Game.goto("guide"), 56))
	v.add_child(UI.button("Save and quit to title", func():
		Game.save_run()
		Game.goto("title"), 56))


## Gear button pulses green while a pure upgrade is waiting in the bag.
var _glow: Tween


func _set_gear_glow(on: bool) -> void:
	if on == (_glow != null and _glow.is_valid()):
		return
	if _glow != null:
		_glow.kill()
		_glow = null
	if on:
		gear_btn.add_theme_color_override("font_color", Color("#5fd35f"))
		_glow = create_tween().set_loops()
		_glow.tween_property(gear_btn, "modulate", Color(1.35, 1.6, 1.35), 0.6)
		_glow.tween_property(gear_btn, "modulate", Color.WHITE, 0.6)
	else:
		gear_btn.remove_theme_color_override("font_color")
		gear_btn.modulate = Color.WHITE


func _toggle_speed() -> void:
	Game.speed = 1.0 if Game.speed >= 4.0 else Game.speed * 2.0
	if Game.autoplay == "":
		Game.settings["speed"] = Game.speed
		Game.save_settings()
	_refresh()


func _toggle_log() -> void:
	log_layer.visible = not log_layer.visible


func _open_gear() -> void:
	timer.stop()
	_paused = true
	Game.save_run()
	Game.goto("gear")


func _shot(name: String, next: Callable) -> void:
	if _shots_left > 0:
		_shots_left -= 1
		Game.auto_next(name, next, 0.4)
	else:
		next.call()
