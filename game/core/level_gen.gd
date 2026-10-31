class_name DSLevelGen
extends RefCounted
## Rogue-style floor generator. Seeded, pure logic.
##
## The floor is a W x H tile grid split into a 3x3 grid of cells. Most cells hold a room of
## random size; a few hold only a corridor junction. Neighbouring cells are joined by
## L-shaped corridors along a random spanning tree plus a couple of extra links (loops).
## The player starts in one room; the stairs down go in the room farthest away.
##
## Result: {w, h, tiles: Array[String] (one row each), rooms: [{x,y,w,h}], start: [x,y],
##          stairs: [x,y], objects: [{type, x, y}], spawns: [{id, x, y, elite?, boss?}]}
## Tile chars: ' ' rock, '.' room floor, '#' corridor.

const W := 32
const H := 38
const COLS := 3
const ROWS := 3

const ROCK := " "
const FLOOR := "."
const CORRIDOR := "#"


static func generate(data: DSData, rng: DSRng, floor_num: int) -> Dictionary:
	var grid: Array = []
	for y in H:
		var row: Array = []
		row.resize(W)
		row.fill(ROCK)
		grid.append(row)
	var cw := W / COLS
	var ch := H / ROWS
	# Rooms (or junction points) per cell.
	var cells: Array = []
	var gone := {}
	var n_gone := rng.number_range(0, 2)
	for i in n_gone:
		gone[rng.number_range(0, COLS * ROWS - 1)] = true
	for cy in ROWS:
		for cx in COLS:
			var idx := cy * COLS + cx
			var x0 := cx * cw
			var y0 := cy * ch
			if gone.has(idx):
				var px := x0 + rng.number_range(2, cw - 3)
				var py := y0 + rng.number_range(2, ch - 3)
				grid[py][px] = CORRIDOR
				cells.append({"x": px, "y": py, "w": 1, "h": 1, "room": false})
			else:
				var rw := rng.number_range(4, cw - 3)
				var rh := rng.number_range(4, ch - 3)
				var rx := x0 + rng.number_range(1, cw - rw - 1)
				var ry := y0 + rng.number_range(1, ch - rh - 1)
				for y in range(ry, ry + rh):
					for x in range(rx, rx + rw):
						grid[y][x] = FLOOR
				cells.append({"x": rx, "y": ry, "w": rw, "h": rh, "room": true})
	# Spanning tree over the 3x3 cell grid (random DFS), then extra links for loops.
	var links := {}
	var visited := {0: true}
	var stack: Array = [0]
	while not stack.is_empty():
		var cur: int = stack[stack.size() - 1]
		var nbrs: Array = []
		for n in _neighbours(cur):
			if not visited.has(n):
				nbrs.append(n)
		if nbrs.is_empty():
			stack.pop_back()
			continue
		var nxt: int = rng.pick(nbrs)
		visited[nxt] = true
		links[_key(cur, nxt)] = [cur, nxt]
		stack.append(nxt)
	for i in rng.number_range(1, 3):
		var a := rng.number_range(0, COLS * ROWS - 1)
		var nb: Array = _neighbours(a)
		var b: int = rng.pick(nb)
		links[_key(a, b)] = [a, b]
	var keys := links.keys()
	keys.sort()
	for k in keys:
		var pair: Array = links[k]
		_corridor(grid, rng, _center(cells[pair[0]]), _center(cells[pair[1]]))
	# Start and stairs.
	var room_ids: Array = []
	for i in cells.size():
		if cells[i]["room"]:
			room_ids.append(i)
	var start_room: int = rng.pick(room_ids)
	var start := _center(cells[start_room])
	var dist := _bfs(grid, start)
	var stairs_room := start_room
	var best := -1
	for i in room_ids:
		var c := _center(cells[i])
		var d := int(dist.get(_pk(c), -1))
		if d > best:
			best = d
			stairs_room = i
	var stairs := _random_floor(rng, cells[stairs_room], {})
	var used := {_pk(start): true, _pk(stairs): true}
	# Objects (chests, shrines, campfires, events) in rooms other than the start room.
	var objects: Array = []
	var cfg: Dictionary = data.balance.get("level", {})
	var others: Array = room_ids.filter(func(i): return i != start_room)
	var plan: Array = []
	for i in rng.number_range(int(cfg.get("chests_min", 1)), int(cfg.get("chests_max", 2))):
		plan.append("chest")
	if rng.number_percent() <= int(cfg.get("shrine_pct", 50)):
		plan.append("shrine")
	if rng.number_percent() <= int(cfg.get("campfire_pct", 60)):
		plan.append("campfire")
	if rng.number_percent() <= int(cfg.get("event_pct", 60)):
		plan.append("event")
	for t in plan:
		var room: Dictionary = cells[rng.pick(others)]
		var p := _random_floor(rng, room, used)
		used[_pk(p)] = true
		objects.append({"type": t, "x": p.x, "y": p.y})
	# Monsters.
	var spawns: Array = []
	var lvl_floor := floor_num
	var count := int(cfg.get("monsters_base", 4)) + int(float(cfg.get("monsters_per_floor", 1.5)) * floor_num) + rng.number_range(0, 2)
	var pool := DSEncounters.pool(data, lvl_floor, "normal")
	for i in count:
		var room: Dictionary = cells[rng.pick(others)]
		var p := _random_floor(rng, room, used)
		used[_pk(p)] = true
		spawns.append({"id": rng.pick(pool), "x": p.x, "y": p.y})
	var spec: Array = DSDungeonGen.FLOORS.get(floor_num, [3, 3, "fight"])
	if spec[2] == "elite":
		var ep := DSEncounters.pool(data, floor_num, "elite")
		var room: Dictionary = cells[rng.pick(others)]
		var p := _random_floor(rng, room, used)
		used[_pk(p)] = true
		spawns.append({"id": rng.pick(ep), "x": p.x, "y": p.y, "elite": true})
	if spec[2] == "boss":
		var bp := DSEncounters.pool(data, floor_num, "boss")
		var p := _random_floor(rng, cells[stairs_room], used)
		used[_pk(p)] = true
		spawns.append({"id": rng.pick(bp), "x": p.x, "y": p.y, "boss": true})
	var rows: Array = []
	for y in H:
		rows.append("".join(PackedStringArray(grid[y])))
	var rooms: Array = []
	for i in room_ids:
		rooms.append({"x": cells[i]["x"], "y": cells[i]["y"], "w": cells[i]["w"], "h": cells[i]["h"]})
	return {"w": W, "h": H, "tiles": rows, "rooms": rooms, "start": [start.x, start.y],
		"stairs": [stairs.x, stairs.y], "objects": objects, "spawns": spawns, "floor": floor_num}


