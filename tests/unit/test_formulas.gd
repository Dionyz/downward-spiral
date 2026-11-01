extends GutTest
## Hand-worked examples from fight.c. Each comment shows the C arithmetic.

const H = preload("res://tests/helpers.gd")
var data: DSData
var sim: CombatSim


func before_each():
	data = H.data()
	sim = CombatSim.new(DSRng.new(1), data)


func _pc(wskill: int = 75) -> Combatant:
	var c := H.dummy("pc", true)
	c.line = "warrior"
	c.flags["weapon_skill"] = wskill
	return c


# --- get_char_min / get_char_max ---------------------------------------------

func test_plain_weapon_range_scaled_by_weapon_skill():
	# min = 10 * 75/100 = 7 ; max = 20 * 75/100 = 15
	assert_eq(sim.damage_range(_pc(), "hit", H.sword(), false, false), [7, 15])


func test_enhanced_damage_adds_half():
	# min = (10 + 10/2) * 75/100 = 11 ; max = (20 + 20/2) * 75/100 = 22
	assert_eq(sim.damage_range(_pc(), "hit", H.sword(), true, false), [11, 22])


func test_sharp_adds_15_percent():
	# min = 10 + 10*15/100 = 11 -> 8 ; max = 20 + 3 = 23 -> 17
	assert_eq(sim.damage_range(_pc(), "hit", H.sword(10, 20, 10, ["sharp"]), false, false), [8, 17])


func test_damroll_adds_tenth():
	var c := _pc(100)
	c.damroll = 25  # +2
	assert_eq(sim.damage_range(c, "hit", H.sword(), false, false), [12, 22])


func test_backstab_scales_with_weapon_level_and_prefers_daggers():
	# dagger lvl 10: min = 10 + (10*(10*2.4))/100 = 12 -> 9 ; max = 20 + (20*(10*5.5))/100 = 31 -> 23
	assert_eq(sim.damage_range(_pc(), "backstab", H.dagger(), false, false), [9, 23])
	# sword lvl 10: min = 10 + 10*20/100 = 12 -> 9 ; max = 20 + 20*50/100 = 30 -> 22
	assert_eq(sim.damage_range(_pc(), "backstab", H.sword(), false, false), [9, 22])


func test_backstab_at_weapon_level_100():
	# dagger lvl 100, 50/101, skill 100: min = 50 + 50*240/100 = 170 ; max = 101 + 101*550/100 = 656
	assert_eq(sim.damage_range(_pc(100), "backstab", H.dagger(50, 101, 100), false, false), [170, 656])


func test_npc_uses_its_damage_dice_and_no_skill_scaling():
	var m := H.dummy("mob")
	m.dmg_min = 3
	m.dmg_max = 8
	m.damroll = 25
	assert_eq(sim.damage_range(m, "hit", null, false, false), [5, 10])


# --- damage() reductions ----------------------------------------------------

func _hit(victim: Combatant, dam: int, spell: bool = false, dtype: String = "slash") -> int:
	var src := H.dummy("src", true)
	return sim.apply_damage(src, victim, dam, "hit", dtype, spell)


func test_spell_damage_loses_a_quarter():
	assert_eq(_hit(H.dummy(), 100, true), 75)


func test_sanctuary_halves():
	var v := H.dummy()
	v.add_status("sanctuary", 5)
	assert_eq(_hit(v, 100), 50)
	assert_eq(_hit(v, 100, true), 37, "spell then sanctuary: 100 -> 75 -> 37")


func test_resist_and_vulnerable_are_quarter_steps():
	var v := H.dummy()
	v.resist = ["slash"]
	assert_eq(_hit(v, 100), 75)
	var w := H.dummy()
	w.vuln = ["slash"]
	assert_eq(_hit(w, 100), 125, "vulnerable is +25% in damage(), not +50%")


func test_toughness_and_minimum_one():
	var v := H.dummy()
	v.toughness = 5
	assert_eq(_hit(v, 100), 95)
	assert_eq(_hit(v, 3), 1, "spec: minimum 1 damage")


