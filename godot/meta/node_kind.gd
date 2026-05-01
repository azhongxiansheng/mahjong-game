class_name NodeKind

# 麻将王 — 里程碑 4 第 1 步：Run 节点种类（spec §7）
#
# 6 类节点，v1 仅 NORMAL/ELITE/BOSS 接里程碑 3 的 4 人桌可玩；
# CAMP/SHOP/EVENT 占位场景（M5 内容生产时填）。

enum Kind {
	NORMAL = 0,   # 普通桌（4 人桌 vs 3 SimpleAi）
	ELITE = 1,    # 精英桌（M6 引入精英 AI 行为；v1 仍用 SimpleAi）
	CAMP = 2,     # 营地（M5 实装休整 / 升级）
	SHOP = 3,     # 商店（M5 实装抽卡 / 卡包）
	EVENT = 4,    # 文字事件（M5 实装）
	BOSS = 5,     # 章末 Boss（M6 引入特殊规则；v1 仍用 SimpleAi）
}

static func is_battle(kind: int) -> bool:
	return kind == Kind.NORMAL or kind == Kind.ELITE or kind == Kind.BOSS

static func is_placeholder(kind: int) -> bool:
	return kind == Kind.CAMP or kind == Kind.SHOP or kind == Kind.EVENT

static func display_name(kind: int) -> String:
	match kind:
		Kind.NORMAL: return "普通桌"
		Kind.ELITE: return "精英桌"
		Kind.CAMP: return "营地"
		Kind.SHOP: return "商店"
		Kind.EVENT: return "事件"
		Kind.BOSS: return "Boss"
	return "?"
