class_name UI
extends RefCounted
## Shared look and small widget builders for the text prototype. Portrait, thumb-sized controls.

const BG := Color("#0e0d12")
const PANEL := Color("#1a1822")
const TEXT := Color("#e6e1d6")
const DIM := Color("#8d8798")
const ACCENT := Color("#d6a64f")
const HP := Color("#c0392b")
const MANA := Color("#2e6fd1")
const ENEMY_HP := Color("#8e3b2f")
const WARN := Color("#ff7a3d")

static var _theme: Theme
static var _heading: Font
static var _body: Font

const HEADING_FONT := "res://game/assets/art/fonts/jersey10.ttf"
const BODY_FONT := "res://game/assets/art/fonts/pixelify_sans.ttf"   # buttons
## Labels this size or bigger are headings and use the heading font.
const HEADING_SIZE := 26


static func _font(path: String) -> Font:
	if not ResourceLoader.exists(path):
		return null
	var f: FontFile = load(path)
	if f != null:
		# Pixel fonts: no subpixel positioning, snap glyphs to whole pixels.
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		f.hinting = TextServer.HINTING_NONE
	return f


static func heading_font() -> Font:
	if _heading == null:
		_heading = _font(HEADING_FONT)
	return _heading


## 9-patch skin from game/assets/art/ui (margins in ART_SPEC.md), else the old flat box.
static func skin(name: String, fallback: StyleBox, content := -1) -> StyleBox:
	var margins := {"panel": 4, "popup": 4, "chip": 3, "button": 4, "button_hover": 4, "button_pressed": 4, "button_disabled": 4,
		"bar_bg": 2, "bar_hp": 2, "bar_mana": 2, "bar_xp": 2, "bar_enemy": 2, "bar_shield": 2}
	var sb := Art.nine("ui/" + name, int(margins.get(name, 4)), content)
	if sb == null:
		return fallback
	if content < 0 and fallback != null:
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			sb.set_content_margin(side, fallback.get_content_margin(side))
	return sb


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 24
	# Pixelify Sans on buttons only (20 px and up, see button()): smaller it blurs, its "8" reads
	# as "S" and its "fl" ligature as "A", so labels keep the default font. Headings: see label().
	_body = _font(BODY_FONT)
	if _body != null:
		_body.opentype_feature_overrides = {"liga": 0, "clig": 0}
		for k in ["Button", "OptionButton"]:
			t.set_font("font", k, _body)
	var flat := StyleBoxFlat.new()
	flat.bg_color = PANEL
	flat.set_corner_radius_all(10)
	flat.set_content_margin_all(14)
	var hover := flat.duplicate()
	hover.bg_color = Color("#2a2634")
	var pressed := flat.duplicate()
	pressed.bg_color = Color("#3a3446")
	var disabled := flat.duplicate()
	disabled.bg_color = Color("#141218")
	var panel: StyleBox = skin("panel", flat.duplicate())
	var normal: StyleBox = skin("button", flat)
	var hov: StyleBox = skin("button_hover", hover)
	var prs: StyleBox = skin("button_pressed", pressed)
	var dis: StyleBox = skin("button_disabled", disabled)
	for sb in [normal, hov, prs, dis]:
		if sb is StyleBoxTexture:
			# Less padding above and below so a 32 px icon fits a 44 px button.
			sb.content_margin_top = 6
			sb.content_margin_bottom = 6
	for k in ["normal", "focus"]:
		t.set_stylebox(k, "Button", normal)
	t.set_stylebox("hover", "Button", hov)
	t.set_stylebox("pressed", "Button", prs)
	t.set_stylebox("disabled", "Button", dis)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("normal", "OptionButton", normal)
	t.set_stylebox("hover", "OptionButton", hov)
	t.set_stylebox("pressed", "OptionButton", prs)
	t.set_stylebox("focus", "OptionButton", normal)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "PopupMenu", panel)
	_theme = t
	return t


## Full-screen root: dark background + margin + vertical stack. Returns the VBox to fill.
static func screen(root: Control) -> VBoxContainer:
	root.theme = theme()
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # pixel art everywhere below
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 16)
	m.add_theme_constant_override("margin_top", 28)
	m.add_theme_constant_override("margin_bottom", 20)
	root.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)
	return v


