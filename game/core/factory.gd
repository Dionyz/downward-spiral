class_name DSFactory
extends RefCounted
## Builds Combatants from data. Pure logic.


## Player for class `line` at `tier` and in-run `level`.
## opts: weapon, offhand, armor (item dicts), actives (Array), rules (Array), bonuses {skill: +pct}
static func make_player(data: DSData, line: String, tier: int, level: int, opts: Dictionary = {}) -> Combatant:
	var b := data.balance
	var L: Dictionary = data.classes.get(line, {})
	var st: Dictionary = L.get("stats", {})
	var c := Combatant.new()
	c.id = "player"
	c.is_player = true
	c.line = line
	c.tier = tier
	c.level = level
	c.mud_level = DSStats.mud_level(level, b)
	c.name = str(opts.get("name", "You"))
	var tiers: Array = L.get("tiers", [])
	if tier >= 1 and tier <= tiers.size():
		c.flags["class_name"] = tiers[tier - 1].get("name", line.capitalize())
	c.max_hp = int(st.get("hp_base", 100)) + int(st.get("hp_per_level", 20)) * (level - 1)
	c.max_hp = int(c.max_hp * (1.0 + float(opts.get("meta_hp_pct", 0)) / 100.0))
	c.hp = c.max_hp
	c.max_mana = int(st.get("mana_base", 0)) + int(st.get("mana_per_level", 0)) * (level - 1)
	c.mana = c.max_mana
	c.mana_regen = int(st.get("mana_regen", 0))
	c.stats = st.get("attributes", c.stats).duplicate()
	c.size = str(st.get("size", "medium"))
	c.ac = int(st.get("ac_base", 0))
	c.damroll = int(st.get("damroll_base", 0)) + int(st.get("damroll_per_level", 0)) * (level - 1)
	c.melee_fail = 0
	c.flags["damage_mult"] = (1.0 + float(opts.get("meta_damage_pct", 0)) / 100.0) * (1.0 + float(st.get("damage_pct", 0)) / 100.0)
	c.flags["spell_mult"] = 1.0 + float(st.get("spell_pct", 0)) / 100.0
	c.flags["damage_taken_mult"] = 1.0 + float(st.get("damage_taken_pct", 0)) / 100.0

	var bonuses: Dictionary = opts.get("bonuses", {})
	for n in data.kit_abilities(line, tier, level):
		var ul := data.unlock_level(n, line, tier)
		c.skills[n] = DSStats.proficiency(ul, level, b, int(bonuses.get(n, 0)))
	c.flags["weapon_skill"] = DSStats.weapon_proficiency(level, b, int(bonuses.get("weapon", 0)))

	# Gear: one weapon slot (dual wielders wield a matched pair), armor, trinket.
	c.weapon = opts.get("weapon", starting_weapon(data, str(L.get("starting_weapon", "dagger")), 1))
	var oh = L.get("offhand", null)
	if oh == "shield":
		c.shield = {"block": int(st.get("shield_block_value", 50))}
	elif oh != null and c.skills.has("dual wield") and c.weapon != null:
		c.offhand = c.weapon
	if opts.has("shield"):
		c.shield = opts["shield"]
	var passives: Array = []
	for slot in ["weapon", "armor", "trinket"]:
		var item = c.weapon if slot == "weapon" else opts.get(slot, null)
		if item == null:
			continue
		apply_item_stats(c, item)
		if item.has("passive"):
			passives.append(item["passive"])
	c.flags["passives"] = passives
	if passives.has("quickened"):
		c.add_status("haste", -1)
	c.hp = c.max_hp
	c.mana = c.max_mana

	if opts.has("actives"):
		c.actives = opts["actives"].duplicate()
	else:
		c.actives = data.kit_abilities(line, tier, level, "active")
	if opts.has("rules"):
		c.rules = opts["rules"].duplicate(true)
	else:
		c.rules = class_ai(data, line, tier, level)
	return c


## The class's built-in fighting priorities (overrides/classes.json "ai"), limited to abilities it
## knows at `level`. Checked top to bottom each round; the first usable one fires. DECISIONS.md D-060.
static func class_ai(data: DSData, line: String, tier: int, level: int) -> Array:
	var L: Dictionary = data.classes.get(line, {})
	var out: Array = []
	for r in L.get("ai", []):
		var aname := str(CombatSim.split_ref(str(r.get("then", "")))[0])
		var ul := data.unlock_level(aname, line, tier)
		if ul >= 1 and ul <= level:
			out.append(r.duplicate(true))
	return out


## Plain common weapon of `wtype` at item level `ilvl`.
static func starting_weapon(data: DSData, wtype: String, ilvl: int) -> Dictionary:
	var wdef: Dictionary = data.items.get("weapon_types", {}).get(wtype, {})
	var mn: Array = wdef.get("min", [5, 2])
	var mx: Array = wdef.get("max", [10, 4])
	var names: Array = data.items.get("weapon_names", {}).get(wtype, [wtype.capitalize()])
	return {"slot": "weapon", "type": wtype, "rarity": "common", "ilvl": ilvl,
		"min": int(round(float(mn[0]) + float(mn[1]) * (ilvl - 1))),
		"max": int(round(float(mx[0]) + float(mx[1]) * (ilvl - 1))),
		"level": ilvl * int(data.balance.get("level_scale", 10)), "dam_type": wdef.get("dam_type", "slash"),
		"flags": [], "affixes": [], "skill_bonus": {}, "damroll": 0, "hp": 0, "mana": 0, "name": names[0]}


