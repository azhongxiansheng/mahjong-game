extends Node

# Autoload: BattlePass — 轻量本地赛季 + 战令框架。
#
# 设计目标:留商业化扩展位但不依赖后端 / 不接真支付。运营接入时只需:
#   1. 加一个 "purchased_premium: bool" 字段(已留)
#   2. 主菜单加 "购买高级战令 ¥30" 按钮 → 调 IAP → set_premium(true)
#   3. 服务端按 season_id 校验购买记录(可后续扩)
#
# Season:
#   - season_id = YYYYMM (本地年月,如 202605)
#   - 每月 1 日自动 reset season_xp / claimed_levels,旧 claim 状态保留(仅清当月)
#   - 玩家通过 daily quest / battle 完成累 season_xp,每 100xp 升 1 级
#   - 每级有 free reward (renown/gold) 和 premium reward (skin/character/...)
#   - premium reward 仅 purchased_premium=true 时可领;否则按钮 disabled
#
# Persistence: user://battle_pass.json
#
# 信号:
#   level_up(new_level) — 升级时 emit,UI 弹 "🎖️ 赛季等级提升到 N"
#   reward_unlocked(level, is_premium) — 解锁时 emit,UI 显示 claim 按钮

const SAVE_PATH: String = "user://battle_pass.json"
const XP_PER_LEVEL: int = 100
const MAX_LEVEL: int = 30  # 一季 30 级:平均 1 天 1 级要做 1 个 100xp 任务

signal level_up(new_level: int)
signal reward_unlocked(level: int, is_premium: bool)
signal season_changed(new_season_id: int)

var season_id: int = 0
var season_xp: int = 0
var purchased_premium: bool = false
# claim 状态:int(level) → "free"/"premium"/"both" 字符串记已领类型
var claimed: Dictionary = {}

# 奖励表:level → {free: Dictionary, premium: Dictionary}
# free/premium reward 用 {kind: "gold"/"renown"/"skin", amount: N, id: "xxx"}
# v1 仅 gold/renown,皮肤 / 角色 id 等 M8 内容化时填。
const REWARDS: Array = [
	# level 1-30,每 5 级一个"小高潮"premium 给点厚的
	{"free": {"kind": "gold", "amount": 50}, "premium": {"kind": "renown", "amount": 20}},
	{"free": {"kind": "renown", "amount": 5}, "premium": {"kind": "gold", "amount": 100}},
	{"free": {"kind": "gold", "amount": 50}, "premium": {"kind": "renown", "amount": 20}},
	{"free": {"kind": "renown", "amount": 5}, "premium": {"kind": "gold", "amount": 100}},
	{"free": {"kind": "gold", "amount": 100}, "premium": {"kind": "skin", "amount": 1, "id": "tile_skin_neon"}},
	{"free": {"kind": "gold", "amount": 50}, "premium": {"kind": "renown", "amount": 30}},
	{"free": {"kind": "renown", "amount": 10}, "premium": {"kind": "gold", "amount": 150}},
	{"free": {"kind": "gold", "amount": 50}, "premium": {"kind": "renown", "amount": 30}},
	{"free": {"kind": "renown", "amount": 10}, "premium": {"kind": "gold", "amount": 150}},
	{"free": {"kind": "gold", "amount": 150}, "premium": {"kind": "skin", "amount": 1, "id": "table_skin_jade"}},
	{"free": {"kind": "gold", "amount": 50}, "premium": {"kind": "renown", "amount": 40}},
	{"free": {"kind": "renown", "amount": 15}, "premium": {"kind": "gold", "amount": 200}},
	{"free": {"kind": "gold", "amount": 50}, "premium": {"kind": "renown", "amount": 40}},
	{"free": {"kind": "renown", "amount": 15}, "premium": {"kind": "gold", "amount": 200}},
	{"free": {"kind": "gold", "amount": 200}, "premium": {"kind": "character", "amount": 1, "id": "season_char_v1"}},
	{"free": {"kind": "gold", "amount": 50}, "premium": {"kind": "renown", "amount": 50}},
	{"free": {"kind": "renown", "amount": 20}, "premium": {"kind": "gold", "amount": 250}},
	{"free": {"kind": "gold", "amount": 50}, "premium": {"kind": "renown", "amount": 50}},
	{"free": {"kind": "renown", "amount": 20}, "premium": {"kind": "gold", "amount": 250}},
	{"free": {"kind": "gold", "amount": 250}, "premium": {"kind": "skin", "amount": 1, "id": "back_skin_gold"}},
	{"free": {"kind": "gold", "amount": 50}, "premium": {"kind": "renown", "amount": 60}},
	{"free": {"kind": "renown", "amount": 25}, "premium": {"kind": "gold", "amount": 300}},
	{"free": {"kind": "gold", "amount": 50}, "premium": {"kind": "renown", "amount": 60}},
	{"free": {"kind": "renown", "amount": 25}, "premium": {"kind": "gold", "amount": 300}},
	{"free": {"kind": "gold", "amount": 300}, "premium": {"kind": "skin", "amount": 1, "id": "win_burst_skin_v1"}},
	{"free": {"kind": "gold", "amount": 50}, "premium": {"kind": "renown", "amount": 75}},
	{"free": {"kind": "renown", "amount": 30}, "premium": {"kind": "gold", "amount": 400}},
	{"free": {"kind": "gold", "amount": 50}, "premium": {"kind": "renown", "amount": 75}},
	{"free": {"kind": "renown", "amount": 30}, "premium": {"kind": "gold", "amount": 400}},
	{"free": {"kind": "gold", "amount": 500}, "premium": {"kind": "title", "amount": 1, "id": "title_season_champion"}},
]