static func label(text: String, size: int = 24, color: Color = TEXT, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if size >= HEADING_SIZE and heading_font() != null:
		l.add_theme_font_override("font", heading_font())
		# The heading face is condensed: a little larger reads the same size.
		l.add_theme_font_size_override("font_size", int(size * 1.15))
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, cb: Callable, min_h: int = 64) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.pressed.connect(func(): Game.sfx("click"))
	b.pressed.connect(cb)
	# Small button text (callers shrink it after this) reads better in the plain font.
	b.ready.connect(func():
		if b.get_theme_font_size("font_size") < 20:
			b.add_theme_font_override("font", ThemeDB.fallback_font))
	return b


## Tinted icon from game/assets/icons (white SVG silhouettes).
## Pixel art (game/assets/art) is used instead when there is some for `name`; it is never tinted,
## except the white UI glyphs (Art.tintable), which take `color` like the SVGs did.
static func icon(name: String, size: int = 64, color: Color = TEXT) -> TextureRect:
	var art := Art.for_icon(name)
	if art != "":
		# Pixel art scales by whole or half multiples of 32 px: snap to 16 px steps.
		var r := Art.rect(art, maxi(16, int(roundf(size / 16.0)) * 16))
		if Art.tintable(art):
			r.modulate = color
		return r
	if name.begins_with("family_"):
		name = "ui_family"
	var t := TextureRect.new()
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # vector fallback: keep it smooth
	var path := "res://game/assets/icons/%s.svg" % name
	if ResourceLoader.exists(path):
		t.texture = load(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	t.modulate = color
	return t


static func bar(color: Color, h: int = 22) -> ProgressBar:
	var p := ProgressBar.new()
	p.custom_minimum_size = Vector2(0, h)
	p.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(5)
	var back := StyleBoxFlat.new()
	back.bg_color = Color("#2b2733")
	back.set_corner_radius_all(5)
	var kind: String = {HP: "bar_hp", MANA: "bar_mana", ENEMY_HP: "bar_enemy", ACCENT: "bar_xp"}.get(color, "")
	p.add_theme_stylebox_override("fill", skin(kind, fill, 0) if kind != "" else fill)
	p.add_theme_stylebox_override("background", skin("bar_bg", back, 0))
	return p


## Style for small readout chips (9-patch art, else a flat rounded box).
static func chip_style() -> StyleBox:
	var cst := StyleBoxFlat.new()
	cst.bg_color = Color("#16141c")
	cst.set_corner_radius_all(8)
	cst.content_margin_left = 8
	cst.content_margin_right = 8
	cst.content_margin_top = 3
	cst.content_margin_bottom = 3
	return skin("chip", cst)


## Style for popups and cards drawn outside the theme (9-patch panel, else `fallback`).
static func panel_style(fallback: StyleBoxFlat) -> StyleBox:
	return skin("panel", fallback)


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Modal yes/no card over `parent`. `on_yes` runs if confirmed.
static func confirm(parent: Control, text: String, yes_label: String, on_yes: Callable, no_label: String = "Cancel") -> void:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.z_index = 120
	parent.add_child(layer)
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
	v.add_child(label(text, 22))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var no := button(no_label, func(): layer.queue_free(), 56)
	var yes := button(yes_label, func():
		layer.queue_free()
		on_yes.call(), 56)
	yes.add_theme_color_override("font_color", ACCENT)
	for b in [no, yes]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	v.add_child(row)


static func tex(name: String) -> Texture2D:
	var art := Art.for_icon(name)
	if art != "":
		return Art.tex(art)
	var path := "res://game/assets/icons/%s.svg" % name
	return load(path) if ResourceLoader.exists(path) else null


## A button showing an icon (and optional text). The icon takes `color`.
static func icon_button(icon_name: String, cb: Callable, min_h: int = 48, text: String = "", color: Color = TEXT) -> Button:
	var b := button(text, cb, min_h)
	b.icon = tex(icon_name)
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.expand_icon = true
	var w := int(min_h * 0.6)
	if Art.for_icon(icon_name) != "":
		w = 32 if w >= 24 else 16   # pixel glyphs: whole or half multiples of 32 px
	b.add_theme_constant_override("icon_max_width", w)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER if text == "" else HORIZONTAL_ALIGNMENT_LEFT
	for k in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		b.add_theme_color_override(k, color)
	b.add_theme_color_override("icon_disabled_color", Color(color, 0.3))
	return b


## Small icon + text on one line.
static func tag(icon_name: String, text: String, size: int = 16, color: Color = TEXT) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := icon(icon_name, size + 2, color)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var l := label(text, size, color, false)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	return h
