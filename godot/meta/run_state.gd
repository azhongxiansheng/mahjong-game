class_name RunState extends RefCounted

# 麻将王 — 里程碑 4 第 1 步：Run 级状态对象（plan-4 D1）
#
# 持单 Run 内跨节点状态：hp / gold / chapter / map / history / deck / seed。
# 与 battle/game_driver.gd（GameDriver，跨"东风战内多局"）显式分层：
#   - GameDriver 只活到节点（一场东风战）结束，由本类按需 new
#   - RunState 跨整个 Run（章 1-章 3）；杀进程则丢失（M5 SaveSystem 实装持久化）

const STARTING_HP: int = 5
const MAX_CHAPTERS: int = 3

# 三个生命周期信号
signal node_completed(next_options: Array)  # next_options: Array[NodeRef]，UI 拉下层选项
signal run_failed                            # hp ≤ 0
signal run_won                               # 通关章 3 Boss

# ---- state ----
var hp: int = STARTING_HP
var max_hp: int = STARTING_HP
var gold: int = 0
var chapter: int = 1                       # 1..MAX_CHAPTERS
var run_seed: int = 0
var current_map: ChapterMap = null
var history: Array = []                    # Array[NodeRef]，已访问节点
var deck: Dictionary = {}                  # 起始包 + 后续抽卡（M5 第 1 步起为
                                            # 单纯持 starter_pack 数据；具体卡片
                                            # 加进 player_deck 字段）
var player_deck: Deck = null               # M5 第 3 步：实际玩家卡组（节点抽
                                            # 卡 / 商店购买 / 卡包打开都加到这）
var pity_state: PityState = null           # M5 第 3 步：跨 Run 抽卡保底
var consumables: Array = []
var finished: bool = false
var won: bool = false

func _init(p_seed: int = 0) -> void:
	run_seed = p_seed
	player_deck = Deck.new()
	pity_state = PityState.new()
	_generate_chapter_map(1)

# ---- public API ----

# 选择并推进到下层节点。返 true 表示推进成功（node_index 在 next_options 内）。
func choose_next_node(node_index: int) -> bool:
	if current_map == null or finished:
		return false
	return current_map.advance_to(node_index)

# 节点结束时调用，应用 hp_delta + gold_reward + 推进 / 失败 / 通关判定。
# - 战斗节点：外部跑完 GameDriver → NodeResult.new(rank, final_scores)
# - 占位节点：NodeResult.from_placeholder()
func complete_node(result: NodeResult) -> void:
	if finished:
		return
	hp = clampi(hp + result.hp_delta, 0, max_hp)
	gold += result.gold_reward
	var current_ref: NodeRef = current_node_ref()
	if current_ref:
		history.append(current_ref)

	# 失败：hp 归零
	if hp <= 0:
		finished = true
		won = false
		emit_signal("run_failed")
		return

	# 在 Boss 节点结束：本章过关，推进或通关
	if current_map.is_at_boss():
		if chapter >= MAX_CHAPTERS:
			finished = true
			won = true
			emit_signal("run_won")
			return
		_generate_chapter_map(chapter + 1)
		emit_signal("node_completed", next_node_options())
		return

	emit_signal("node_completed", next_node_options())

func next_node_options() -> Array:
	if current_map == null:
		return []
	var indices: Array = current_map.next_options()
	var refs: Array = []
	for i in indices:
		refs.append(current_map.nodes[i])
	return refs

func current_node_ref() -> NodeRef:
	if current_map == null or current_map.current_node < 0:
		return null
	return current_map.nodes[current_map.current_node]

# ---- internal ----

func _generate_chapter_map(chapter_index: int) -> void:
	chapter = chapter_index
	var config: Dictionary = ChapterConfig.get_chapter(chapter_index)
	var seed: int = run_seed * 1000 + chapter_index
	current_map = ChapterMapGenerator.generate(config, seed)

# ---- 序列化（M5 SaveSystem） ----

const SAVE_VERSION: int = 1

func to_dict() -> Dictionary:
	var history_dicts: Array = []
	for h in history:
		history_dicts.append(h.to_dict())
	return {
		"version": SAVE_VERSION,
		"hp": hp,
		"max_hp": max_hp,
		"gold": gold,
		"chapter": chapter,
		"run_seed": run_seed,
		"current_map": _serialize_current_map(),
		"history": history_dicts,
		"deck": deck.duplicate(true),
		"player_deck": player_deck.to_dict() if player_deck else {},
		"pity_state": pity_state.to_dict() if pity_state else {},
		"consumables": consumables.duplicate(),
		"finished": finished,
		"won": won,
	}

# Helper：避开 ternary "Values not mutually compatible" warning
# （GDScript 4 严格类型推断，{} vs null 在 ternary 上下文中要显式 helper）。
func _serialize_current_map() -> Variant:
	if current_map == null:
		return null
	return current_map.to_dict()

# 反序列化：调用方需自行处理 version 兼容（v1 不支持迁移；非 v1 返 null）。
static func from_dict(d: Dictionary) -> RunState:
	if d == null or d.is_empty():
		return null
	if int(d.get("version", 0)) != SAVE_VERSION:
		return null  # 版本不匹配；M7 加迁移逻辑
	var rs := RunState.new(int(d.get("run_seed", 0)))
	rs.hp = int(d.get("hp", STARTING_HP))
	rs.max_hp = int(d.get("max_hp", STARTING_HP))
	rs.gold = int(d.get("gold", 0))
	rs.chapter = int(d.get("chapter", 1))
	# current_map 从 dict 恢复；不再走 _generate_chapter_map（避免覆盖 advance_to 后的状态）
	var map_dict = d.get("current_map")
	if map_dict != null and not (map_dict is Dictionary and map_dict.is_empty()):
		rs.current_map = ChapterMap.from_dict(map_dict)
	for hd in d.get("history", []):
		var n := NodeRef.from_dict(hd)
		if n:
			rs.history.append(n)
	rs.deck = d.get("deck", {}).duplicate(true)
	rs.player_deck = Deck.from_dict(d.get("player_deck", {}))
	rs.pity_state = PityState.from_dict(d.get("pity_state", {}))
	rs.consumables = d.get("consumables", []).duplicate()
	rs.finished = bool(d.get("finished", false))
	rs.won = bool(d.get("won", false))
	return rs
