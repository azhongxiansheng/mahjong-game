class_name CardPack

# 麻将王 — 里程碑 5 第 1 步：卡包主题（spec §9.2 第 2 行 + plan-5 D2）
#
# 三种主题：火力 / 速胡 / 控场。每个主题对池子的稀有度 / TileId 偏好做权重修正
# （v1 仅按稀有度修正；TileId 主题倾向 M6 内容化）。

enum Kind {
	AGGRO = 0,    # 火力 — 增番 / 高 rarity 牌权重 +
	FAST = 1,     # 速胡 — 立直系 / 速胡相关 +
	CONTROL = 2,  # 控场 — 阻胡 / 透明牌系 +
}

const PACK_SIZE: int = 5
const GUARANTEE_INDEX: int = 4  # 第 5 张走"精良+ 池子"

# Kind → 稀有度权重修正（相对 NODE_SINGLE_WEIGHTS 60/28/10/2）
# v1 简化：火力倾向更高 rarity；速胡保持默认；控场倾向 rarity 中等档
static func rarity_weights_for_theme(theme: int) -> Array:
	match theme:
		Kind.AGGRO:
			return [50.0, 30.0, 15.0, 5.0]   # 高 rarity 偏多
		Kind.FAST:
			return [55.0, 30.0, 12.0, 3.0]
		Kind.CONTROL:
			return [45.0, 35.0, 16.0, 4.0]   # 史诗偏多
	return Rarity.NODE_SINGLE_WEIGHTS

static func display_name(theme: int) -> String:
	match theme:
		Kind.AGGRO: return "火力包"
		Kind.FAST: return "速胡包"
		Kind.CONTROL: return "控场包"
	return "?"

# 解析 StringName id 到 Kind（用于 Run 内调用方传 &"aggro" 等友好名）
static func theme_from_id(id: StringName) -> int:
	match id:
		&"aggro": return Kind.AGGRO
		&"fast": return Kind.FAST
		&"control": return Kind.CONTROL
	return Kind.AGGRO
