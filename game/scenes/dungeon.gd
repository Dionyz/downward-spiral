extends Control
## The run screen: the floor as a dungeon map with your character walking it, and below it
## whatever the current room needs. Exploration is automatic; you choose at forks, at events,
## and which boon to take. Gear opens the inventory.

const TYPE_LABEL := {"fight": "Fight", "elite": "Elite", "boss": "Boss", "treasure": "Treasure",
	"shrine": "Shrine", "rest": "Rest", "event": "Event"}
const TYPE_COLOR := MapView.TYPE_COLOR
const AUTO_DELAY := 0.9

var run: DSRunState
var header: Label
var subheader: Label
var map: MapView
var body: VBoxContainer
var gear_btn: Button
var auto_timer: Timer
var _auto_paused := false
var _busy := false              # true while the token is walking
static var _gear_shown := false   # screenshot runs visit the gear screen once


func _ready() -> void:
	run = Game.run
	var v := UI.screen(self)
	header = UI.label("", 26, UI.ACCENT)
	v.add_child(header)
	subheader = UI.label("", 17, UI.DIM)
	v.add_child(subheader)
	var frame := PanelContainer.new()
	map = MapView.new()
	frame.add_child(map)
	v.add_child(frame)
	map.setup(run)
	map.room_tapped.connect(func(j): _enter(j))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	v.add_child(scroll)
	gear_btn = UI.button("Gear", _open_gear, 56)
	v.add_child(gear_btn)
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
	var pots := "Potions %d" % int(run.potions.get("hp", 0))
	if p.max_mana > 0:
		pots += "+%d MP" % int(run.potions.get("mp", 0))
	parts.append(pots)
	subheader.text = "  ·  ".join(PackedStringArray(parts))
	gear_btn.text = "Gear  (bag %d)" % run.inventory.size()
	map.setup(run)
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
	if run.phase == "reward":
		hid = "reward"
	elif run.phase == "floor_end":
		hid = "floor_end"
	elif run.phase == "room" and run.room.get("type", "") in ["rest", "shrine", "event"]:
		hid = str(run.room["type"])
	if hid != "" and Hint.seen("dungeon"):
		Hint.show(self, hid)
	_maybe_autoplay()


func _room_title(rm: Dictionary) -> void:
	var t: String = rm.get("type", "")
	var nm: String = rm.get("name", "")
	if t == "event" and rm.has("event"):
		nm = str(run.data.events.get(rm["event"], {}).get("title", nm))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(UI.icon("room_" + t, 48, Color(TYPE_COLOR.get(t, "#e6e1d6"))))
	var tl := UI.label("%s — %s" % [TYPE_LABEL.get(t, t), nm], 24, Color(TYPE_COLOR.get(t, "#e6e1d6")))
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	body.add_child(head)
	if t != "event" or not rm.has("event"):
		body.add_child(UI.label(str(rm.get("desc", "")), 18, UI.DIM))


func _show_path() -> void:
	var options := run.current_step()
	if options.size() > 1:
		body.add_child(UI.label("The path splits. Tap a room on the map, or:", 22, UI.ACCENT))
		for j in options.size():
			var rm: Dictionary = options[j]
			var t: String = rm.get("type", "")
			var jj: int = j
			body.add_child(UI.button("%s — %s" % [TYPE_LABEL.get(t, t), rm.get("name", "")], func(): _enter(jj), 58))
	else:
		var rm: Dictionary = options[0]
		var t: String = rm.get("type", "")
		body.add_child(UI.label("Heading for: %s — %s" % [TYPE_LABEL.get(t, t), rm.get("name", "")], 20, Color(TYPE_COLOR.get(t, "#e6e1d6"))))
		_schedule_auto()


func _show_room() -> void:
	var rm := run.room
	_room_title(rm)
	match rm.get("type", ""):
		"fight", "elite", "boss":
			var foes := run.fight_monsters()
			body.add_child(UI.label("Ahead: " + ", ".join(PackedStringArray(foes.map(func(f): return f.name))), 20))
			body.add_child(UI.button("Fight", _fight, 64))
			_schedule_auto()
		"treasure":
			body.add_child(UI.label("You pry open the chest.", 20))
			_show_loot(rm.get("loot", []))
			body.add_child(UI.button("Continue", _skip, 60))
		"shrine":
			_show_shrine()
		"rest":
			body.add_child(UI.label("A quiet corner to catch your breath.", 20))
			body.add_child(UI.button("Rest (recover %d%% HP and mana)" % int(run._cfg().get("rest_heal_pct", 40)), _rest_heal, 64))
		"event":
			_show_event()


