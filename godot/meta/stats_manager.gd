extends Node

# StatsManager - autoload 单例,记录终身游戏统计 + 成就解锁。
# 与 SettingsManager（用户偏好）分离，专门持久化麻将对局统计。
#
# 存储:user://stats.json
#
# 调用流:
#   - PlayableTable 在事件流上调 record_win / record_hand_end
#   - UI 通过 stats[<key>] 读 + check_achievements() 取新解锁列表
#
# 成就 (AchievementId):字符串 id,定义于 ACHIEVEMENTS 字典。

const STATS_PATH: String = "user://stats.json"

# 终身统计字段(全 int / float,JSON 友好)
var hands_played: int = 0
var hands_won: int = 0
var hands_lost_by_deal_in: int = 0   # 玩家被自家放铳
var tsumo_count: int = 0             # 自摸数
var ron_count: int = 0               # 荣胡数(我胡别人)
var yakuman_count: int = 0           # 役満次数(任意倍)
var double_yakuman_count: int = 0    # 双役満次数
var riichi_count: int = 0            # 玩家立直次数
var double_riichi_count: int = 0
var ippatsu_count: int = 0           # 一発命中
var haitei_count: int = 0            # 海底/河底捞月命中
var rinshan_count: int = 0           # 岭上开花命中
var highest_single_hand_score: int = 0   # 单局最高得分
var total_points_won: int = 0            # 终身累计胡得分

# 已解锁 achievement id 集合(string)。Set 由 Dictionary key 模拟。
var unlocked_achievements: Dictionary = {}

signal achievement_unlocked(achievement_id: String, meta: Dictionary)


# ---- Achievement 定义 ----
# 每个成就:id → {name, desc, predicate(self) -> bool}
# 增加成就只需在此字典里加条目,无需改 record_* 路径。
const ACHIEVEMENTS: Dictionary = {
	"first_win": {"name": "首胡", "desc": "第一次胡牌"},
	"hundred_wins": {"name": "百胡练习", "desc": "终身胡牌满 100"},
	"first_tsumo": {"name": "首次自摸", "desc": "第一次自摸"},
	"first_ron": {"name": "首次荣和", "desc": "第一次荣胡"},
	"first_yakuman": {"name": "役満达成", "desc": "终身首役満"},
	"yakuman_master": {"name": "役満达人", "desc": "终身 10 次役満"},
	"double_yakuman": {"name": "双倍役満", "desc": "首次双倍役満(国士13面/纯正九莲等)"},
	"first_riichi": {"name": "首次立直", "desc": "玩家第一次立直"},
	"double_riichi": {"name": "ダブル立直", "desc": "首次第一巡双立直"},
	"first_ippatsu": {"name": "一発命中", "desc": "首次立直一発内胡"},
	"first_haitei": {"name": "海底渔人", "desc": "首次海底/河底捞月"},
	"first_rinshan": {"name": "岭上开花", "desc": "首次岭上开花"},
	"score_18000": {"name": "倍満收割", "desc": "单局得分 ≥ 18000"},
	"score_32000": {"name": "役満收割", "desc": "单局得分 ≥ 32000"},
}


func _ready() -> void:
	_load_from_disk()


# ---- 记录入口（由 PlayableTable 调用）----

# 一局结束时调一次。win_event 可为 null(流局)。is_player_winner = 玩家胡牌。
# loser_was_player = 玩家放铳。
func record_hand_end(win_event, is_player_winner: bool = false, loser_was_player: bool = false) -> void:
	hands_played += 1
	if win_event != null:
		hands_won += 1
		var yakuman_mul: int = int(win_event.extra.get("yakuman_multiplier", 0))
		if yakuman_mul >= 1:
			yakuman_count += 1
		if yakuman_mul >= 2:
			double_yakuman_count += 1
		var winner_total: int = int(win_event.extra.get("winner_total", 0))
		if is_player_winner:
			if winner_total > highest_single_hand_score:
				highest_single_hand_score = winner_total
			total_points_won += winner_total
		# 自摸 / 荣胡区分:看 extra 是否有 discarder_seat(荣胡)
		if int(win_event.extra.get("discarder_seat", -1)) >= 0:
			ron_count += 1
		else:
			tsumo_count += 1
		# yaku_names 里命中的特殊役
		var yaku_names: Array = win_event.extra.get("yaku_names", [])
		for item in yaku_names:
			if not (item is Dictionary):
				continue
			var nm: String = String(item.get("name", ""))
			match nm:
				"一発":
					ippatsu_count += 1
				"海底摸月", "海底捞月":
					haitei_count += 1
				"河底捞鱼", "河底摸鱼":
					haitei_count += 1
				"岭上开花":
					rinshan_count += 1
	if loser_was_player:
		hands_lost_by_deal_in += 1
	_check_and_emit_achievements()
	_save_to_disk()


