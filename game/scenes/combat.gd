extends Control
## Plays back one fight from CombatSim, about one round per second (2x / 4x toggle).
## Stage view: enemy and player portraits with hit flashes, lunges, floating numbers, death
## animations, screen shake and sound. The MUD-style text log is a toggle.
## The character fights on its own; the player can only drink potions.

const ROUND_TIME := 1.0

var sim: CombatSim
var player: Combatant
var enemies: Array = []
var run: DSRunState
var pots := {}

var root_box: VBoxContainer
var stage: VBoxContainer
var log_view: CombatLog
var log_frame: PanelContainer
var fx_layer: Control
var cards := {}                # name -> {icon, holder, bar, mana, status, name}
var hp_pot: Button
var mp_pot: Button
var speed_btn: Button
var log_btn: Button
var continue_btn: Button
var timer: Timer
var queue: Array = []          # events waiting to be shown this round
var _gap := 0.0
var _gap_left := 0.0
var _shake_tween: Tween


func _ready() -> void:
	run = Game.run
	player = run.make_player()
	enemies = run.fight_monsters()
	sim = CombatSim.new(run.fight_rng(), Game.data)
	pots = run.potions.duplicate()
	root_box = UI.screen(self)

	stage = VBoxContainer.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_theme_constant_override("separation", 10)
	root_box.add_child(stage)
	var grid := GridContainer.new()
	grid.columns = 2 if enemies.size() > 1 else 1
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(grid)
	for e in enemies:
		grid.add_child(_enemy_card(e, 150 if enemies.size() > 2 else 200))
	stage.add_child(_player_card())

	log_frame = PanelContainer.new()
	log_view = CombatLog.new()
	log_view.player_name = player.name
	log_frame.add_child(log_view)
	root_box.add_child(log_frame)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	hp_pot = UI.button("", func(): _potion("hp"))
	mp_pot = UI.button("", func(): _potion("mp"))
	speed_btn = UI.button("", _toggle_speed)
	log_btn = UI.button("Log", _toggle_log)
	for b in [hp_pot, mp_pot, speed_btn, log_btn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	root_box.add_child(row)
	continue_btn = UI.button("Continue", _continue, 72)
	continue_btn.visible = false
	root_box.add_child(continue_btn)

	fx_layer = Control.new()
	fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx_layer)

	_apply_log_mode()
	log_view.add_events(sim.begin(player, enemies))
	_refresh()
	timer = Timer.new()
	timer.wait_time = ROUND_TIME / Game.speed
	timer.timeout.connect(_tick)
	add_child(timer)
	Hint.show(self, "fight", func(): timer.start())


# --- cards -------------------------------------------------------------------

