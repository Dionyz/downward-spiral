class_name MapView
extends Control
## The floor drawn as a dungeon map: rooms joined by corridors on a stone-grid background,
## the entrance stair at the top, the way down at the bottom, and the player's token walking
## from room to room. Forks show as two rooms side by side; tap one to choose it.

signal room_tapped(choice: int)

const TYPE_COLOR := {"fight": "#c9c2b6", "elite": "#ff9a2e", "boss": "#ff5a3d", "treasure": "#d6a64f",
	"shrine": "#9d7cf2", "rest": "#5fd35f", "event": "#5f9fd3"}
const ROOM := 64.0              # room tile size (px)
const WALK_TIME := 0.7          # seconds per corridor

var run: DSRunState
var token: Control
var token_icon: TextureRect
var _icons: Array = []          # TextureRects per room, rebuilt on layout
var _buttons: Array = []
var _walking := false
var _bob := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(0, 470)
	clip_contents = true
	resized.connect(_layout)
	token = Control.new()
	token.custom_minimum_size = Vector2(52, 52)
	token.size = Vector2(52, 52)
	token.z_index = 5
	add_child(token)
	var ring := Panel.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#14121a")
	st.border_color = UI.ACCENT
	st.set_border_width_all(3)
	st.set_corner_radius_all(26)
	ring.add_theme_stylebox_override("panel", st)
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	token.add_child(ring)
	token_icon = UI.icon("class_knifer", 40, UI.ACCENT)
	token_icon.position = Vector2(6, 6)
	token.add_child(token_icon)


func setup(p_run: DSRunState) -> void:
	run = p_run
	var L: Dictionary = run.data.classes.get(run.line, {})
	var path := "res://game/assets/icons/class_%s.svg" % run.line
	if ResourceLoader.exists(path):
		token_icon.texture = load(path)
	token_icon.modulate = Color(str(L.get("color", "#d6a64f")))
	_layout()


# --- geometry -------------------------------------------------------------

func _steps() -> Array:
	return run.steps() if run != null else []


## Centre of room `j` in step `i`. Steps wind down the map; fork rooms sit side by side.
func room_pos(i: int, j: int = 0) -> Vector2:
	var n := maxi(1, _steps().size())
	var top := 70.0
	var bottom := size.y - 70.0
	var y := top + (bottom - top) * (float(i) + 0.5) / float(n)
	var cx := size.x * 0.5 + sin(float(i) * 1.7 + float(run.floor_num)) * size.x * 0.22
	var opts: int = _steps()[i].size() if i < _steps().size() else 1
	if opts > 1:
		cx = size.x * 0.5 + (float(j) - 0.5) * size.x * 0.42
	return Vector2(cx, y)


func entrance_pos() -> Vector2:
	return Vector2(size.x * 0.5, 30.0)


func exit_pos() -> Vector2:
	return Vector2(size.x * 0.5, size.y - 30.0)


## Where the token stands for the run's current state.
func token_home() -> Vector2:
	if run == null:
		return entrance_pos()
	match run.phase:
		"room", "reward":
			return room_pos(run.step, int(run.room.get("chosen", 0)))
		"floor_end", "over":
			return exit_pos()
	if run.step == 0:
		return entrance_pos()
	return room_pos(run.step - 1, _chosen(run.step - 1))


func _chosen(i: int) -> int:
	var taken: Array = run.floor_data.get("taken", [])
	return int(taken[i]) if i < taken.size() else 0


# --- building -------------------------------------------------------------

func _layout() -> void:
	if run == null or size.x <= 0:
		return
	for c in _icons:
		c.queue_free()
	for b in _buttons:
		b.queue_free()
	_icons.clear()
	_buttons.clear()
	var steps := _steps()
	for i in steps.size():
		for j in steps[i].size():
			var rm: Dictionary = steps[i][j]
			var t: String = rm.get("type", "fight")
			var ic := UI.icon("room_" + t, 40, Color(TYPE_COLOR.get(t, "#c9c2b6")))
			ic.size = Vector2(40, 40)
			ic.position = room_pos(i, j) - Vector2(20, 20)
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(ic)
			_icons.append(ic)
			if _state(i, j) == "past_other" or _state(i, j) == "past":
				ic.modulate.a = 0.35
			# Fork rooms are tappable while you stand before them.
			if steps[i].size() > 1 and i == run.step and run.phase == "path":
				var b := Button.new()
				b.flat = true
				b.size = Vector2(ROOM + 16, ROOM + 16)
				b.position = room_pos(i, j) - b.size / 2.0
				var jj: int = j
				b.pressed.connect(func(): room_tapped.emit(jj))
				add_child(b)
				_buttons.append(b)
	if not _walking:
		token.position = token_home() - token.size / 2.0
	queue_redraw()


