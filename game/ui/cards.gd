class_name Cards
extends RefCounted
## Item and boon cards for rewards, treasure and shrines.


static func rarity_color(data: DSData, rarity: String) -> Color:
	return Color(str(data.items.get("rarities", {}).get(rarity, {}).get("color", "#c8c8c8")))


## Short stat lines for an item.
static func item_lines(data: DSData, it: Dictionary) -> Array:
	var out: Array = []
	match it.get("slot", ""):
		"weapon":
			out.append("%s · damage %d-%d" % [str(it.get("type", "")).capitalize(), int(it.get("min", 0)), int(it.get("max", 0))])
		"armor":
			out.append("Armor · AC %d" % int(it.get("ac", 0)))
		"trinket":
			out.append("Trinket")
	if int(it.get("damroll", 0)) != 0:
		out.append("+%d weapon damage" % int(it["damroll"]))
	if int(it.get("hp", 0)) != 0:
		out.append("+%d HP" % int(it["hp"]))
	if int(it.get("mana", 0)) != 0:
		out.append("+%d mana" % int(it["mana"]))
	if it.get("slot") != "armor" and int(it.get("ac", 0)) != 0:
		out.append("AC %d" % int(it["ac"]))
	var sb: Dictionary = it.get("skill_bonus", {})
	for k in sb.keys():
		out.append("+%d %s" % [int(sb[k]), k])
	for f in it.get("flags", []):
		out.append(str(f).capitalize())
	if it.has("passive"):
		var lp: Dictionary = data.items.get("legendary_passives", {}).get(it["passive"], {})
		out.append("★ %s: %s" % [lp.get("name", it["passive"]), lp.get("desc", "")])
	return out


static func item_card(data: DSData, it: Dictionary, equipped, on_take: Callable, take_label: String = "Take") -> PanelContainer:
	var card := PanelContainer.new()
	var v := VBoxContainer.new()
	card.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(UI.icon("item_" + str(it.get("slot", "weapon")), 40, rarity_color(data, str(it.get("rarity", "common")))))
	var nm := UI.label(str(it.get("name", "?")), 22, rarity_color(data, str(it.get("rarity", "common"))))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	var delta := int(it.get("power", DSLoot.power(it))) - (0 if equipped == null else DSLoot.power(equipped))
	var dl := UI.label(("+%d" % delta) if delta >= 0 else str(delta), 20, Color("#5fd35f") if delta >= 0 else Color("#ff8c7a"), false)
	head.add_child(dl)
	v.add_child(head)
	v.add_child(UI.label("%s %s" % [str(it.get("rarity", "")).capitalize(), it.get("slot", "")], 16, UI.DIM))
	v.add_child(UI.label(" · ".join(PackedStringArray(item_lines(data, it))), 18))
	if equipped != null:
		v.add_child(UI.label("Replaces %s" % equipped.get("name", "?"), 16, UI.DIM))
	v.add_child(UI.button(take_label, on_take, 52))
	return card


static func boon_card(data: DSData, id: String, on_take: Callable, take_label: String = "Take") -> PanelContainer:
	var b: Dictionary = data.boons.get(id, {})
	var card := PanelContainer.new()
	var v := VBoxContainer.new()
	card.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(UI.icon("boon", 40, UI.ACCENT))
	var bn := UI.label(str(b.get("name", id)), 22, UI.ACCENT)
	bn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(bn)
	v.add_child(head)
	v.add_child(UI.label("Boon", 16, UI.DIM))
	v.add_child(UI.label(str(b.get("desc", "")), 18))
	v.add_child(UI.button(take_label, on_take, 52))
	return card


## Numbers that matter on an item, in display order: [[short label, value]].
## Weapons lead with average damage (what you actually feel), then the range.
static func item_stats(it) -> Array:
	var s: Array = []
	if it == null:
		return s
	if it.get("slot") == "weapon":
		s.append(["Avg dmg", (int(it.get("min", 0)) + int(it.get("max", 0))) / 2.0])
	if int(it.get("ac", 0)) != 0:
		s.append(["Armor", -int(it.get("ac", 0))])
	if int(it.get("damroll", 0)) != 0:
		s.append(["Weapon damage", int(it.get("damroll", 0))])
	if int(it.get("hp", 0)) != 0:
		s.append(["HP", int(it.get("hp", 0))])
	if int(it.get("mana", 0)) != 0:
		s.append(["Mana", int(it.get("mana", 0))])
	var sb: Dictionary = it.get("skill_bonus", {})
	for k in sb.keys():
		s.append([str(k).capitalize(), int(sb[k])])
	return s