func _enemy_card(e: Combatant, size: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(v)
	var mid := str(e.id).rsplit("_", true, 1)[0]
	var col := Color(str(Game.data.monsters.get(mid, {}).get("color", "#c9c2b6")))
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var ic := UI.icon("mon_" + mid, size, col)
	holder.add_child(ic)
	v.add_child(holder)
	var nm := UI.label(e.name, 18, UI.TEXT, false)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	v.add_child(nm)
	var bar := UI.bar(UI.ENEMY_HP, 12)
	v.add_child(bar)
	var st := UI.label("", 15, UI.DIM, false)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.clip_text = true
	v.add_child(st)
	cards[e.name] = {"icon": ic, "holder": holder, "bar": bar, "status": st, "name": nm, "color": col, "c": e}
	return card


func _player_card() -> PanelContainer:
	var card := PanelContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	card.add_child(h)
	var L: Dictionary = Game.data.classes.get(run.line, {})
	var col := Color(str(L.get("color", "#d6a64f")))
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(110, 110)
	var ic := UI.icon("class_" + run.line, 110, col)
	holder.add_child(ic)
	h.add_child(holder)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var nm := UI.label("%s · level %d · floor %d" % [str(L.get("display", run.line)), run.level, run.floor_num], 20, col, false)
	v.add_child(nm)
	var hp_l := UI.label("", 18, UI.TEXT, false)
	v.add_child(hp_l)
	var bar := UI.bar(UI.HP, 22)
	v.add_child(bar)
	var mana := UI.bar(UI.MANA, 10)
	mana.visible = player.max_mana > 0
	v.add_child(mana)
	var st := UI.label("", 15, UI.DIM, false)
	st.clip_text = true
	v.add_child(st)
	cards[player.name] = {"icon": ic, "holder": holder, "bar": bar, "mana": mana, "status": st, "name": nm, "hp_label": hp_l, "color": col, "c": player}
	return card


# --- playback -------------------------------------------------------------------

func _tick() -> void:
	if sim.over:
		return
	if Game.autoplay != "":
		if player.hp_pct() < 30.0:
			_potion("hp")
		if player.max_mana > 0 and player.mana_pct() < 15.0:
			_potion("mp")
	var evs := sim.step()
	log_view.add_events(evs)
	queue = evs.filter(func(e): return e.get("t") in ["damage", "miss", "parry", "dodge", "block", "cast", "ability", "heal", "death", "status_applied", "phase", "stance"])
	_gap = (ROUND_TIME / Game.speed) * 0.85 / maxf(1.0, float(queue.size()))
	_gap_left = 0.0
	if Game.autoplay != "" and sim.round_num == 3 and OS.get_cmdline_user_args().has("--shots"):
		timer.paused = true
		Game.auto_next("combat_mid_f%d_s%d" % [run.floor_num, run.step], func(): timer.paused = false, 0.25)
	if sim.over:
		timer.stop()
		# Let the queued animations play, then finish.
		get_tree().create_timer(ROUND_TIME / Game.speed).timeout.connect(_end)


func _process(delta: float) -> void:
	if queue.is_empty():
		return
	_gap_left -= delta
	while _gap_left <= 0.0 and not queue.is_empty():
		_show(queue.pop_front())
		_gap_left += _gap


func _show(ev: Dictionary) -> void:
	var t: String = ev.get("t", "")
	var dst: String = ev.get("dst", "")
	var src: String = ev.get("src", "")
	match t:
		"damage":
			var amt := int(ev.get("amount", 0))
			var crit: bool = ev.get("crit", false)
			_lunge(src, dst)
			_flash(dst, Color(1.0, 0.35, 0.3))
			_float(dst, str(amt), Color("#ffd24a") if crit else (Color("#ff8c7a") if dst == player.name else Color.WHITE), 34 if crit else 26)
			_set_hp(dst, int(ev.get("hp", 0)), int(ev.get("max_hp", 1)))
			Game.sfx("crit" if crit else "hit", randf_range(0.9, 1.1))
			if dst == player.name and amt >= int(player.max_hp * 0.12):
				_screen_shake(10.0)
			elif crit:
				_screen_shake(5.0)
		"miss", "parry", "dodge", "block":
			var who := src if t in ["parry", "dodge", "block"] else dst
			_float(who, {"miss": "miss", "parry": "parry", "dodge": "dodge", "block": "block"}[t], UI.DIM, 20)
			Game.sfx("block" if t in ["block", "parry"] else "miss", randf_range(0.9, 1.1))
		"cast":
			_flash(src, Color(0.7, 0.5, 1.0))
			Game.sfx("spell")
		"ability":
			_pulse(src)
		"heal":
			var amt := int(ev.get("amount", 0))
			if amt > 0:
				_float(dst, "+%d" % amt, Color("#5fd35f"), 24)
			Game.sfx("heal")
		"status_applied":
			_float(dst, str(ev.get("status", "")).replace("_", " "), Color("#7fc8a9"), 18)
		"stance":
			_float(src, "%s dance" % ev.get("stance", ""), UI.ACCENT, 20)
		"phase":
			_screen_shake(14.0)
			_flash(src, Color(1.0, 0.6, 0.2))
		"death":
			_die(src)
			Game.sfx("death")


func _card(n: String):
	return cards.get(n, null)


func _set_hp(n: String, hp: int, max_hp: int) -> void:
	var c = _card(n)
	if c == null:
		return
	c["bar"].max_value = max_hp
	var tw := create_tween()
	tw.tween_property(c["bar"], "value", hp, 0.15)


func _flash(n: String, col: Color) -> void:
	var c = _card(n)
	if c == null:
		return
	var ic: TextureRect = c["icon"]
	var base: Color = c["color"]
	if not c["c"].is_alive():
		return
	var tw := create_tween()
	tw.tween_property(ic, "modulate", col, 0.05)
	tw.tween_property(ic, "modulate", base, 0.2)


func _pulse(n: String) -> void:
	var c = _card(n)
	if c == null:
		return
	var ic: TextureRect = c["icon"]
	ic.pivot_offset = ic.size / 2.0
	var tw := create_tween()
	tw.tween_property(ic, "scale", Vector2(1.12, 1.12), 0.08)
	tw.tween_property(ic, "scale", Vector2.ONE, 0.12)


## Attacker leans toward the defender: enemies up/down toward the player and back.
func _lunge(src: String, dst: String) -> void:
	var c = _card(src)
	if c == null or src == dst:
		return
	var ic: TextureRect = c["icon"]
	var dir := Vector2(0, -14) if src == player.name else Vector2(0, 14)
	var tw := create_tween()
	tw.tween_property(ic, "position", dir, 0.06)
	tw.tween_property(ic, "position", Vector2.ZERO, 0.12)


func _die(n: String) -> void:
	var c = _card(n)
	if c == null:
		return
	var ic: TextureRect = c["icon"]
	ic.pivot_offset = ic.size / 2.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(ic, "modulate", Color(0.4, 0.4, 0.4, 0.25), 0.5)
	tw.tween_property(ic, "rotation", deg_to_rad(80.0 if n != player.name else -80.0), 0.5).set_trans(Tween.TRANS_BACK)
	tw.tween_property(ic, "position", Vector2(0, 20), 0.5)
	c["name"].modulate = Color(1, 1, 1, 0.4)


func _float(n: String, text: String, col: Color, size: int) -> void:
	var c = _card(n)
	if c == null:
		return
	var holder: Control = c["holder"]
	var l := UI.label(text, size, col, false)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	fx_layer.add_child(l)
	var r := holder.get_global_rect()
	l.position = r.position + Vector2(r.size.x * 0.5 - 20 + randf_range(-24, 24), r.size.y * 0.3)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 70, 0.8).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