func record_riichi(is_double: bool = false) -> void:
	riichi_count += 1
	if is_double:
		double_riichi_count += 1
	_check_and_emit_achievements()
	_save_to_disk()


# 返回当前所有计数字段的快照。
func snapshot() -> Dictionary:
	return {
		"hands_played": hands_played,
		"hands_won": hands_won,
		"hands_lost_by_deal_in": hands_lost_by_deal_in,
		"tsumo_count": tsumo_count,
		"ron_count": ron_count,
		"yakuman_count": yakuman_count,
		"double_yakuman_count": double_yakuman_count,
		"riichi_count": riichi_count,
		"ippatsu_count": ippatsu_count,
		"haitei_count": haitei_count,
		"rinshan_count": rinshan_count,
	}


# snapshot 跟 baseline 的差值（每个 key 的当前值减基线值）。
func diff_from(baseline: Dictionary) -> Dictionary:
	var cur := snapshot()
	var d: Dictionary = {}
	for k in cur.keys():
		d[k] = int(cur[k]) - int(baseline.get(k, 0))
	return d


# ---- 成就检测 ----

# 扫所有未解锁成就,看是否达成 → emit + mark unlocked。
func _check_and_emit_achievements() -> void:
	for id in ACHIEVEMENTS.keys():
		if unlocked_achievements.has(id):
			continue
		if _achievement_satisfied(id):
			unlocked_achievements[id] = true
			achievement_unlocked.emit(id, ACHIEVEMENTS[id])


func _achievement_satisfied(id: String) -> bool:
	match id:
		"first_win": return hands_won >= 1
		"hundred_wins": return hands_won >= 100
		"first_tsumo": return tsumo_count >= 1
		"first_ron": return ron_count >= 1
		"first_yakuman": return yakuman_count >= 1
		"yakuman_master": return yakuman_count >= 10
		"double_yakuman": return double_yakuman_count >= 1
		"first_riichi": return riichi_count >= 1
		"double_riichi": return double_riichi_count >= 1
		"first_ippatsu": return ippatsu_count >= 1
		"first_haitei": return haitei_count >= 1
		"first_rinshan": return rinshan_count >= 1
		"score_18000": return highest_single_hand_score >= 18000
		"score_32000": return highest_single_hand_score >= 32000
	return false


# ---- 序列化 ----

func _load_from_disk() -> void:
	if not FileAccess.file_exists(STATS_PATH):
		return
	var file := FileAccess.open(STATS_PATH, FileAccess.READ)
	if file == null:
		return
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	hands_played = int(parsed.get("hands_played", 0))
	hands_won = int(parsed.get("hands_won", 0))
	hands_lost_by_deal_in = int(parsed.get("hands_lost_by_deal_in", 0))
	tsumo_count = int(parsed.get("tsumo_count", 0))
	ron_count = int(parsed.get("ron_count", 0))
	yakuman_count = int(parsed.get("yakuman_count", 0))
	double_yakuman_count = int(parsed.get("double_yakuman_count", 0))
	riichi_count = int(parsed.get("riichi_count", 0))
	double_riichi_count = int(parsed.get("double_riichi_count", 0))
	ippatsu_count = int(parsed.get("ippatsu_count", 0))
	haitei_count = int(parsed.get("haitei_count", 0))
	rinshan_count = int(parsed.get("rinshan_count", 0))
	highest_single_hand_score = int(parsed.get("highest_single_hand_score", 0))
	total_points_won = int(parsed.get("total_points_won", 0))
	var ach = parsed.get("unlocked_achievements", {})
	if ach is Dictionary:
		unlocked_achievements = ach.duplicate()


func _save_to_disk() -> void:
	var d: Dictionary = {
		"hands_played": hands_played,
		"hands_won": hands_won,
		"hands_lost_by_deal_in": hands_lost_by_deal_in,
		"tsumo_count": tsumo_count,
		"ron_count": ron_count,
		"yakuman_count": yakuman_count,
		"double_yakuman_count": double_yakuman_count,
		"riichi_count": riichi_count,
		"double_riichi_count": double_riichi_count,
		"ippatsu_count": ippatsu_count,
		"haitei_count": haitei_count,
		"rinshan_count": rinshan_count,
		"highest_single_hand_score": highest_single_hand_score,
		"total_points_won": total_points_won,
		"unlocked_achievements": unlocked_achievements,
	}
	var file := FileAccess.open(STATS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("StatsManager._save_to_disk: can't open %s" % STATS_PATH)
		return
	file.store_string(JSON.stringify(d, "\t"))
	file.close()
