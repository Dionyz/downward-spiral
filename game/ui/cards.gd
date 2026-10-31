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
	v.add_child(UI.label(str(b.get("name", id)), 22, UI.ACCENT))
	v.add_child(UI.label("Boon", 16, UI.DIM))
	v.add_child(UI.label(str(b.get("desc", "")), 18))
	v.add_child(UI.button(take_label, on_take, 52))
	return card
