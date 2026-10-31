class_name GridView
extends Control
## Draws a DSWorld: tiles with fog of war, objects, loot on the floor, the stairs, and tokens for
## the player and every monster in view. Tokens glide between tiles each turn; hits flash and
## float numbers; big hits shake the view.

const OBJ_ICON := {"chest": "room_treasure", "shrine": "room_shrine", "campfire": "room_rest", "event": "room_event"}
const OBJ_COLOR := {"chest": "#d6a64f", "shrine": "#9d7cf2", "campfire": "#ff9a2e", "event": "#5f9fd3"}

var world: DSWorld
var run: DSRunState
const TILE := 40.0                # map is bigger than the screen; the camera follows the player
var tile := TILE
var origin := Vector2.ZERO       # always zero inside `content`
var content: Control             # the whole map; moved around as the camera
var tokens := {}                 # combatant name -> {node, icon, bar, color}
var fx_layer: Control
var _move_time := 0.2
var _cam_tween: Tween
var _fading := {}                # tokens on their way out: name -> token


## A live or fading token by name, or {}.
func _tok(nm: String) -> Dictionary:
	return tokens.get(nm, _fading.get(nm, {}))


func _ready() -> void:
	clip_contents = true
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(_relayout)
	content = Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.draw.connect(_draw_map)
	add_child(content)
	fx_layer = Control.new()
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_layer.z_index = 10
	content.add_child(fx_layer)


func setup(p_run: DSRunState) -> void:
	run = p_run
	world = run.world
	for k in tokens.keys():
		tokens[k]["node"].queue_free()
	tokens.clear()
	_relayout()


func _relayout() -> void:
	if world == null or size.x <= 0:
		return
	# Small screens: zoom out a little so the view keeps about 15 tiles across.
	tile = floorf(clampf(size.x / 15.0, 24.0, TILE))
	content.size = Vector2(world.w, world.h) * tile
	sync_tokens(true)
	_camera(true)
	redraw()


func redraw() -> void:
	queue_redraw()
	if content != null:
		content.queue_redraw()


## Keep the player near the middle of the view, without showing far past the map edges.
func _camera(snap: bool) -> void:
	var target := size / 2.0 - cell_center(world.ppos)
	var msize := content.size
	if msize.x <= size.x:
		target.x = (size.x - msize.x) / 2.0
	else:
		target.x = clampf(target.x, size.x - msize.x - tile, tile)
	if msize.y <= size.y:
		target.y = (size.y - msize.y) / 2.0
	else:
		target.y = clampf(target.y, size.y - msize.y - tile, tile)
	target = target.floor()
	if _cam_tween != null and _cam_tween.is_valid():
		_cam_tween.kill()
	if snap:
		content.position = target
	elif content.position != target:
		_cam_tween = create_tween()
		_cam_tween.tween_property(content, "position", target, _move_time)


func cell_center(p: Vector2i) -> Vector2:
	return origin + (Vector2(p) + Vector2(0.5, 0.5)) * tile


# --- tokens ---------------------------------------------------------------

func _make_token(nm: String, icon_name: String, col: Color, ring: Color) -> Dictionary:
	# `node` moves between tiles; `body` (inside it) does the lunges, so the two never fight.
	var node := Control.new()
	node.size = Vector2(tile, tile)
	node.z_index = 3
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var body := Control.new()
	body.size = Vector2(tile, tile)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(body)
	var bg := Panel.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#14121a")
	st.border_color = ring
	st.set_border_width_all(2)
	st.set_corner_radius_all(int(tile / 2))
	bg.add_theme_stylebox_override("panel", st)
	bg.size = Vector2(tile, tile)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(bg)
	var ic := UI.icon(icon_name, int(tile) - 4, col)
	ic.size = Vector2(tile - 4, tile - 4)
	ic.position = Vector2(2, 2)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(ic)
	var bar := ColorRect.new()
	bar.color = Color("#c0392b")
	bar.size = Vector2(tile, 3)
	bar.position = Vector2(0, tile - 1)
	body.add_child(bar)
	content.add_child(node)
	return {"node": node, "body": body, "icon": ic, "bar": bar, "color": col, "target": node.position, "tw": null}


