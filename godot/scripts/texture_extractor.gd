## 麻将牌纹理加载（autoload）
##
## v2: 改用 lietxia/mahjong_graphic 的标准日麻矢量牌（272×389 透明 PNG，34 张 + 红宝 3 张 + 牌背）。
## 旧 v1 从 mahjong_atlas0.png 切 80×120 网格的方案被废弃 — 那张图实际是 FairyGUI 的整包 UI 截图，
## 牌不在网格位置，切出来全是空白。
##
## 命名约定（标准日麻 riichi notation，与素材包 1m..9m/1p..9p/1s..9s/1z..7z 文件名匹配）：
##   m 万子 (Manzu)：1m..9m + 0m=赤五万
##   p 筒子 (Pinzu)：1p..9p + 0p=赤五筒
##   s 索子 (Souzu)：1s..9s + 0s=赤五索
##   z 字牌 (Jihai)：1z=东 / 2z=南 / 3z=西 / 4z=北 / 5z=白 / 6z=发 / 7z=中
extends Node

const TILES_DIR: String = "res://assets/mahjong_tiles_riichi/"

# 内部图集：key（1m..9m, 1p..9p, 1s..9s, 1z..7z, 0m, 0p, 0s, back）→ Texture2D
var extracted_tiles: Dictionary = {}

func _ready() -> void:
	_load_tiles()
	print("✅ TextureExtractor initialized (riichi vector tiles, %d 张)" % extracted_tiles.size())

func _load_tiles() -> void:
	# 数牌 1-9
	for n in range(1, 10):
		_load_one("%dm" % n)
		_load_one("%dp" % n)
		_load_one("%ds" % n)
	# 字牌 1z-7z
	for z in range(1, 8):
		_load_one("%dz" % z)
	# 红宝 0m/0p/0s（5 万/5 筒/5 索 的红色版本）
	_load_one("0m")
	_load_one("0p")
	_load_one("0s")
	# 牌背
	_load_one("back")

func _load_one(key: String) -> void:
	var path: String = TILES_DIR + key + ".png"
	if not ResourceLoader.exists(path):
		push_warning("[TextureExtractor] missing tile: %s" % path)
		return
	var tex: Texture2D = load(path) as Texture2D
	if tex != null:
		extracted_tiles[key] = tex

# CardTileBack 等消费方调；缺牌时返 null（让 caller fall-back 到 Label）。
func get_tile_texture(tile_name: String) -> Texture2D:
	if tile_name in extracted_tiles:
		return extracted_tiles[tile_name]
	return null