## Add an item's flat bonuses to a combatant (weapon damage itself is read from c.weapon).
static func apply_item_stats(c: Combatant, item: Dictionary) -> void:
	c.ac += int(item.get("ac", 0))
	c.damroll += int(item.get("damroll", 0))
	c.max_hp += int(item.get("hp", 0))
	c.max_mana += int(item.get("mana", 0)) if c.max_mana > 0 else 0
	var sb: Dictionary = item.get("skill_bonus", {})
	for k in sb.keys():
		if c.skills.has(k):
			c.skills[k] = mini(100, int(c.skills[k]) + int(sb[k]))


## Monster `id` scaled to `level`.
static func make_monster(data: DSData, id: String, level: int, idx: int = 0) -> Combatant:
	var b := data.balance
	var m: Dictionary = data.monsters.get(id, {})
	var sc: Dictionary = b.get("monster_scaling", {})
	var c := Combatant.new()
	c.id = "%s_%d" % [id, idx]
	c.name = str(m.get("name", id))
	c.is_player = false
	c.level = level
	c.mud_level = DSStats.mud_level(level, b)
	var l1 := float(level - 1)
	var hp_mult := 1.0 + float(sc.get("hp_linear", 0.9)) * l1 + float(sc.get("hp_quadratic", 0.12)) * l1 * l1
	var dmg_mult := 1.0 + float(sc.get("dmg_linear", 0.3)) * l1
	c.max_hp = maxi(1, int(float(m.get("hp", 20)) * hp_mult))
	c.hp = c.max_hp
	var dm: Array = m.get("dmg", [1, 4])
	c.dmg_min = maxi(1, int(float(dm[0]) * dmg_mult))
	c.dmg_max = maxi(c.dmg_min, int(float(dm[1]) * dmg_mult))
	c.size = str(m.get("size", "medium"))
	c.stats = m.get("attributes", {"str": 14, "dex": 14, "con": 14, "int": 10, "wis": 10}).duplicate()
	c.skills = m.get("skills", {}).duplicate()
	c.resist = m.get("resist", []).duplicate()
	c.vuln = m.get("vuln", []).duplicate()
	c.immune = m.get("immune", []).duplicate()
	c.dam_type = str(m.get("dam_type", "slash"))
	c.attack_noun = str(m.get("noun", "hit"))
	c.toughness = int(m.get("toughness", 0))
	c.ac = int(m.get("ac", 0))
	c.no_stun = bool(m.get("no_stun", false))
	c.melee_fail = 40
	c.tags = m.get("tags", []).duplicate()
	c.flags["speed"] = int(m.get("speed", 0))
	if m.has("steady"):
		c.flags["steady"] = int(m["steady"])
	if m.get("flying", false):
		c.flags["flying"] = true
	c.monster_abilities = {}
	var abil: Dictionary = m.get("abilities", {})
	for k in abil.keys():
		var a: Dictionary = abil[k].duplicate(true)
		a["name"] = k
		if a.has("min"):
			a["min"] = int(float(a["min"]) * dmg_mult)
			a["max"] = int(float(a.get("max", a["min"])) * dmg_mult)
		c.monster_abilities[k] = a
	c.rules = m.get("rules", []).duplicate(true)
	c.flags["dmg_mult"] = dmg_mult
	c.flags["phases"] = m.get("phases", []).duplicate(true)
	return c


## Apply boons (ids from boons.json) to a player. Run-level effects (gold, xp) live in DSRunState.
static func apply_boons(data: DSData, c: Combatant, boon_ids: Array) -> void:
	for id in boon_ids:
		var b: Dictionary = data.boons.get(id, {})
		var e: Dictionary = b.get("effect", {})
		if e.has("flag"):
			c.flags[str(e["flag"])] = true
		var bs: Dictionary = e.get("stats", {})
		for k in bs.keys():
			c.flags[k] = int(c.flags.get(k, 0)) + int(bs[k])
		var sb: Dictionary = e.get("skill_bonus", {})
		for k in sb.keys():
			if c.skills.has(k):
				c.skills[k] = mini(100, int(c.skills[k]) + int(sb[k]))
		var ss: Dictionary = e.get("start_status", {})
		for k in ss.keys():
			var params: Dictionary = data.ability(k).get("params", {})
			c.add_status(k, int(ss[k]), {"ac": int(params.get("ac", 0))})
	if c.flags.get("boon_mana_regen", false):
		c.mana_regen += 2
	if int(c.flags.get("b_hp_pct", 0)) > 0:
		c.max_hp = int(c.max_hp * (1.0 + int(c.flags["b_hp_pct"]) / 100.0))
		c.hp = c.max_hp
	if c.flags.get("boon_keen_edge", false) and c.weapon != null:
		var w: Dictionary = c.weapon.duplicate(true)
		if not w["flags"].has("sharp"):
			w["flags"].append("sharp")
		c.weapon = w
		if c.offhand != null:
			c.offhand = w
