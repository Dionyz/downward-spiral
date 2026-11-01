class_name CharStats
extends RefCounted
## Everything that decides how your character fights, worked out from the same numbers the
## combat rules use. Shown on the in-run Character panel.
## sections() returns [{title, rows: [[label, value]]}]; rows with an empty value are skipped.


static func _pct(v: float) -> String:
	var r := roundi(v)
	return ("+%d%%" % r) if r > 0 else ("%d%%" % r)


## The few numbers the run HUD shows: average weapon hit and the chances to avoid a melee hit.
## Avoid combines parry, dodge, shield block and sidestep as independent rolls.
static func quick(run: DSRunState) -> Dictionary:
	var p: Combatant = run.world.player if run.world != null else run.make_player()
	var sim := CombatSim.new(DSRng.new(1), run.data)
	var foe := Combatant.new()
	var avg := 0.0
	if p.weapon != null:
		var r := sim.damage_range(p, "hit", p.weapon, false, false)
		avg = (int(r[0]) + int(r[1])) / 2.0 * float(p.flags.get("damage_mult", 1.0)) + CombatSim.bstat(p, "b_flat")
	var parts := {}
	if p.skill("parry") > 0:
		parts["parry"] = sim.parry_chance(foe, p)
	if p.skill("dodge") > 0:
		parts["dodge"] = sim.dodge_chance(foe, p)
	if p.shield != null and p.skill("shield block") > 0:
		parts["block"] = sim.block_chance(foe, p)
	if p.skill("sidestep") > 0:
		parts["sidestep"] = sim.sidestep_chance(foe, p)
	var hit_through := 1.0
	for k in parts.keys():
		hit_through *= 1.0 - int(parts[k]) / 100.0
	return {"avg": avg, "avoid": roundi((1.0 - hit_through) * 100.0), "parts": parts}