func test_armor_class_reduction():
	var v := H.dummy()
	v.ac = -400  # dam -= (400/2000 * 0.3) * dam = 6
	assert_eq(_hit(v, 100), 94)
	var w := H.dummy()
	w.ac = -5000  # clamps to -2000 -> 30%
	assert_eq(_hit(w, 100), 70)


func test_enemy_hit_is_capped_at_35_percent():
	var pc := H.dummy("pc", true)
	pc.max_hp = 100
	pc.hp = 100
	var mob := H.dummy("mob")
	assert_eq(sim.apply_damage(mob, pc, 90, "hit", "bash", false), 35)
	pc.hp = 100
	assert_eq(sim.apply_damage(mob, pc, 90, "hit", "bash", false, {"uncapped": true}), 90)


# --- defenses -----------------------------------------------------------------

func test_parry_chance():
	var atk := H.dummy("atk")
	var v := H.dummy("v", true)
	v.weapon = H.sword()
	v.skills["parry"] = 60
	assert_eq(sim.parry_chance(atk, v), 20, "60/3")
	v.skills["parry"] = 0
	assert_eq(sim.parry_chance(atk, v), 10, "clamped up to 10")
	v.skills["parry"] = 300
	assert_eq(sim.parry_chance(atk, v), 50, "clamped to 50")
	v.skills["parry"] = 60
	v.add_status("stunned", 2)
	assert_eq(sim.parry_chance(atk, v), 10)


func test_unarmed_player_cannot_parry_unarmed_npc_halves():
	var atk := H.dummy("atk")
	var pc := H.dummy("pc", true)
	pc.skills["parry"] = 90
	assert_eq(sim.parry_chance(atk, pc), 0)
	var mob := H.dummy("mob")
	mob.skills["parry"] = 90
	assert_eq(sim.parry_chance(atk, mob), 15, "90/3/2")


func test_dodge_chance():
	var atk := H.dummy("atk")
	var v := H.dummy("v")
	v.skills["dodge"] = 60
	assert_eq(sim.dodge_chance(atk, v), 30)
	v.skills["dodge"] = 200
	assert_eq(sim.dodge_chance(atk, v), 70, "medium size cap 70")
	v.size = "small"
	assert_eq(sim.dodge_chance(atk, v), 80)
	v.size = "medium"
	v.skills["dodge"] = 60
	v.add_status("blind", 2)
	assert_eq(sim.dodge_chance(atk, v), 15, "can't see attacker: 30/2")
	v.remove_status("blind")
	v.add_status("asleep", 2)
	assert_eq(sim.dodge_chance(atk, v), 0, "no defenses while asleep")


func test_shield_block_chance():
	var atk := H.dummy("atk")
	var v := H.dummy("v", true)
	v.skills["shield block"] = 40
	assert_eq(sim.block_chance(atk, v), 0, "no shield")
	v.shield = {"block": 55}
	assert_eq(sim.block_chance(atk, v), 22, "55 * 40 / 100")
	v.skills["shield block"] = 10
	assert_eq(sim.block_chance(atk, v), 10, "clamped up to 10")
	v.shield = {"block": 100}
	v.skills["shield block"] = 100
	assert_eq(sim.block_chance(atk, v), 66, "clamped to 66")


# --- combat log text ------------------------------------------------------------

func test_log_uses_second_person_for_the_player():
	assert_eq(CombatText.line({"t": "dodge", "src": "You", "dst": "a rat"}), "You dodge a rat's swing.")
	assert_eq(CombatText.line({"t": "dodge", "src": "a rat", "dst": "You"}), "A rat dodges your swing.")
	assert_eq(CombatText.line({"t": "ability", "src": "You", "dst": "a rat", "ability": "bash"}), "You use bash on a rat.")
	assert_eq(CombatText.line({"t": "status_applied", "dst": "You", "status": "blind"}), "You are blinded.")
	var d := CombatText.line({"t": "damage", "src": "a rat", "dst": "You", "amount": 5, "max_hp": 100, "dt": "hit"})
	assert_true(d.begins_with("A rat's strike") and d.find(" you. [5]") > 0, d)
