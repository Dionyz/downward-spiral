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


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 24
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
	for k in ["normal", "focus"]:
		t.set_stylebox(k, "Button", flat)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("normal", "OptionButton", flat)
	t.set_stylebox("hover", "OptionButton", hover)
	t.set_stylebox("pressed", "OptionButton", pressed)
	t.set_stylebox("focus", "OptionButton", flat)
	var panel := flat.duplicate()
	t.set_stylebox("panel", "PanelContainer", panel)
	_theme = t
	return t


## Full-screen root: dark background + margin + vertical stack. Returns the VBox to fill.
static func screen(root: Control) -> VBoxContainer:
	root.theme = theme()
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


static func label(text: String, size: int = 24, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, cb: Callable, min_h: int = 64) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.pressed.connect(cb)
	return b


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
	p.add_theme_stylebox_override("fill", fill)
	p.add_theme_stylebox_override("background", back)
	return p


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c
