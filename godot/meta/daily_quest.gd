extends Node

# Autoload: DailyQuest — 每日任务系统。每天 3 个固定任务,完成给 gold/renown/
# season_xp 三栏奖励。完成进度从 StatsManager 计数字段累加(对 baseline 算 diff,
# 跟 RunSummary 亮点行同源),不需要单独 hook 战斗事件。
#
# Day 切换 (本地日期变化) → 自动重 roll 任务列表 + 清进度 baseline。
# Persistence: user://daily_quest.json 存 {day_key, quests, claim_state}。
#
# Schema:
#   day_key: int — DailySeed.today_seed() 当 dedup key (年月日)
#   quests: Array[Dictionary] — 当日 3 个任务
#     each: {id: StringName, kind: String, target: int, baseline: int,
#            gold_reward: int, renown_reward: int, season_xp_reward: int,
#            claimed: bool}
#   kind 取 StatsManager.snapshot() 的字段名,如 "hands_won" / "tsumo_count"
#     / "riichi_count" / "yakuman_count" / "ippatsu_count"

const SAVE_PATH: String = "user://daily_quest.json"
const QUEST_COUNT: int = 3

# 任务模板池。每日从 pool 随机抽 3 个 (按 day_key seed 确定性,同一天全服一致)。
# season_xp 累 → BattlePass 战令进度(下个 task 实装)。
const QUEST_POOL: Array = [
	{"id": &"daily_win_3", "kind": "hands_won", "target": 3, "gold": 50, "renown": 5, "xp": 30, "desc": "今日胡 3 次"},
	{"id": &"daily_win_5", "kind": "hands_won", "target": 5, "gold": 80, "renown": 10, "xp": 50, "desc": "今日胡 5 次"},
	{"id": &"daily_tsumo_2", "kind": "tsumo_count", "target": 2, "gold": 40, "renown": 5, "xp": 25, "desc": "今日自摸 2 次"},
	{"id": &"daily_ron_3", "kind": "ron_count", "target": 3, "gold": 50, "renown": 5, "xp": 30, "desc": "今日荣胡 3 次"},
	{"id": &"daily_riichi_5", "kind": "riichi_count", "target": 5, "gold": 60, "renown": 8, "xp": 35, "desc": "今日立直 5 次"},
	{"id": &"daily_ippatsu_1", "kind": "ippatsu_count", "target": 1, "gold": 100, "renown": 15, "xp": 60, "desc": "今日一発命中 1 次"},
	{"id": &"daily_yakuman_1", "kind": "yakuman_count", "target": 1, "gold": 300, "renown": 50, "xp": 200, "desc": "今日役満 1 次"},
	{"id": &"daily_haitei_1", "kind": "haitei_count", "target": 1, "gold": 150, "renown": 25, "xp": 100, "desc": "今日海底/河底 1 次"},
	{"id": &"daily_play_8", "kind": "hands_played", "target": 8, "gold": 30, "renown": 3, "xp": 20, "desc": "今日打 8 局"},
]

signal quests_refreshed
signal quest_claimed(quest_id: StringName, gold: int, renown: int, xp: int)

var day_key: int = 0
var quests: Array = []  # Array[Dictionary]


func _ready() -> void:
	_load_from_disk()
	_ensure_today()


# 调用方:RunFlow / 主菜单 / 设置入口 调用。本方法检测 day_key 变化触发重 roll。
func _ensure_today() -> void:
	var today_key: int = _today_key()
	if day_key != today_key:
		_reroll_for_day(today_key)


func _today_key() -> int:
	var d: Dictionary = Time.get_date_dict_from_system()
	return int(d.year) * 10000 + int(d.month) * 100 + int(d.day)


# Roll 3 个任务用 day_key 作 seed,全服同 seed 同一天任务一致。
func _reroll_for_day(new_day_key: int) -> void:
	day_key = new_day_key
	var rng := RandomNumberGenerator.new()
	rng.seed = new_day_key
	var sm = get_node_or_null("/root/StatsManager")
	var baseline: Dictionary = sm.snapshot() if sm and sm.has_method("snapshot") else {}
	var indices: Array = []
	for i in range(QUEST_POOL.size()):
		indices.append(i)
	# Fisher-Yates 用 seeded RNG 洗牌取前 QUEST_COUNT 个
	for i in range(indices.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = indices[i]
		indices[i] = indices[j]
		indices[j] = tmp
	quests.clear()
	for i in range(min(QUEST_COUNT, indices.size())):
		var tpl: Dictionary = QUEST_POOL[indices[i]]
		quests.append({
			"id": tpl.id,
			"kind": tpl.kind,
			"target": tpl.target,
			"baseline": int(baseline.get(tpl.kind, 0)),
			"gold_reward": tpl.gold,
			"renown_reward": tpl.renown,
			"season_xp_reward": tpl.xp,
			"desc": tpl.desc,
			"claimed": false,
		})
	_save_to_disk()
	emit_signal("quests_refreshed")


# 调用方:任意时候(主菜单/HUD/RunSummary)查询进度。返当前 stats snapshot
# vs quest baseline 的差值,clamp 到 [0, target]。
func progress_for(quest: Dictionary) -> int:
	var sm = get_node_or_null("/root/StatsManager")
	if sm == null or not sm.has_method("snapshot"):
		return 0
	var cur: Dictionary = sm.snapshot()
	var delta: int = int(cur.get(quest.kind, 0)) - int(quest.get("baseline", 0))
	return clampi(delta, 0, int(quest.target))


func is_completed(quest: Dictionary) -> bool:
	return progress_for(quest) >= int(quest.target)


# 玩家点"领取"按钮 → 校验完成 + 未领,加 gold/renown/season_xp,标记 claimed。
# 不直接修 RunState/MetaProgress,emit signal 让调用方按当前上下文决定怎么发
# (run 内加 RunState.gold,run 外只加 MetaProgress.renown)。
func claim(quest_id: StringName) -> bool:
	for q in quests:
		if q.id != quest_id:
			continue
		if q.claimed:
			return false
		if not is_completed(q):
			return false
		q.claimed = true
		_save_to_disk()
		emit_signal("quest_claimed", quest_id,
			int(q.gold_reward), int(q.renown_reward), int(q.season_xp_reward))
		return true
	return false


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
	day_key = int(parsed.get("day_key", 0))
	var qs = parsed.get("quests", [])
	if qs is Array:
		quests = qs


func _save_to_disk() -> void:
	var d: Dictionary = {"day_key": day_key, "quests": quests}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("DailyQuest._save_to_disk: cannot write %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