static func sections(run: DSRunState) -> Array:
	var data := run.data
	var p: Combatant = run.world.player if run.world != null else run.make_player()
	var sim := CombatSim.new(DSRng.new(1), data)
	var foe := Combatant.new()
	var L: Dictionary = data.classes.get(run.line, {})
	var b := func(k: String) -> int: return CombatSim.bstat(p, k)
	var out: Array = []

	# --- Character ---
	var rows: Array = []
	rows.append(["Class", "%s (mastery %d)" % [str(L.get("display", run.line)), run.mastery]])
	rows.append(["Race", str(data.races.get(run.race, {}).get("name", run.race.capitalize()))])
	rows.append(["Level", "%d (%d / %d XP)" % [run.level, run.xp, run.xp_to_next()]])
	rows.append(["Health", "%d / %d" % [maxi(0, p.hp), p.max_hp]])
	var sh := int(p.flags.get("shield_hp", 0))
	rows.append(["Shield", str(sh) if sh > 0 else ""])
	if p.max_mana > 0:
		rows.append(["Mana", "%d / %d (+%d a turn in fights)" % [p.mana, p.max_mana, p.mana_regen]])
	var a: Dictionary = p.stats
	rows.append(["Attributes", "Str %d · Dex %d · Con %d · Int %d · Wis %d" % [int(a.get("str", 15)), int(a.get("dex", 15)), int(a.get("con", 15)), int(a.get("int", 15)), int(a.get("wis", 15))]])
	out.append({"title": "Character", "rows": rows})

	# --- Offense ---
	rows = []
	var w = p.weapon
	if w != null:
		var rng_ := sim.damage_range(p, "hit", w, false, false)
		rows.append(["Weapon", "%s, %d-%d damage" % [str(w.get("name", "?")), int(rng_[0]), int(rng_[1])]])
		rows.append(["Average hit", Cards._num((int(rng_[0]) + int(rng_[1])) / 2.0 * float(p.flags.get("damage_mult", 1.0)))])
	if p.total_damroll() >= 10:
		rows.append(["Weapon damage bonus", "+%s" % Cards._num(p.total_damroll() / 10.0)])
	if p.offhand != null:
		rows.append(["Off-hand", "dual wielding"])
	rows.append(["Damage", _pct((float(p.flags.get("damage_mult", 1.0)) - 1.0) * 100.0 + b.call("b_dmg_pct"))])
	if p.max_mana > 0 or float(p.flags.get("spell_mult", 1.0)) != 1.0:
		rows.append(["Spell power", _pct((float(p.flags.get("spell_mult", 1.0)) - 1.0) * 100.0)])
	rows.append(["Flat damage per hit", ("+%d" % b.call("b_flat")) if b.call("b_flat") > 0 else ""])
	rows.append(["Accuracy (hitroll)", ("%+d" % p.total_hitroll()) if p.total_hitroll() != 0 else ""])
	var extra: Array = []
	if p.skill("second attack") > 0:
		extra.append("2nd %d%%" % (DSStats.idiv(p.skill("second attack"), 3) * 2))
	if p.skill("third attack") > 0:
		extra.append("3rd %d%%" % DSStats.idiv(p.skill("third attack"), 2))
	if p.skill("fourth attack") > 0:
		extra.append("4th %d%%" % DSStats.idiv(p.skill("fourth attack") * 4, 5))
	rows.append(["Extra attacks", " · ".join(extra) if not extra.is_empty() else "none yet"])
	if p.skill("enhanced damage") > 0:
		rows.append(["Enhanced damage", "%d%% of hits deal +50%%" % p.skill("enhanced damage")])
	var crit := 0.0
	if p.line_is(CombatSim.THIEF_WARRIOR_LINES) and p.skill("critical hit") > 0:
		crit += p.skill("critical hit") * 0.15
	crit += b.call("b_crit")
	rows.append(["Critical hits", ("%s%% chance, %d%% damage" % [Cards._num(crit), 175 + b.call("b_crit_dmg")]) if crit > 0 else "none"])
	rows.append(["Bonus vs one foe", _pct(b.call("b_duel")) if b.call("b_duel") > 0 else ""])
	rows.append(["Bonus vs elites and bosses", _pct(b.call("b_giant")) if b.call("b_giant") > 0 else ""])
	rows.append(["Bonus under 30% health", _pct(b.call("b_berserk_low")) if b.call("b_berserk_low") > 0 else ""])
	rows.append(["Execute (under 20% health)", ("%d%% chance" % b.call("b_execute")) if b.call("b_execute") > 0 else ""])
	rows.append(["Best hit this run", str(int(run.stats.get("best_hit", 0))) if int(run.stats.get("best_hit", 0)) > 0 else ""])
	rows.append(["Skill cooldowns", ("-%d turns" % b.call("b_cdr")) if b.call("b_cdr") > 0 else ""])
	out.append({"title": "Offense", "rows": rows})

	# --- Defense ---
	rows = []
	rows.append(["Armor", str(-sim._total_ac(p))])
	var taken := (float(p.flags.get("damage_taken_mult", 1.0)) - 1.0) * 100.0
	rows.append(["Class damage taken", _pct(taken) if absf(taken) >= 0.5 else ""])
	var dr := mini(b.call("b_dr_all"), CombatSim.DR_CAP)
	rows.append(["Damage reduction", "%d%% (cap %d%%)" % [dr, CombatSim.DR_CAP] if dr > 0 else ""])
	rows.append(["...under 40% health", ("+%d%%" % b.call("b_dr_low")) if b.call("b_dr_low") > 0 else ""])
	rows.append(["...vs 2+ foes", ("+%d%%" % b.call("b_dr_pack")) if b.call("b_dr_pack") > 0 else ""])
	rows.append(["...vs special attacks", ("+%d%%" % b.call("b_dr_special")) if b.call("b_dr_special") > 0 else ""])
	rows.append(["Flat reduction per hit", ("-%d" % b.call("b_dr_flat")) if b.call("b_dr_flat") > 0 else ""])
	var buff := p.buff_reduction()
	rows.append(["Spell wards", ("-%d%% damage" % roundi(buff * 100.0)) if buff > 0.0 else ""])
	rows.append(["Parry", ("%d%%" % sim.parry_chance(foe, p)) if p.skill("parry") > 0 and sim.parry_chance(foe, p) > 0 else ""])
	rows.append(["Dodge", ("%d%%" % sim.dodge_chance(foe, p)) if p.skill("dodge") > 0 else ""])
	rows.append(["Shield block", ("%d%%" % sim.block_chance(foe, p)) if p.shield != null and p.skill("shield block") > 0 else ""])
	rows.append(["Sidestep", ("%d%%" % sim.sidestep_chance(foe, p)) if p.skill("sidestep") > 0 else ""])
	rows.append(["Biggest hit you can take", "%d%% of max health" % int(data.balance.get("enemy_hit_cap_pct", 35))])
	if not p.resist.is_empty():
		rows.append(["Resists", ", ".join(p.resist)])
	if not p.immune.is_empty():
		rows.append(["Immune to", ", ".join(p.immune)])
	if not p.vuln.is_empty():
		rows.append(["Vulnerable to", ", ".join(p.vuln)])
	out.append({"title": "Defense", "rows": rows})

	# --- Recovery ---
	rows = []
	rows.append(["Health potions", "%d (heal %d%%)" % [int(run.potions.get("hp", 0)), int(data.balance.get("potion_pct", 50))]])
	if p.max_mana > 0:
		rows.append(["Mana potions", str(int(run.potions.get("mp", 0)))])
	rows.append(["Life leech", ("%d%% of damage dealt" % b.call("b_leech")) if b.call("b_leech") > 0 else ""])
	rows.append(["Leech under 50% health", ("+%d%%" % b.call("b_adrenaline")) if b.call("b_adrenaline") > 0 else ""])
	rows.append(["Regeneration", ("%d%% health a turn" % b.call("b_regen")) if b.call("b_regen") > 0 else ""])
	rows.append(["Heal on kill", ("%d%% health" % b.call("b_kill_heal")) if b.call("b_kill_heal") > 0 else ""])
	rows.append(["Shield after a hit", ("%d%% of max health" % b.call("b_bulwark")) if b.call("b_bulwark") > 0 else ""])
	var ls := int(run.boons.count("last_stand")) - int(run.stats.get("last_stands", 0))
	rows.append(["Last Stand left", str(ls) if run.boons.has("last_stand") else ""])
	rows.append(["Out of combat", "regain health slowly while exploring"])
	out.append({"title": "Recovery", "rows": rows})

	# Drop empty rows.
	for s in out:
		s["rows"] = s["rows"].filter(func(r): return str(r[1]) != "")
	return out
