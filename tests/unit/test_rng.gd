extends GutTest
## DSRng: Park-Miller, deterministic across platforms.


func test_known_sequence_for_seed_42():
	var r := DSRng.new(42)
	assert_eq([r.next_int(), r.next_int(), r.next_int()], [2027382, 1226992407, 551494037])


func test_number_percent_matches_hand_computed():
	var r := DSRng.new(42)
	assert_eq([r.number_percent(), r.number_percent(), r.number_percent(), r.number_percent(), r.number_percent()],
		[83, 8, 38, 16, 43])


func test_same_seed_same_stream():
	var a := DSRng.new(1234)
	var b := DSRng.new(1234)
	for i in 200:
		assert_eq(a.number_range(1, 1000), b.number_range(1, 1000))


func test_range_bounds():
	var r := DSRng.new(7)
	for i in 2000:
		var v := r.number_range(3, 9)
		assert_true(v >= 3 and v <= 9)
	assert_eq(r.number_range(5, 5), 5)
	assert_eq(r.number_range(9, 2), 9, "hi < lo returns lo like the MUD")


func test_zero_seed_is_valid():
	var r := DSRng.new(0)
	assert_gt(r.next_int(), 0)


func test_state_round_trip():
	var r := DSRng.new(99)
	r.next_int()
	var s := r.save_state()
	var a := r.next_int()
	r.load_state(s)
	assert_eq(r.next_int(), a)