static func _num(v) -> String:
	if typeof(v) == TYPE_FLOAT and v != floorf(v):
		return "%.1f" % v
	return str(int(v))


## Compact stat chips for `it`, compared with what's equipped: [{text, color}].
## Green = better than equipped, red = worse, plain = same (or nothing to compare).
static func compare_lines(data: DSData, it: Dictionary, equipped) -> Array:
	var a := item_stats(it)
	var b := {}
	for e in item_stats(equipped):
		b[e[0]] = e[1]
	var seen := {}
	var out: Array = []
	for e in a:
		var k: String = e[0]
		seen[k] = true
		var va: float = float(e[1])
		var vb: float = float(b.get(k, 0))
		var diff := va - vb
		var col := UI.TEXT
		var tail := ""
		if equipped != null and absf(diff) > 0.01:
			col = Color("#5fd35f") if diff > 0 else Color("#ff8c7a")
			tail = " (%s%s)" % ["+" if diff > 0 else "", _num(diff)]
		var text := "%s %s%s" % [k, _num(e[1]), tail]
		if k == "Weapon damage":
			text = "%s%s weapon damage%s" % ["+" if float(e[1]) >= 0 else "", _num(e[1]), tail]
		if k == "Avg dmg":
			text += "  [%d-%d]" % [int(it.get("min", 0)), int(it.get("max", 0))]
		out.append({"text": text, "color": col})
	for k in b.keys():
		if not seen.has(k):
			out.append({"text": "%s -%s" % [k, _num(b[k])], "color": Color("#ff8c7a")})
	for f in it.get("flags", []):
		var had: bool = equipped != null and equipped.get("flags", []).has(f)
		out.append({"text": str(f).capitalize(), "color": UI.TEXT if had else Color("#5fd35f")})
	if equipped != null:
		for f in equipped.get("flags", []):
			if not it.get("flags", []).has(f):
				out.append({"text": "no %s" % str(f).capitalize(), "color": Color("#ff8c7a")})
	if it.has("passive"):
		var lp: Dictionary = data.items.get("legendary_passives", {}).get(it["passive"], {})
		out.append({"text": "★ %s: %s" % [lp.get("name", it["passive"]), lp.get("desc", "")], "color": Color("#ff9a2e"), "wide": true})
	return out


## Lay stat chips out several per line, wrapping when they don't fit.
static func stat_flow(lines: Array, size: int = 17) -> Control:
	var box := VBoxContainer.new()
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 18)
	flow.add_theme_constant_override("v_separation", 2)
	box.add_child(flow)
	for line in lines:
		if line.get("wide", false):
			box.add_child(UI.label(line["text"], size, line["color"]))
		else:
			flow.add_child(UI.label(line["text"], size, line["color"], false))
	return box


## Compact item card: icon, name, compared stats, and action buttons ([[label, callable, disabled?]]).
static func item_row(data: DSData, it: Dictionary, eq, actions: Array, note: String = "") -> PanelContainer:
	var card := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var col := rarity_color(data, str(it.get("rarity", "common")))
	head.add_child(UI.icon("item_" + str(it.get("slot", "weapon")), 34, col))
	var nm := UI.label(str(it.get("name", "?")), 19, col)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	for a in actions:
		var b := UI.button(str(a[0]), a[1], 44)
		b.add_theme_font_size_override("font_size", 17)
		b.custom_minimum_size.x = 90
		b.disabled = a.size() > 2 and bool(a[2])
		head.add_child(b)
	v.add_child(head)
	var sub := "%s %s · ilvl %d" % [str(it.get("rarity", "")).capitalize(), str(it.get("slot", "")), int(it.get("ilvl", 1))]
	if note != "":
		sub += " · " + note
	if eq != null and DSRunState.is_pure_upgrade(it, eq):
		v.add_child(UI.label(sub + "  ·  ▲ UPGRADE", 14, Color("#5fd35f")))
	else:
		v.add_child(UI.label(sub, 14, UI.DIM))
	v.add_child(stat_flow(compare_lines(data, it, eq), 16))
	return card
