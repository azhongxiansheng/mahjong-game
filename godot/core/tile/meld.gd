class_name Meld

enum Kind { CHI, PON, MINKAN, ANKAN, ADDED_KAN }

var kind: Kind
var tiles: Array[Tile]
var from_seat: int  # 牌来自哪个 seat（暗杠 = -1）

func _init(p_kind: Kind, p_tiles: Array[Tile], p_from: int) -> void:
	kind = p_kind
	tiles = p_tiles
	from_seat = p_from

static func make_chi(p_tiles: Array[Tile], from_seat: int) -> Meld:
	return Meld.new(Kind.CHI, p_tiles, from_seat)

static func make_pon(p_tiles: Array[Tile], from_seat: int) -> Meld:
	return Meld.new(Kind.PON, p_tiles, from_seat)

static func make_minkan(p_tiles: Array[Tile], from_seat: int) -> Meld:
	return Meld.new(Kind.MINKAN, p_tiles, from_seat)

static func make_ankan(p_tiles: Array[Tile]) -> Meld:
	return Meld.new(Kind.ANKAN, p_tiles, -1)

static func make_added_kan(p_tiles: Array[Tile], from_seat: int) -> Meld:
	return Meld.new(Kind.ADDED_KAN, p_tiles, from_seat)

func is_concealed() -> bool:
	return kind == Kind.ANKAN

func is_kan() -> bool:
	return kind == Kind.MINKAN or kind == Kind.ANKAN or kind == Kind.ADDED_KAN

func to_id_array() -> Array:
	var ids := []
	for t in tiles:
		ids.append(t.id)
	return ids
