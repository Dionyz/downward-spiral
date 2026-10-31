extends Node
## Autoload "Game": run state for the milestone 4 prototype (one floor of fights).
## Holds data, the run's RNG and the player's carried-over HP, mana, rules and potions.

const SCENES := "res://game/scenes/%s.tscn"

var data: DSData
var rng: DSRng
var seed_value: int = 0
var line: String = "warrior"
var level: int = 1
var fight_index: int = 0
var fights_per_floor: int = 3
var hp: int = -1
var mana: int = -1
var rules: Array = []
var actives: Array = []
var potions := {"hp": 2, "mp": 2}
var result: String = ""        # "", "win", "loss", "extract"
var fights_won: int = 0
var speed: float = 1.0
## Headless smoke test: `godot --headless --path . -- --autoplay warrior` clicks through a whole run.
var autoplay: String = ""


func _ready() -> void:
	data = DSData.load_dir("res://game/data")
	var args := OS.get_cmdline_user_args()
	var i := args.find("--autoplay")
	if i >= 0:
		autoplay = args[i + 1] if i + 1 < args.size() else "warrior"
		speed = 64.0


func new_run(p_line: String, p_seed: int = 0) -> void:
	line = p_line
	seed_value = p_seed if p_seed != 0 else int(Time.get_unix_time_from_system()) % 1000000007
	rng = DSRng.new(seed_value)
	level = 1
	fight_index = 0
	fights_won = 0
	hp = -1
	mana = -1
	result = ""
	potions = {"hp": int(data.balance.get("start_potions_hp", 2)), "mp": int(data.balance.get("start_potions_mp", 2))}
	var p := DSFactory.make_player(data, line, 1, level)
	rules = p.rules.duplicate(true)
	actives = p.actives.duplicate()


## A fresh Combatant for the next fight, carrying HP/mana from the last one.
func make_player() -> Combatant:
	var p := DSFactory.make_player(data, line, 1, level, {"rules": rules, "actives": actives})
	if hp >= 0:
		p.hp = clampi(hp, 1, p.max_hp)
	if mana >= 0:
		p.mana = clampi(mana, 0, p.max_mana)
	return p


func next_encounter() -> Array:
	return DSEncounters.roll_fight(data, rng, 1, level)


## Called by the combat scene when a fight ends.
func finish_fight(p: Combatant, fight_result: String) -> void:
	hp = p.hp
	mana = p.mana
	if fight_result == "win":
		fights_won += 1
		fight_index += 1
		_level_up()
		if fight_index >= fights_per_floor:
			result = "win"
	else:
		result = fight_result


## Prototype levelling: one level per won fight. New actives auto-equip into free slots.
func _level_up() -> void:
	var old := DSFactory.make_player(data, line, 1, level)
	level = mini(10, level + 1)
	var neu := DSFactory.make_player(data, line, 1, level)
	hp += neu.max_hp - old.max_hp
	mana += neu.max_mana - old.max_mana
	for a in DSFactory.default_actives(data, line, 1, level):
		if not actives.has(a) and actives.size() < int(data.balance.get("max_actives", 4)):
			actives.append(a)


func rule_slots() -> int:
	return DSFactory.rule_slots(data, level)


## Autoplay step: wait a moment, optionally save a screenshot (--shots <dir>), then run `next`.
var _shot_n := 0


func auto_next(shot_name: String, next: Callable, delay: float = 0.4) -> void:
	await get_tree().create_timer(delay).timeout
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		await RenderingServer.frame_post_draw
		_shot_n += 1
		var path := "%s/%02d_%s.png" % [args[i + 1], _shot_n, shot_name]
		get_viewport().get_texture().get_image().save_png(path)
	next.call()


func goto(scene: String) -> void:
	get_tree().change_scene_to_file(SCENES % scene)