func _ready() -> void:
	_load_from_disk()
	_ensure_season()
	# 接 DailyQuest.quest_claimed → 累 season_xp
	var dq = get_node_or_null("/root/DailyQuest")
	if dq and dq.has_signal("quest_claimed"):
		if not dq.quest_claimed.is_connected(_on_quest_claimed):
			dq.quest_claimed.connect(_on_quest_claimed)


func _on_quest_claimed(_quest_id: StringName, _gold: int, _renown: int, xp: int) -> void:
	add_xp(xp)


# 把 N xp 加到 season_xp,跨级时多次 emit level_up + reward_unlocked。
func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	var prev_level: int = current_level()
	season_xp += amount
	var new_level: int = current_level()
	_save_to_disk()
	if new_level > prev_level:
		for lv in range(prev_level + 1, new_level + 1):
			emit_signal("level_up", lv)
			emit_signal("reward_unlocked", lv, false)
			if purchased_premium:
				emit_signal("reward_unlocked", lv, true)


func current_level() -> int:
	return mini(season_xp / XP_PER_LEVEL, MAX_LEVEL)


func xp_progress_in_level() -> int:
	return season_xp % XP_PER_LEVEL


# 玩家点 claim 按钮 → 加奖励 + 标记。is_premium=true 要 purchased_premium=true
# 否则返 false(UI 应 disabled,但 defense check 再加一道)。
func claim_reward(level: int, is_premium: bool) -> Dictionary:
	if level < 1 or level > MAX_LEVEL:
		return {}
	if level > current_level():
		return {}
	if is_premium and not purchased_premium:
		return {}
	var key: int = level
	var prev: String = String(claimed.get(key, ""))
	var tag: String = "premium" if is_premium else "free"
	if tag in prev:
		return {}  # 已领
	var new_tag: String
	if prev == "":
		new_tag = tag
	else:
		new_tag = "both"
	claimed[key] = new_tag
	_save_to_disk()
	var reward_idx: int = level - 1
	if reward_idx >= REWARDS.size():
		return {}
	var bundle: Dictionary = REWARDS[reward_idx]
	return bundle.get("premium" if is_premium else "free", {})


func is_claimed(level: int, is_premium: bool) -> bool:
	var prev: String = String(claimed.get(level, ""))
	var tag: String = "premium" if is_premium else "free"
	return tag in prev


# Premium 购买入口。本地版本仅 set bool;接 IAP 时由 SDK 回调 set_premium(true)。
# 不直接卖:运营接入时拼 UI + 调 IAP SDK + 校验后调本方法。
func set_premium(b: bool) -> void:
	purchased_premium = b
	_save_to_disk()


# Season 切换:每月 1 日 → 自动 reset xp/claimed,保留 purchased_premium(本季
# 已购的话本季持续,跨季要重新购)。v1 简化:跨季也清 premium,运营可改。
func _ensure_season() -> void:
	var sid: int = _today_season_id()
	if season_id == sid:
		return
	season_id = sid
	season_xp = 0
	claimed = {}
	purchased_premium = false  # 跨季清,简化记账
	_save_to_disk()
	emit_signal("season_changed", sid)


static func _today_season_id() -> int:
	var d: Dictionary = Time.get_date_dict_from_system()
	return int(d.year) * 100 + int(d.month)


static func season_display(sid: int) -> String:
	var year: int = int(sid / 100)
	var month: int = int(sid) % 100
	return "%04d 年 %d 月" % [year, month]


# ---- 持久化 ----

func _load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var raw: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return
	season_id = int(parsed.get("season_id", 0))
	season_xp = int(parsed.get("season_xp", 0))
	purchased_premium = bool(parsed.get("purchased_premium", false))
	var cl = parsed.get("claimed", {})
	if cl is Dictionary:
		# JSON dict keys 是 string,转回 int
		claimed = {}
		for k in cl.keys():
			claimed[int(str(k))] = String(cl[k])


func _save_to_disk() -> void:
	var d: Dictionary = {
		"season_id": season_id,
		"season_xp": season_xp,
		"purchased_premium": purchased_premium,
		"claimed": claimed,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("BattlePass._save_to_disk: cannot write %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
