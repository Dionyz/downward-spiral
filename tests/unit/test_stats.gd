extends GutTest
## Level, proficiency, cooldown and mana mapping.

const B := {"level_scale": 10, "proficiency": {"start": 40, "per_level": 10, "cap": 95, "hard_cap": 100},
	"cooldown_divisor": 12, "min_cooldown": 1, "mana_cost_scale": 0.25,
	"weapon_proficiency": {"start": 75, "per_level": 2, "cap": 95}}


func test_proficiency_curve():
	assert_eq(DSStats.proficiency(1, 1, B), 40, "40% when unlocked")
	assert_eq(DSStats.proficiency(1, 2, B), 50)
	assert_eq(DSStats.proficiency(3, 5, B), 60)
	assert_eq(DSStats.proficiency(1, 10, B), 95, "cap 95")
	assert_eq(DSStats.proficiency(1, 10, B, 10), 100, "bonus over cap, hard cap 100")
	assert_eq(DSStats.proficiency(4, 3, B), 0, "not unlocked yet")


func test_mud_level_mapping():
	assert_eq(DSStats.mud_level(1, B), 10)
	assert_eq(DSStats.mud_level(10, B), 100)


func test_cooldown_from_beats():
	# Beats are pulses; one combat round (PULSE_VIOLENCE) is 12 pulses.
	assert_eq(DSStats.cooldown_rounds(10, B), 1, "bash beats 10 -> 1 round")
	assert_eq(DSStats.cooldown_rounds(24, B), 2, "circle beats 24 -> 2 rounds")
	assert_eq(DSStats.cooldown_rounds(20, B), 2, "backstab beats 20")
	assert_eq(DSStats.cooldown_rounds(4, B), 1, "magic fist beats 4")
	assert_eq(DSStats.cooldown_rounds(0, B), 1, "warcry beats 0 -> min 1")


func test_mana_cost_scale():
	assert_eq(DSStats.mana_cost(0, B), 0)
	assert_eq(DSStats.mana_cost(20, B), 5)
	assert_eq(DSStats.mana_cost(75, B), 19, "chain lightning")
	assert_eq(DSStats.mana_cost(2, B), 1, "never below 1")


func test_weapon_proficiency():
	assert_eq(DSStats.weapon_proficiency(1, B), 75)
	assert_eq(DSStats.weapon_proficiency(10, B), 93)


func test_c_integer_division_truncates_toward_zero():
	assert_eq(DSStats.idiv(7, 2), 3)
	assert_eq(DSStats.idiv(-7, 2), -3)
