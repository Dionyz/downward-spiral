class_name BoonList
extends RefCounted
## Full-screen list of the run's boons and boon families, with what each family tier gives.


static func open(parent: Control, run: DSRunState) -> void:
	var layer := PanelContainer.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.z_index = 95
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#0d0c11")
	st.set_content_margin_all(16)
	layer.add_theme_stylebox_override("panel", st)
	parent.add_child(layer)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	layer.add_child(v)
	v.add_child(UI.label("Boons", 30, UI.ACCENT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 6)
	scroll.add_child(inner)
	v.add_child(scroll)
	var counts := DSFactory.family_counts(run.data, run.boons)
	inner.add_child(UI.label("Families (distinct boons)", 20, UI.DIM))
	for f in run.data.families.keys():
		var fam: Dictionary = run.data.families[f]
		var n := int(counts.get(f, 0))
		var col := Color(str(fam.get("color", "#e6e1d6")))
		inner.add_child(Tip.attach(UI.tag("ui_family", "%s  %d  — %s" % [str(fam["name"]), n, str(fam.get("desc", ""))], 18, col if n > 0 else UI.DIM), str(fam["name"])))
		for th in ["2", "4", "6"]:
			var on := n >= int(th)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var pad := Control.new()
			pad.custom_minimum_size = Vector2(24, 0)
			row.add_child(pad)
			var ic := UI.icon("ui_check", 16, col)
			ic.modulate = col if on else Color(0, 0, 0, 0)
			row.add_child(ic)
			row.add_child(UI.label("%s: %s" % [th, str(fam["tiers"][th]["text"])], 16, col if on else UI.DIM))
			inner.add_child(row)
	inner.add_child(UI.label("Your boons", 20, UI.DIM))
	if run.boons.is_empty():
		inner.add_child(UI.label("None yet. Level up or kill an elite to pick one.", 17, UI.DIM))
	# One line per boon and rarity, with how many copies.
	var groups := {}
	var order: Array = []
	for bi in run.boons.size():
		var key := "%s|%s" % [run.boons[bi], run.boon_rarity[bi] if bi < run.boon_rarity.size() else "common"]
		if not groups.has(key):
			groups[key] = 0
			order.append(key)
		groups[key] = int(groups[key]) + 1
	for key in order:
		var parts: PackedStringArray = str(key).split("|")
		var id := parts[0]
		var rarity := parts[1]
		var b: Dictionary = run.data.boons.get(id, {})
		var n := int(groups[key])
		var rcol := Color(str(run.data.boon_rarities().get(rarity, {}).get("color", "#d6a64f")))
		inner.add_child(UI.label("%s (%s)%s" % [str(b.get("name", id)), rarity.capitalize(), (" ×%d" % n) if n > 1 else ""], 19, rcol))
		inner.add_child(UI.label(run.boon_desc(id, rarity), 16))
	inner.add_child(Tip.attach(UI.label("Total damage reduction from boons is capped at 90%.", 15, UI.DIM), "damage reduction"))
	v.add_child(UI.button("Close", func(): layer.queue_free(), 56))
