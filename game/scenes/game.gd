extends Node
## Autoload "Game": owns the current DSRunState, the account, and save files.
## Saves: user://run.json (autosaved on every room change), user://account.json.

const SCENES := "res://game/scenes/%s.tscn"
const RUN_SAVE := "user://run.json"
const ACCOUNT_SAVE := "user://account.json"

var data: DSData
var run: DSRunState
var account: Dictionary = {}
var speed: float = 1.0
## Headless smoke test: `godot --headless --path . -- --autoplay warrior` clicks through a whole run.
var autoplay: String = ""
var save_dir: String = ""   # override for autoplay so real saves aren't touched


func _ready() -> void:
	data = DSData.load_dir("res://game/data")
	var args := OS.get_cmdline_user_args()
	var i := args.find("--autoplay")
	if i >= 0:
		autoplay = args[i + 1] if i + 1 < args.size() else "warrior"
		speed = 64.0
		save_dir = "user://autoplay"
		DirAccess.make_dir_recursive_absolute(save_dir)
	account = _read(_path(ACCOUNT_SAVE))


func _path(p: String) -> String:
	return p if save_dir == "" else p.replace("user:/", save_dir)


# --- runs -----------------------------------------------------------------

func new_run(line: String, seed_value: int = 0) -> void:
	if seed_value == 0:
		seed_value = int(Time.get_unix_time_from_system() * 1000.0) % 2147483646 + 1
	run = DSRunState.new_run(data, line, seed_value)
	save_run()


func has_saved_run() -> bool:
	var d := _read(_path(RUN_SAVE))
	return not d.is_empty() and d.get("phase", "over") != "over"


func load_run() -> bool:
	var d := _read(_path(RUN_SAVE))
	if d.is_empty():
		return false
	run = DSRunState.from_dict(data, d)
	return true


func save_run() -> void:
	if run != null:
		_write(_path(RUN_SAVE), run.to_dict())


## Bank the finished run into the account once, and clear the run save.
func finish_run() -> Dictionary:
	if run == null or run.phase != "over":
		return {}
	var b := run.banked()
	if not run.room.get("banked", false):
		account = DSRunState.bank_into(account, run)
		run.room["banked"] = true
		_write(_path(ACCOUNT_SAVE), account)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path(RUN_SAVE)))
	return b


# --- io -------------------------------------------------------------------

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if typeof(v) == TYPE_DICTIONARY else {}


func _write(path: String, d: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))


# --- navigation and autoplay ----------------------------------------------

func goto(scene: String) -> void:
	get_tree().change_scene_to_file(SCENES % scene)


var _shot_n := 0


## Autoplay step: wait a moment, optionally save a screenshot (--shots <dir>), then run `next`.
func auto_next(shot_name: String, next: Callable, delay: float = 0.3) -> void:
	await get_tree().create_timer(delay).timeout
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		await RenderingServer.frame_post_draw
		_shot_n += 1
		var path := "%s/%03d_%s.png" % [args[i + 1], _shot_n, shot_name]
		get_viewport().get_texture().get_image().save_png(path)
	next.call()
