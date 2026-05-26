extends GutTest

# GAP-5: Active consumable usage during battle
# Tests for PlayableBattleController consumable API (sync-testable parts).
# Async UI interaction (button → signal → use_consumable loop) is covered
# by F6 smoke tests; this file covers the data layer.

var _bc: PlayableBattleController

func before_each() -> void:
	_bc = PlayableBattleController.new(42, 0, false)

# ---- set_consumables / has_usable_consumable / get_usable_consumables ----

func test_set_consumables_populates_list():
	_bc.set_consumables([&"hp_potion_v1", &"wall_peek_v1"])
	assert_true(_bc.has_usable_consumable(), "should have usable consumables")
	var usable: Array = _bc.get_usable_consumables()
	assert_eq(usable.size(), 2)
	assert_true(usable.has(&"hp_potion_v1"))
	assert_true(usable.has(&"wall_peek_v1"))

func test_empty_consumables():
	_bc.set_consumables([])
	assert_false(_bc.has_usable_consumable())
	assert_eq(_bc.get_usable_consumables().size(), 0)

func test_default_no_consumables():
	assert_false(_bc.has_usable_consumable())
	assert_eq(_bc.get_usable_consumables().size(), 0)

# ---- use_consumable ----

func test_use_consumable_removes_from_available():
	_bc.set_consumables([&"hp_potion_v1", &"wall_peek_v1"])
	var ok: bool = _bc.use_consumable(&"hp_potion_v1")
	assert_true(ok, "use should succeed")
	# After use: hp_potion_v1 removed from available, wall_peek_v1 remains
	var usable: Array = _bc.get_usable_consumables()
	assert_eq(usable.size(), 1)
	assert_true(usable.has(&"wall_peek_v1"))
	assert_false(usable.has(&"hp_potion_v1"))

func test_use_consumable_cannot_reuse_same_hand():
	# Even if we re-add the same consumable, the _used_consumables_this_hand
	# blocks re-use within the same hand.
	_bc.set_consumables([&"hp_potion_v1"])
	_bc.use_consumable(&"hp_potion_v1")
	# Manually re-inject (simulating a bug or edge case)
	_bc._available_consumables.append(&"hp_potion_v1")
	var ok: bool = _bc.use_consumable(&"hp_potion_v1")
	assert_false(ok, "same consumable cannot be used twice in one hand")

func test_use_nonexistent_consumable_fails():
	_bc.set_consumables([&"wall_peek_v1"])
	var ok: bool = _bc.use_consumable(&"nonexistent_v1")
	assert_false(ok)

func test_set_consumables_resets_used_tracking():
	_bc.set_consumables([&"hp_potion_v1"])
	_bc.use_consumable(&"hp_potion_v1")
	assert_false(_bc.has_usable_consumable())
	# New hand (new set_consumables call) should reset tracking
	_bc.set_consumables([&"hp_potion_v1"])
	assert_true(_bc.has_usable_consumable(), "new hand should reset used tracking")

# ---- wall_peek effect ----

func test_wall_peek_reveals_3_tiles():
	_bc.set_consumables([&"wall_peek_v1"])
	# Before using, no revealed tiles
	assert_eq(_bc.state.revealed_tiles.size(), 0)
	_bc.use_consumable(&"wall_peek_v1")
	# After using, 3 tiles should be revealed to seat 0
	assert_eq(_bc.state.revealed_tiles.size(), 3, "should reveal 3 wall tiles")
	for entry in _bc.state.revealed_tiles:
		assert_true(entry.visible_to.has(0), "should be visible to player seat 0")

# ---- hp_potion effect (signal-based, BC does not modify HP directly) ----

func test_hp_potion_emits_player_action_event():
	_bc.set_consumables([&"hp_potion_v1"])
	_bc.use_consumable(&"hp_potion_v1")
	# The use_consumable call emits a PLAYER_ACTION event with kind="use_consumable"
	var found: bool = false
	for ev in _bc.events:
		if ev.type == &"PLAYER_ACTION":
			var kind: String = String(ev.extra.get("kind", ""))
			if kind == "use_consumable":
				assert_eq(String(ev.extra.get("consumable_id", "")), "hp_potion_v1")
				found = true
				break
	assert_true(found, "should emit PLAYER_ACTION event for consumable use")

# ---- multiple consumables in sequence ----

func test_use_multiple_consumables_in_sequence():
	_bc.set_consumables([&"hp_potion_v1", &"wall_peek_v1"])
	_bc.use_consumable(&"hp_potion_v1")
	assert_eq(_bc.get_usable_consumables().size(), 1)
	_bc.use_consumable(&"wall_peek_v1")
	assert_eq(_bc.get_usable_consumables().size(), 0)
	assert_false(_bc.has_usable_consumable())