static func _neighbours(i: int) -> Array:
	var out: Array = []
	var cx := i % COLS
	var cy := i / COLS
	if cx > 0:
		out.append(i - 1)
	if cx < COLS - 1:
		out.append(i + 1)
	if cy > 0:
		out.append(i - COLS)
	if cy < ROWS - 1:
		out.append(i + COLS)
	return out


static func _key(a: int, b: int) -> String:
	return "%d-%d" % [mini(a, b), maxi(a, b)]


static func _center(c: Dictionary) -> Vector2i:
	return Vector2i(int(c["x"]) + int(c["w"]) / 2, int(c["y"]) + int(c["h"]) / 2)


static func _pk(p: Vector2i) -> String:
	return "%d,%d" % [p.x, p.y]


## L-shaped corridor: horizontal then vertical or the reverse. Room floor stays room floor.
static func _corridor(grid: Array, rng: DSRng, a: Vector2i, b: Vector2i) -> void:
	var horizontal_first := rng.number_percent() <= 50
	var corner := Vector2i(b.x, a.y) if horizontal_first else Vector2i(a.x, b.y)
	for seg in [[a, corner], [corner, b]]:
		var p: Vector2i = seg[0]
		var q: Vector2i = seg[1]
		var step := Vector2i(signi(q.x - p.x), signi(q.y - p.y))
		while true:
			if grid[p.y][p.x] == ROCK:
				grid[p.y][p.x] = CORRIDOR
			if p == q:
				break
			p += step


static func _random_floor(rng: DSRng, room: Dictionary, used: Dictionary) -> Vector2i:
	for t in 40:
		var p := Vector2i(rng.number_range(int(room["x"]), int(room["x"]) + int(room["w"]) - 1),
			rng.number_range(int(room["y"]), int(room["y"]) + int(room["h"]) - 1))
		if not used.has(_pk(p)):
			return p
	return _center(room)


## Walkable tiles reachable from `from`, with distances: {"x,y": steps}.
static func _bfs(grid: Array, from: Vector2i) -> Dictionary:
	var dist := {_pk(from): 0}
	var q: Array = [from]
	var head := 0
	while head < q.size():
		var p: Vector2i = q[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = p + d
			if n.x < 0 or n.y < 0 or n.x >= W or n.y >= H:
				continue
			if grid[n.y][n.x] == ROCK or dist.has(_pk(n)):
				continue
			dist[_pk(n)] = int(dist[_pk(p)]) + 1
			q.append(n)
	return dist


## Every walkable tile reachable from the start? (tests)
static func fully_connected(level: Dictionary) -> bool:
	var grid: Array = []
	for row in level["tiles"]:
		var chars: Array = []
		var rs := str(row)
		for i in rs.length():
			chars.append(rs.substr(i, 1))
		grid.append(chars)
	var s: Array = level["start"]
	var dist := _bfs(grid, Vector2i(int(s[0]), int(s[1])))
	for y in H:
		for x in W:
			if grid[y][x] != ROCK and not dist.has("%d,%d" % [x, y]):
				return false
	return true