func _screen_shake(amount: float) -> void:
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	for i in 6:
		_shake_tween.tween_property(root_box.get_parent(), "position", Vector2(randf_range(-amount, amount), randf_range(-amount, amount)), 0.03)
	_shake_tween.tween_property(root_box.get_parent(), "position", Vector2.ZERO, 0.04)


# --- state --------------------------------------------------------------------

func _refresh() -> void:
	for n in cards.keys():
		var c: Dictionary = cards[n]
		var who: Combatant = c["c"]
		c["bar"].max_value = who.max_hp
		c["bar"].value = who.hp
		c["status"].text = "dead" if not who.is_alive() else _statuses(who)
		if c.has("mana"):
			c["mana"].max_value = maxi(1, who.max_mana)
			c["mana"].value = who.mana
			c["hp_label"].text = "HP %d/%d%s" % [who.hp, who.max_hp, ("   Mana %d/%d" % [who.mana, who.max_mana]) if who.max_mana > 0 else ""]
	hp_pot.text = "HP potion (%d)" % int(pots.get("hp", 0))
	mp_pot.text = "MP potion (%d)" % int(pots.get("mp", 0))
	hp_pot.disabled = int(pots.get("hp", 0)) <= 0 or sim.over
	mp_pot.disabled = int(pots.get("mp", 0)) <= 0 or sim.over
	mp_pot.visible = player.max_mana > 0
	speed_btn.text = "%dx" % int(Game.speed)


func _statuses(c: Combatant) -> String:
	var parts: Array = []
	if c.stance != "":
		parts.append(c.stance)
	for s in c.statuses.keys():
		if not str(s).begins_with("stance_"):
			parts.append(str(s).replace("_", " "))
	return ", ".join(PackedStringArray(parts))


func _physics_process(_delta: float) -> void:
	# Keep text bits (statuses, HP label) fresh between rounds without touching animated bars.
	if is_instance_valid(hp_pot):
		for n in cards.keys():
			var c: Dictionary = cards[n]
			var who: Combatant = c["c"]
			c["status"].text = "dead" if not who.is_alive() else _statuses(who)
			if c.has("hp_label"):
				c["hp_label"].text = "HP %d/%d%s" % [maxi(0, who.hp), who.max_hp, ("   Mana %d/%d" % [who.mana, who.max_mana]) if who.max_mana > 0 else ""]
				c["mana"].value = who.mana


func _potion(kind: String) -> void:
	if int(pots.get(kind, 0)) <= 0 or sim.over:
		return
	pots[kind] = int(pots[kind]) - 1
	sim.events = []
	sim.use_potion(kind)
	log_view.add_events(sim.events)
	for ev in sim.events:
		_show(ev)
	_refresh()


func _toggle_speed() -> void:
	Game.speed = 1.0 if Game.speed >= 4.0 else Game.speed * 2.0
	if Game.autoplay == "":
		Game.settings["speed"] = Game.speed
		Game.save_settings()
	timer.wait_time = ROUND_TIME / Game.speed
	_refresh()


func _toggle_log() -> void:
	Game.settings["log_open"] = not bool(Game.settings.get("log_open", false))
	Game.save_settings()
	_apply_log_mode()


## Log closed: compact strip under the stage. Log open: the log takes over the stage area.
func _apply_log_mode() -> void:
	var open := bool(Game.settings.get("log_open", false))
	stage.visible = not open
	log_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL if open else Control.SIZE_FILL
	log_frame.custom_minimum_size = Vector2(0, 0 if open else 190)
	log_btn.text = "Stage" if open else "Log"


func _end() -> void:
	if not is_inside_tree() or continue_btn.visible:
		return
	_refresh()
	Game.sfx("victory" if sim.result == "win" else "defeat")
	run.finish_fight(player, enemies, sim.result, pots)
	Game.save_run()
	continue_btn.visible = true
	continue_btn.text = "Continue" if sim.result == "win" else "See the end"
	if Game.autoplay != "":
		print("[autoplay] fight over: %s in %d rounds, HP %d/%d, log lines %d" % [sim.result, sim.round_num, player.hp, player.max_hp, log_view.get_line_count()])
		Game.auto_next("combat_end_f%d_s%d" % [run.floor_num, run.step], _continue)


func _continue() -> void:
	Game.goto("run_end" if run.phase == "over" else "dungeon")