## Items that just landed: name, whether it went on or into the bag, and how it compares.
func _show_loot(loot: Array) -> void:
	if loot.is_empty():
		return
	body.add_child(UI.label("Loot", 20, UI.DIM))
	for entry in loot:
		var it: Dictionary = entry["item"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var col := Cards.rarity_color(run.data, str(it.get("rarity", "common")))
		row.add_child(UI.icon("item_" + str(it.get("slot", "weapon")), 32, col))
		var nm := UI.label(str(it.get("name", "?")), 19, col)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		if entry.get("equipped", false):
			row.add_child(UI.label("equipped", 16, Color("#7fc8a9"), false))
		else:
			var eq = run.items.get(it.get("slot", ""))
			var delta := DSLoot.power(it) - (0 if eq == null else DSLoot.power(eq))
			row.add_child(UI.label(("bag  +%d" % delta) if delta > 0 else "bag", 16, Color("#5fd35f") if delta > 0 else UI.DIM, false))
		body.add_child(row)


func _show_shrine() -> void:
	body.add_child(UI.label("Choose a boon.", 20))
	var offers: Array = run.room.get("offers", [])
	for i in offers.size():
		_boon_card(offers[i], i)
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
	body.add_child(UI.label("Victory", 28, UI.ACCENT))
	var bits: Array = ["+%d gold" % int(rw.get("gold", 0)), "+%d XP" % int(rw.get("xp", 0))]
	if rw.has("potion"):
		bits.append("+1 %s potion" % str(rw["potion"]).to_upper())
	body.add_child(UI.label("   ".join(PackedStringArray(bits)), 20))
	_show_loot(rw.get("loot", []))
	var offers: Array = rw.get("offers", [])
	if not offers.is_empty():
		body.add_child(UI.label("Choose a boon", 22, UI.ACCENT))
		for i in offers.size():
			_boon_card(offers[i], i)
		body.add_child(UI.button("Skip the boon", _skip, 52))
	else:
		body.add_child(UI.button("Continue", _skip, 60))


func _show_floor_end() -> void:
	body.add_child(UI.label("Floor %d cleared." % run.floor_num, 28, UI.ACCENT))
	body.add_child(UI.label("The stair spirals down into the dark.", 18, UI.DIM))
	body.add_child(UI.button("Descend to floor %d" % (run.floor_num + 1), _descend, 68))
	if run.can_extract():
		body.add_child(UI.button("Extract (keep %d gold, %d XP)" % [run.gold, run.xp_total], _extract, 60))
	else:
		body.add_child(UI.label("You can extract from the end of floor 2.", 16, UI.DIM))


func _boon_card(o: Dictionary, i: int) -> void:
	var ii := i
	body.add_child(Cards.boon_card(run.data, str(o.get("id", "")), func(): _take(ii)))


# --- actions --------------------------------------------------------------

func _after() -> void:
	Game.save_run()
	_refresh()


## Walk to the room, then enter it.
func _enter(choice: int) -> void:
	auto_timer.stop()
	if run.phase != "path" or _busy:
		return
	_busy = true
	map.walk_to(run.step, choice, func():
		_busy = false
		if not is_inside_tree():
			return
		run.enter(choice)
		_after()
	)


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
	if _busy:
		return
	_busy = true
	map.walk_to(-1, 0, func():
		_busy = false
		if not is_inside_tree():
			return
		run.descend()
		_after()
	)


func _extract() -> void:
	run.extract()
	_after()


func _open_gear() -> void:
	auto_timer.stop()
	Game.save_run()
	Game.goto("gear")


# --- auto exploration -------------------------------------------------------

func _schedule_auto() -> void:
	if Game.autoplay == "" and not _auto_paused:
		auto_timer.start(AUTO_DELAY)


func _auto_advance() -> void:
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
	if not is_inside_tree() or _busy:
		return
	print("[autoplay] at floor %d step %d phase %s room %s bag %d" % [run.floor_num, run.step, run.phase, run.room.get("type", "-"), run.inventory.size()])
	if run.is_fight_room():
		_fight()
		return
	if run.phase == "path":
		_enter(0)
		return
	if run.phase == "floor_end":
		print("[autoplay] floor %d cleared, level %d, HP %d, gold %d" % [run.floor_num, run.level, run.make_player().hp, run.gold])
		if run.floor_num == 1 and OS.get_cmdline_user_args().has("--shots") and not _gear_shown:
			_gear_shown = true
			# Show the gear screen once in screenshot runs.
			Game.goto("gear")
			return
		_descend()
		return
	DSAutopilot.advance(run)
	_after()
