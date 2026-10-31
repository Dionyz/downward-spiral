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
	c.flags["damage_mult"] = 1.0 + float(opts.get("meta_damage_pct", 0)) / 100.0

	var bonuses: Dictionary = opts.get("bonuses", {})
	for n in data.kit_abilities(line, tier, level):
		var ul := data.unlock_level(n, line, tier)
		c.skills[n] = DSStats.proficiency(ul, level, b, int(bonuses.get(n, 0)))
	c.flags["weapon_skill"] = DSStats.weapon_proficiency(level, b, int(bonuses.get("weapon", 0)))

	c.weapon = opts.get("weapon", starting_weapon(data, str(L.get("starting_weapon", "dagger")), 1))
	var oh = L.get("offhand", null)
	if opts.has("offhand"):
		c.offhand = opts["offhand"]
	elif oh == "shield":
		c.shield = {"block": int(st.get("shield_block_value", 50))}
	elif oh != null and c.skills.has("dual wield"):
		c.offhand = starting_weapon(data, str(oh), 1)
	if opts.has("shield"):
		c.shield = opts["shield"]
	var armor = opts.get("armor", null)
	if armor != null:
		c.ac += int(armor.get("ac", 0))
	var trinket = opts.get("trinket", null)
	if trinket != null:
		for k in trinket.get("skill_bonus", {}).keys():
			if c.skills.has(k):
				c.skills[k] = mini(100, c.skills[k] + int(trinket["skill_bonus"][k]))
		c.damroll += int(trinket.get("damroll", 0))

	if opts.has("actives"):
		c.actives = opts["actives"].duplicate()
	else:
		c.actives = default_actives(data, line, tier, level)
	if opts.has("rules"):
		c.rules = opts["rules"].duplicate(true)
	else:
		c.rules = default_rules(data, line, tier, level, int(opts.get("rule_slots", 2)))
	return c


## Equipped actives when the player hasn't chosen: starting actives, then signature unlocks, max 4.
static func default_actives(data: DSData, line: String, tier: int, level: int) -> Array:
	var L: Dictionary = data.classes.get(line, {})
	var out: Array = []
	for n in L.get("starting_actives", []):
		if data.unlock_level(n, line, tier) <= level and data.unlock_level(n, line, tier) >= 1:
			out.append(n)
	for n in L.get("signature", []):
		if out.size() >= int(data.balance.get("max_actives", 4)):
			break
		var ul := data.unlock_level(n, line, tier)
		if ul >= 1 and ul <= level and data.ability(n).get("kind", "") == "active":
			out.append(n)
	return out


## Class default rules, trimmed to rule slots and to abilities the character has.
static func default_rules(data: DSData, line: String, tier: int, level: int, slots: int) -> Array:
	var L: Dictionary = data.classes.get(line, {})
	var out: Array = []
	for r in L.get("default_rules", []):
		if out.size() >= slots:
			break
		var aname := str(CombatSim.split_ref(str(r.get("then", "")))[0])
		var ul := data.unlock_level(aname, line, tier)
		if ul >= 1 and ul <= level:
			out.append(r.duplicate())
	return out


static func starting_weapon(data: DSData, wtype: String, band: int) -> Dictionary:
	return weapon_from_base(data, wtype, band, [])


static func weapon_from_base(data: DSData, wtype: String, band: int, wflags: Array) -> Dictionary:
	var bases: Array = data.items.get("weapon_bases", [])
	var best = null
	for wb in bases:
		if wb.get("weapon_type", "") != wtype:
			continue
		if best == null or absi(int(wb["band"]) - band) < absi(int(best["band"]) - band):
			best = wb
	var mn := 5
	var mx := 10
	if best != null:
		mn = int(best["min"])
		mx = int(best["max"])
	var dt := "slash"
	if wtype in ["dagger", "spear", "polearm"]:
		dt = "pierce"
	elif wtype in ["mace", "flail", "staff"]:
		dt = "bash"
	return {"type": wtype, "min": mn, "max": mx, "level": band * int(data.balance.get("level_scale", 10)),
		"flags": wflags.duplicate(), "dam_type": dt, "name": wtype.capitalize()}


## Monster `id` scaled to `level`. Elites/bosses carry their own telegraph abilities.
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
	return c
