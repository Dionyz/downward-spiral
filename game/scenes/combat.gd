extends Control
## Plays back one fight from CombatSim, about one round per second (2x / 4x toggle).
## The character fights on its own; the player can only drink potions.

var sim: CombatSim
var player: Combatant
var enemies: Array = []
var log_view: CombatLog
var enemy_box: VBoxContainer
var enemy_rows := {}
var hp_bar: ProgressBar
var mana_bar: ProgressBar
var hp_label: Label
var status_label: Label
var hp_pot: Button
var mp_pot: Button
var speed_btn: Button
var continue_btn: Button
var timer: Timer
var run: DSRunState
var pots := {}


func _ready() -> void:
	var v := UI.screen(self)
	run = Game.run
	player = run.make_player()
	enemies = run.fight_monsters()
	sim = CombatSim.new(run.fight_rng(), Game.data)
	pots = run.potions.duplicate()

	enemy_box = VBoxContainer.new()
	v.add_child(enemy_box)
	for e in enemies:
		_add_enemy_row(e)

	log_view = CombatLog.new()
	log_view.player_name = player.name
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(log_view)
	v.add_child(frame)

	var L: Dictionary = Game.data.classes.get(run.line, {})
	v.add_child(UI.label("%s · level %d · floor %d" % [str(L.get("display", run.line)), run.level, run.floor_num], 22, UI.ACCENT))
	hp_label = UI.label("", 20)
	v.add_child(hp_label)
	hp_bar = UI.bar(UI.HP, 26)
	v.add_child(hp_bar)
	mana_bar = UI.bar(UI.MANA, 14)
	mana_bar.visible = player.max_mana > 0
	v.add_child(mana_bar)
	status_label = UI.label("", 18, UI.DIM)
	v.add_child(status_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	hp_pot = UI.button("", func(): _potion("hp"))
	mp_pot = UI.button("", func(): _potion("mp"))
	speed_btn = UI.button("", _toggle_speed)
	for b in [hp_pot, mp_pot, speed_btn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	v.add_child(row)
	continue_btn = UI.button("Continue", _continue, 72)
	continue_btn.visible = false
	v.add_child(continue_btn)

	log_view.add_events(sim.begin(player, enemies))
	_refresh()
	timer = Timer.new()
	timer.wait_time = 1.0 / Game.speed
	timer.timeout.connect(_tick)
	add_child(timer)
	timer.start()


func _add_enemy_row(e: Combatant) -> void:
	var box := VBoxContainer.new()
	var top := HBoxContainer.new()
	var nm := UI.label(e.name, 20, UI.TEXT, false)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	var st := UI.label("", 16, UI.DIM, false)
	top.add_child(st)
	box.add_child(top)
	var b := UI.bar(UI.ENEMY_HP, 12)
	box.add_child(b)
	enemy_box.add_child(box)
	enemy_rows[e] = {"name": nm, "bar": b, "status": st}


func _tick() -> void:
	if sim.over:
		return
	if Game.autoplay != "":
		if player.hp_pct() < 30.0:
			_potion("hp")
		if player.max_mana > 0 and player.mana_pct() < 15.0:
			_potion("mp")
	log_view.add_events(sim.step())
	_refresh()
	if Game.autoplay != "" and sim.round_num == 3 and OS.get_cmdline_user_args().has("--shots"):
		timer.paused = true
		Game.auto_next("combat_mid_f%d_s%d" % [run.floor_num, run.step], func(): timer.paused = false, 0.2)
	if sim.over:
		timer.stop()
		_end()


func _refresh() -> void:
	hp_bar.max_value = player.max_hp
	hp_bar.value = player.hp
	mana_bar.max_value = maxi(1, player.max_mana)
	mana_bar.value = player.mana
	hp_label.text = "HP %d/%d%s" % [player.hp, player.max_hp,
		("   Mana %d/%d" % [player.mana, player.max_mana]) if player.max_mana > 0 else ""]
	status_label.text = _statuses(player)
	for e in enemies:
		var r: Dictionary = enemy_rows[e]
		r["bar"].max_value = e.max_hp
		r["bar"].value = e.hp
		r["status"].text = "dead" if not e.is_alive() else _statuses(e)
		r["name"].modulate = Color(1, 1, 1, 0.4) if not e.is_alive() else Color.WHITE
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


func _potion(kind: String) -> void:
	if int(pots.get(kind, 0)) <= 0 or sim.over:
		return
	pots[kind] = int(pots[kind]) - 1
	sim.events = []
	sim.use_potion(kind)
	log_view.add_events(sim.events)
	_refresh()


func _toggle_speed() -> void:
	Game.speed = 1.0 if Game.speed >= 4.0 else Game.speed * 2.0
	timer.wait_time = 1.0 / Game.speed
	_refresh()


func _end() -> void:
	run.finish_fight(player, enemies, sim.result, pots)
	Game.save_run()
	continue_btn.visible = true
	continue_btn.text = "Continue" if sim.result == "win" else "See the end"
	if Game.autoplay != "":
		print("[autoplay] fight over: %s in %d rounds, HP %d/%d, log lines %d" % [sim.result, sim.round_num, player.hp, player.max_hp, log_view.get_line_count()])
		Game.auto_next("combat_end_f%d_s%d" % [run.floor_num, run.step], _continue)


func _continue() -> void:
	Game.goto("run_end" if run.phase == "over" else "dungeon")