func _state(i: int, j: int) -> String:
	if i < run.step or (run.phase in ["floor_end", "over"]):
		return "past" if j == _chosen(i) else "past_other"
	if i == run.step and run.phase in ["room", "reward"]:
		return "here" if j == int(run.room.get("chosen", 0)) else "past_other"
	if i == run.step:
		return "next"
	return "ahead"


func _draw() -> void:
	if run == null:
		return
	# Stone floor: faint tile grid.
	draw_rect(Rect2(Vector2.ZERO, size), Color("#121017"))
	var tile := 32.0
	var grid := Color(1, 1, 1, 0.035)
	var x := 0.0
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), grid, 1.0)
		x += tile
	var y := 0.0
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), grid, 1.0)
		y += tile
	var steps := _steps()
	# Corridors: entrance -> first step -> ... -> last step -> exit.
	var prev: Array = [entrance_pos()]
	var prev_idx := -1
	for i in steps.size():
		var cur: Array = []
		for j in steps[i].size():
			cur.append(room_pos(i, j))
		for a in prev.size():
			for b in cur.size():
				var walked := i < run.step or (i == run.step and run.phase in ["room", "reward"]) or run.phase in ["floor_end", "over"]
				walked = walked and (prev_idx < 0 or a == _chosen(prev_idx)) and (b == (int(run.room.get("chosen", 0)) if i == run.step and run.phase in ["room", "reward"] else _chosen(i)))
				_corridor(prev[a], cur[b], walked)
		prev = cur
		prev_idx = i
	for a in prev.size():
		_corridor(prev[a], exit_pos(), run.phase in ["floor_end", "over"] and (prev_idx < 0 or a == _chosen(prev_idx)))
	# Stairs.
	_stairs(entrance_pos(), "up")
	_stairs(exit_pos(), "down")
	# Rooms.
	for i in steps.size():
		for j in steps[i].size():
			var t: String = steps[i][j].get("type", "fight")
			var c := Color(TYPE_COLOR.get(t, "#c9c2b6"))
			var p := room_pos(i, j)
			var r := Rect2(p - Vector2(ROOM, ROOM) / 2.0, Vector2(ROOM, ROOM))
			var st := _state(i, j)
			var fill := Color("#1d1a24")
			var border := c.darkened(0.35)
			var width := 2.0
			match st:
				"past":
					fill = Color("#191620")
					border = c.darkened(0.6)
				"past_other":
					fill = Color("#141218")
					border = Color(0.3, 0.3, 0.3, 0.4)
				"here":
					border = c
					width = 4.0
				"next":
					border = c.lightened(0.1)
					width = 3.0
			draw_rect(r, fill)
			draw_rect(r, border, false, width)


func _corridor(a: Vector2, b: Vector2, walked: bool) -> void:
	var col := Color("#3a3446") if not walked else Color("#6b5a3a")
	draw_line(a, b, Color("#0b0a0e"), 16.0)
	draw_line(a, b, col, 10.0)
	if walked:
		# Footprints along the walked path.
		var d := a.distance_to(b)
		var n := int(d / 18.0)
		for k in range(1, n):
			var p := a.lerp(b, float(k) / float(n))
			draw_circle(p, 2.0, Color("#d6a64f", 0.35))


func _stairs(p: Vector2, kind: String) -> void:
	var w := 46.0
	for k in 4:
		var yy := p.y - 12.0 + float(k) * 7.0
		var inset := float(k) * 5.0 if kind == "down" else float(3 - k) * 5.0
		draw_rect(Rect2(Vector2(p.x - w / 2.0 + inset, yy), Vector2(w - inset * 2.0, 5.0)), Color("#4a4458"))


# --- movement -------------------------------------------------------------

## Walk the token to the room at step `i`, choice `j` (or to the exit if i == -1), then call `done`.
func walk_to(i: int, j: int, done: Callable) -> void:
	var target := exit_pos() if i < 0 else room_pos(i, j)
	_walking = true
	var from := token.position + token.size / 2.0
	var dur := WALK_TIME * clampf(from.distance_to(target) / 120.0, 0.6, 1.4) / maxf(1.0, Game.speed * 0.5)
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var pos := from.lerp(target, t)
		pos.y -= absf(sin(t * PI * 4.0)) * 6.0   # a little step bob
		token.position = pos - token.size / 2.0
	, 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		_walking = false
		if done.is_valid():
			done.call()
	)


func _process(delta: float) -> void:
	if _walking or run == null:
		return
	# Idle breathing on the token.
	_bob += delta * 3.0
	token.position = token_home() - token.size / 2.0 + Vector2(0, sin(_bob) * 2.0)
