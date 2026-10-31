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
		out.append("+%d damroll" % int(it["damroll"]))
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


## Numbers that matter on an item, as {label: value}, for side-by-side comparison.
static func item_stats(it) -> Dictionary:
	var s := {}
	if it == null:
		return s
	if it.get("slot") == "weapon":
		s["Min damage"] = int(it.get("min", 0))
		s["Max damage"] = int(it.get("max", 0))
	if int(it.get("ac", 0)) != 0:
		s["Armor (AC)"] = -int(it.get("ac", 0))
	if int(it.get("damroll", 0)) != 0:
		s["Damroll"] = int(it.get("damroll", 0))
	if int(it.get("hp", 0)) != 0:
		s["HP"] = int(it.get("hp", 0))
	if int(it.get("mana", 0)) != 0:
		s["Mana"] = int(it.get("mana", 0))
	var sb: Dictionary = it.get("skill_bonus", {})
	for k in sb.keys():
		s[str(k).capitalize()] = int(sb[k])
	return s


## Stat-by-stat comparison of `it` against what's equipped: [{text, color}].
## Green = better than equipped, red = worse, plain = same or new.
static func compare_lines(data: DSData, it: Dictionary, equipped) -> Array:
	var a := item_stats(it)
	var b := item_stats(equipped)
	var keys: Array = a.keys()
	for k in b.keys():
		if not keys.has(k):
			keys.append(k)
	var out: Array = []
	for k in keys:
		var va := int(a.get(k, 0))
		var vb := int(b.get(k, 0))
		var diff := va - vb
		var col := UI.TEXT
		var tail := ""
		if equipped != null and diff != 0:
			col = Color("#5fd35f") if diff > 0 else Color("#ff8c7a")
			tail = "  (%s%d)" % ["+" if diff > 0 else "", diff]
		out.append({"text": "%s %d%s" % [k, va, tail], "color": col})
	for f in it.get("flags", []):
		var had: bool = equipped != null and equipped.get("flags", []).has(f)
		out.append({"text": str(f).capitalize(), "color": UI.TEXT if had else Color("#5fd35f")})
	if equipped != null:
		for f in equipped.get("flags", []):
			if not it.get("flags", []).has(f):
				out.append({"text": "loses %s" % str(f).capitalize(), "color": Color("#ff8c7a")})
	if it.has("passive"):
		var lp: Dictionary = data.items.get("legendary_passives", {}).get(it["passive"], {})
		out.append({"text": "★ %s: %s" % [lp.get("name", it["passive"]), lp.get("desc", "")], "color": Color("#ff9a2e")})
	return out
