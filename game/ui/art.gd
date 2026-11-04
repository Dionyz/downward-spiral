class_name Art
extends RefCounted
## Pixel art lookup. Every picture the game draws lives in game/assets/art/ under a fixed name
## (see game/assets/art/ART_SPEC.md); replacing a file there replaces it in game. Anything
## missing falls back to the old vector icon, so a half-finished art set still runs.
## Pixel art is drawn with nearest-neighbor filtering and is never tinted, except the white UI
## glyphs and family badges in ui/ (TINTABLE), which the caller colors like the old SVG icons.

const ROOT := "res://game/assets/art/%s.png"

static var _cache := {}
static var _variants := {}
static var _frames := {}
static var _nine := {}

## White glyphs in ui/ that take the caller's color (see ART_SPEC.md, UI).
const GLYPHS := ["ui_up", "ui_down", "ui_check", "ui_grip", "ui_upgrade", "ui_star", "ui_family", "boon", "town_trophy"]

## Statuses with an icon, in the order they are shown (most important first).
const STATUSES := ["stunned", "knocked_down", "asleep", "frozen", "transfixed", "dazed", "blind", "slowed",
	"poisoned", "bleeding", "berserk", "haste", "sanctuary", "shield", "armor", "warcry", "envenomed"]

## Old icon names (game/assets/icons/*.svg) -> art ids.
const ICON_MAP := {
	"room_treasure": "objects/chest", "room_shrine": "objects/shrine", "room_rest": "objects/campfire",
	"room_event": "objects/event", "potion": "items/potion_hp", "town_coins": "items/gold",
	"town_stash": "town/stash", "town_shop": "town/shop", "town_trainer": "town/trainer",
	"town_inn": "town/inn", "town_gate": "town/gate",
	"item_weapon": "items/weapon_sword", "item_armor": "items/armor_jerkin", "item_trinket": "items/trinket_amulet",
}


static func tex(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var path := ROOT % id
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[id] = t
	return t


static func has(id: String) -> bool:
	return tex(id) != null


## Art id for an old icon name, or "" when there is no pixel art for it.
static func for_icon(name: String) -> String:
	var id := ""
	if ICON_MAP.has(name):
		id = ICON_MAP[name]
	elif name.begins_with("mon_"):
		id = "monsters/" + name.substr(4)
	elif name.begins_with("class_"):
		id = "player/%s_human" % name.substr(6)
	elif name in GLYPHS or name.begins_with("family_"):
		id = "ui/" + name
	return id if id != "" and has(id) else ""


## True for the white glyphs the game tints (ui/<glyph>, ui/family_<id>).
static func tintable(id: String) -> bool:
	return id.begins_with("ui/") and (id.substr(3) in GLYPHS or id.begins_with("ui/family_"))


static func boon(id: String) -> String:
	var a := "boons/" + id
	return a if has(a) else ""


static func skill(name: String) -> String:
	var a := "skills/" + name.replace(" ", "_")
	return a if has(a) else ""


static func status(name: String) -> String:
	var a := "status/" + name
	return a if has(a) else ""


## Frames of a hit effect (fx/<name>_0.png, _1, ...), empty when there is no art.
static func frames(name: String) -> Array:
	if _frames.has(name):
		return _frames[name]
	var out: Array = []
	for i in 8:
		var t := tex("fx/%s_%d" % [name, i])
		if t == null:
			break
		out.append(t)
	_frames[name] = out
	return out


## A 9-patch StyleBoxTexture from ui/<name>.png, drawn at x2 (one art pixel = two screen pixels),
## or null when the file is missing. `margin` is in art pixels (see ART_SPEC.md).
## A new StyleBox each call (callers set their own content margins); the scaled texture is cached.
static func nine(id: String, margin: int, content: int = -1) -> StyleBoxTexture:
	if not _nine.has(id):
		var t := tex(id)
		var big: Texture2D = null
		if t != null:
			var img := t.get_image()
			if img != null:
				if img.is_compressed():
					img.decompress()
				img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
				big = ImageTexture.create_from_image(img)
		_nine[id] = big
	if _nine[id] == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = _nine[id]
	sb.set_texture_margin_all(margin * 2)
	if content >= 0:
		sb.set_content_margin_all(content)
	return sb


static func player(line: String, race: String = "human") -> String:
	var id := "player/%s_%s" % [line, race]
	return id if has(id) else "player/%s_human" % line


## Art id for an item: weapons by type, armor and trinkets by base name, else by slot.
static func item(data: DSData, it: Dictionary) -> String:
	var slot := str(it.get("slot", "weapon"))
	var id := ""
	if slot == "weapon" and it.has("type"):
		id = "items/weapon_" + str(it["type"])
	else:
		var base := str(it.get("base", ""))
		if base == "":
			var names: Array = data.items.get(slot, {}).get("names", []) if slot in ["armor", "trinket"] else []
			var nm := str(it.get("name", ""))
			for n in names:
				if nm.contains(str(n)):
					base = str(n)
		if base != "":
			id = "items/%s_%s" % [slot, base.to_lower().replace(" ", "_")]
	if id == "" or not has(id):
		id = ICON_MAP.get("item_" + slot, "")
	return id


## A pixel-art TextureRect (no tint) sized `size`.
static func rect(id: String, size: int) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex(id)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	return t


## Item picture in a frame colored by rarity.
static func item_icon(data: DSData, it: Dictionary, size: int) -> Control:
	var col := Cards.rarity_color(data, str(it.get("rarity", "common")))
	var id := item(data, it)
	return framed(id, size, col, func(px): return UI.icon("item_" + str(it.get("slot", "weapon")), px, col))


## Boon icon in a frame colored by its rarity (`col`); the old tinted badge when there's no art.
static func boon_icon(id: String, size: int, col: Color) -> Control:
	return framed(boon(id), size, col, func(px): return UI.icon("boon", px, col))


## `id`'s picture inside a rarity-colored frame `size` px square; `fallback(px)` builds the
## inner control when there is no art.
static func framed(id: String, size: int, col: Color, fallback: Callable) -> Control:
	var frame := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(col, 0.12)
	st.border_color = col
	st.set_border_width_all(2)
	st.set_corner_radius_all(0)
	frame.add_theme_stylebox_override("panel", st)
	frame.custom_minimum_size = Vector2(size, size)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Whole multiples of 32 px keep the pixels even.
	var px := size - 6 if size - 6 < 32 else int(floorf((size - 6) / 32.0) * 32.0)
	var inner: Control = rect(id, px) if id != "" else fallback.call(px)
	inner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(inner)
	return frame


## Map tile textures for a theme and kind (floor / corridor / wall), all variants.
static func tiles(theme: String, kind: String) -> Array:
	var key := theme + "/" + kind
	if _variants.has(key):
		return _variants[key]
	var out: Array = []
	for i in 16:
		var t := tex("tiles/%s/%s_%d" % [theme, kind, i])
		if t == null:
			break
		out.append(t)
	if out.is_empty() and theme != "spiral":
		out = tiles("spiral", kind)
	_variants[key] = out
	return out
