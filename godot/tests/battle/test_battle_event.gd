extends GutTest

func test_make_minimal_event():
	var ev := BattleEvent.make(&"WIN_DECLARED", 0)
	assert_eq(ev.type, &"WIN_DECLARED")
	assert_eq(ev.actor_seat, 0)
	assert_null(ev.tile_instance)
	assert_eq(ev.chain_id, 0)
	assert_eq(ev.extra, {})

func test_make_with_tile_and_extra():
	var ti := TileInstance.make(Tile.new(TileId.W5), 0)
	var ev := BattleEvent.make(&"RON_DECLARED", 1, ti, {"points_won": 8000})
	assert_eq(ev.actor_seat, 1)
	assert_eq(ev.tile_instance, ti)
	assert_eq(ev.extra.get("points_won", 0), 8000)

func test_chain_id_assignable_after_make():
	var ev := BattleEvent.make(&"TILE_DRAWN", 2)
	ev.chain_id = 42
	assert_eq(ev.chain_id, 42)