## Create/remove tokens to match who is alive and visible; snap or glide to positions.
func sync_tokens(snap: bool = false) -> void:
	if world == null:
		return
	var want := {}
	var L: Dictionary = run.data.classes.get(run.line, {})
	want[world.player.name] = {"pos": world.ppos, "icon": "class_" + run.line, "col": Color(str(L.get("color", "#d6a64f"))),
		"ring": UI.ACCENT, "c": world.player}
	for m in world.monsters:
		if not m["c"].is_alive() or not world.is_visible(m["pos"]):
			continue
		var col := Color(str(run.data.monsters.get(m["id"], {}).get("color", "#c9c2b6")))
		var ring := Color("#ff5a3d") if m["boss"] else (Color("#ff9a2e") if m["elite"] else Color("#5a5466"))
		if m["state"] == "asleep":
			col = col.darkened(0.45)
		want[m["c"].name] = {"pos": m["pos"], "icon": "mon_" + m["id"], "col": col, "ring": ring, "c": m["c"]}
	for k in tokens.keys():
		if not want.has(k):
			# Fade out (dead or out of sight) but keep it findable for this turn's hit effects.
			var gone: Dictionary = tokens[k]
			tokens.erase(k)
			_fading[k] = gone
			var tw := create_tween()
			tw.tween_property(gone["node"], "modulate:a", 0.0, 0.45).set_delay(0.15)
			tw.tween_callback(func():
				if _fading.get(k) == gone:
					_fading.erase(k)
				gone["node"].queue_free())
	for k in want.keys():
		var wv: Dictionary = want[k]
		if not tokens.has(k) or tokens[k]["node"].size.x != tile:
			if tokens.has(k):
				tokens[k]["node"].queue_free()
			tokens[k] = _make_token(k, wv["icon"], wv["col"], wv["ring"])
			snap = true
		var t: Dictionary = tokens[k]
		t["icon"].modulate = wv["col"]
		t["color"] = wv["col"]
		var c: Combatant = wv["c"]
		t["bar"].size.x = tile * clampf(float(c.hp) / float(maxi(1, c.max_hp)), 0.0, 1.0)
		t["bar"].visible = c.hp < c.max_hp
		var target := cell_center(wv["pos"]) - Vector2(tile, tile) / 2.0
		if t["tw"] != null and t["tw"].is_valid() and t["target"] != target:
			t["tw"].kill()
		if snap or t["node"].position.distance_to(target) > tile * 8.0:
			t["node"].position = target
		elif t["target"] != target or t["node"].position != target:
			# Long moves (charge) glide a little slower so you can follow them.
			var dur := _move_time * clampf(t["node"].position.distance_to(target) / tile, 1.0, 2.0)
			var tw := create_tween()
			tw.tween_property(t["node"], "position", target, dur)
			t["tw"] = tw
		t["target"] = target
	_camera(snap)


func set_move_time(sec: float) -> void:
	_move_time = sec


# --- effects ----------------------------------------------------------------

func flash(nm: String, col: Color) -> void:
	var t := _tok(nm)
	if t.is_empty():
		return
	var ic: TextureRect = t["icon"]
	var base: Color = t["color"]
	var tw := create_tween()
	tw.tween_property(ic, "modulate", col, 0.05)
	tw.tween_property(ic, "modulate", base, 0.2)


func float_text(nm: String, text: String, col: Color, fsize: int = 18) -> void:
	var t := _tok(nm)
	if t.is_empty():
		return
	var l := UI.label(text, fsize, col, false)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	fx_layer.add_child(l)
	l.position = t["target"] + Vector2(tile * 0.1 + randf_range(-6, 6), -tile * 0.4)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - tile * 1.6, 0.8).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


func lunge(src: String, dst: String) -> void:
	var a := _tok(src)
	var b := _tok(dst)
	if a.is_empty() or b.is_empty() or src == dst:
		return
	var body: Control = a["body"]
	var dir: Vector2 = (b["target"] - a["target"])
	if dir.length() > tile * 1.5:
		return   # ranged: no lunge across the room
	dir = dir.normalized() * tile * 0.3
	var tw := create_tween()
	tw.tween_property(body, "position", dir, 0.05)
	tw.tween_property(body, "position", Vector2.ZERO, 0.1)


func shake(amount: float) -> void:
	var tw := create_tween()
	var home := position
	for i in 5:
		tw.tween_property(self, "position", home + Vector2(randf_range(-amount, amount), randf_range(-amount, amount)), 0.03)
	tw.tween_property(self, "position", home, 0.04)


# --- drawing ----------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0b0a0e"))


func _draw_map() -> void:
	if world == null:
		return
	for y in world.h:
		for x in world.w:
			var p := Vector2i(x, y)
			var k := DSWorld.pk(p)
			if not world.seen.has(k):
				continue
			var vis := world.visible.has(k)
			var t := world.tile(p)
			var r := Rect2(origin + Vector2(p) * tile, Vector2(tile, tile))
			var col: Color
			if t == " ":
				col = Color("#3a3446") if vis else Color("#241f2c")
				content.draw_rect(r, col)
				continue
			if t == "#":
				col = Color("#2a2533") if vis else Color("#1a171f")
			else:
				col = Color("#26222e") if vis else Color("#17151c")
			content.draw_rect(r.grow(-0.5), col)
	# Stairs.
	if world.seen.has(DSWorld.pk(world.stairs)):
		var c := cell_center(world.stairs)
		for i in 3:
			var wdt := tile * (0.8 - i * 0.2)
			content.draw_rect(Rect2(Vector2(c.x - wdt / 2.0, c.y - tile * 0.3 + i * tile * 0.25), Vector2(wdt, tile * 0.15)), Color("#8d8798"))
	queue_redraw_objects()


## Objects and floor loot are child icons (rebuilt cheaply each redraw).
var _obj_nodes: Array = []


func queue_redraw_objects() -> void:
	for n in _obj_nodes:
		n.queue_free()
	_obj_nodes.clear()
	for o in world.objects:
		if o["used"] or not world.seen.has(DSWorld.pk(o["pos"])):
			continue
		var ic := UI.icon(OBJ_ICON.get(o["type"], "room_event"), int(tile), Color(OBJ_COLOR.get(o["type"], "#e6e1d6")))
		ic.size = Vector2(tile, tile)
		ic.position = cell_center(o["pos"]) - Vector2(tile, tile) / 2.0
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(ic)
		_obj_nodes.append(ic)
	for it in world.items:
		if not world.seen.has(DSWorld.pk(it["pos"])):
			continue
		var col := Cards.rarity_color(run.data, str(it["item"].get("rarity", "common")))
		var ic2 := UI.icon("item_" + str(it["item"].get("slot", "weapon")), int(tile * 0.7), col)
		ic2.size = Vector2(tile * 0.7, tile * 0.7)
		ic2.position = cell_center(it["pos"]) - ic2.size / 2.0
		ic2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(ic2)
		_obj_nodes.append(ic2)
