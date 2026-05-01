extends GutTest

func test_make_plain_tile_no_skill():
	var ti := TileInstance.make(Tile.new(TileId.W5), 0)
	assert_eq(ti.tile.id, TileId.W5)
	assert_eq(ti.owner_seat, 0)
	assert_eq(ti.holder_seat, -1)
	assert_null(ti.skill)

func test_make_with_skill():
	var skill := SkillResource.new()
	skill.id = &"thunder_5w_v1"
	var ti := TileInstance.make(Tile.new(TileId.W5), 1, skill)
	assert_eq(ti.skill, skill)
	assert_eq(ti.owner_seat, 1)

func test_holder_seat_mutable():
	var ti := TileInstance.make(Tile.new(TileId.W5), 0)
	ti.holder_seat = 2
	assert_eq(ti.holder_seat, 2)
