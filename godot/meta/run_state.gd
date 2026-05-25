class_name RunState extends RefCounted

# 麻将王 — 里程碑 4 第 1 步：Run 级状态对象（plan-4 D1）
#
# 持单 Run 内跨节点状态：hp / gold / chapter / map / history / deck / seed。
# 与 battle/game_driver.gd（GameDriver，跨"东风战内多局"）显式分层：
#   - GameDriver 只活到节点（一场东风战）结束，由本类按需 new
#   - RunState 跨整个 Run（章 1-章 3）；杀进程则丢失（M5 SaveSystem 实装持久化）

const MAX_CHAPTERS: int = 3

# 三个生命周期信号
signal node_completed(next_options: Array)  # next_options: Array[NodeRef]，UI 拉下层选项
signal run_failed                            # hp ≤ 0
signal run_won                               # 通关章 3 Boss

# ---- state ----
# M7 tune-3：从 BalanceConstants 取 starting_hp（之前 hardcode 5；类似 #69
# 修 NodeResult 的 single source）
var hp: int = int(BalanceConstants.lookup(&"starting_hp"))
var max_hp: int = int(BalanceConstants.lookup(&"max_hp"))
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
var relics: Array = []
var selected_character_id: StringName = &""
var difficulty: int = Difficulty.Level.NORMAL
var finished: bool = false
var won: bool = false
# 速战连击:speed 节点连续 rank=1 的次数。≥2 时第 2+ 次给 200% gold 奖励,
# 补偿 speed mode 砍掉的"完整东风战故事感"。在速战短局里追求连击 → 类似
# Slay the Spire combo / Hades 节奏奖励,玩家有"压力下持续高手感"的爽点。
# 任何 rank>1 或非 speed 节点都清零(打破连击)。
var speed_streak: int = 0
# 上一次拿到的 streak bonus gold 金额,UI 显示 toast 用。-1 = 本次未触发。
var last_speed_streak_bonus: int = 0

func _init(p_seed: int = 0) -> void:
	run_seed = p_seed
	player_deck = Deck.new()
	pity_state = PityState.new()
	_generate_chapter_map(1)

# ---- consumables API ----

const MAX_CONSUMABLES: int = 5
const MAX_RELICS: int = 5

func add_consumable(item: ConsumableItem) -> bool:
	if item == null or consumables.size() >= MAX_CONSUMABLES:
		return false
	consumables.append(item)
	return true

func remove_consumable(item_id: StringName) -> bool:
	for i in range(consumables.size()):
		if consumables[i].id == item_id:
			consumables.remove_at(i)
			return true
	return false

func has_consumable(item_id: StringName) -> bool:
	for c in consumables:
		if c.id == item_id:
			return true
	return false

func consumable_count() -> int:
	return consumables.size()

func use_run_consumable(item_id: StringName) -> bool:
	for i in range(consumables.size()):
		var c: ConsumableItem = consumables[i]
		if c.id == item_id and c.is_run():
			consumables.remove_at(i)
			_apply_run_consumable(c)
			return true
	return false

func _apply_run_consumable(item: ConsumableItem) -> void:
	match item.id:
		&"hp_potion_v1":
			hp = clampi(hp + 1, 0, max_hp)
		&"gold_doubler_v1":
			gold += 500

# ---- relics API ----

func add_relic(item: RelicItem) -> bool:
	if item == null or relics.size() >= MAX_RELICS:
		return false
	for r in relics:
		if r.id == item.id:
			return false
	relics.append(item)
	return true

func has_relic(item_id: StringName) -> bool:
	for r in relics:
		if r.id == item_id:
			return true
	return false

func relic_count() -> int:
	return relics.size()

func relic_ids() -> Array:
	var ids: Array = []
	for r in relics:
		ids.append(r.id)
	return ids

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
	# 速战连击:speed 节点 rank=1 累计 streak,第 2 连胡起每次额外 +200% gold。
	# 公式: bonus = gold_reward * 2 when streak >= 2 (streak=1 没奖励,2 给 +200%
	# 即总 3x,3 给 4x,...)。任何 rank>1 或非 speed 节点都清零。
	last_speed_streak_bonus = 0
	if result.session_kind == "speed" and result.rank == 1:
		speed_streak += 1
		if speed_streak >= 2:
			var bonus: int = result.gold_reward * 2
			gold += bonus
			last_speed_streak_bonus = bonus
	else:
		speed_streak = 0
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

# v1 → v2 (M8): NodeRef 加 session_kind 字段。
# Migration: NodeRef.from_dict 缺字段时默认 "east_round"，所以 v1 无业务字段
# 改动 — 只需 from_dict 接受 version=1。
const SAVE_VERSION: int = 2

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
		"consumables": _serialize_consumables(),
		"relics": _serialize_relics(),
		"selected_character_id": String(selected_character_id),
		"difficulty": difficulty,
		"finished": finished,
		"won": won,
		"speed_streak": speed_streak,
	}

# Helper：避开 ternary "Values not mutually compatible" warning
# （GDScript 4 严格类型推断，{} vs null 在 ternary 上下文中要显式 helper）。
func _serialize_relics() -> Array:
	var result: Array = []
	for r in relics:
		if r is RelicItem:
			result.append(r.to_dict())
	return result

func _serialize_consumables() -> Array:
	var result: Array = []
	for c in consumables:
		if c is ConsumableItem:
			result.append(c.to_dict())
		else:
			result.append(c)
	return result

func _serialize_current_map() -> Variant:
	if current_map == null:
		return null
	return current_map.to_dict()

# 反序列化：M8 起接受 v1（迁移）+ v2；未来版本返 null。
# v1 → v2 迁移：NodeRef.from_dict 自身处理缺 session_kind 字段（默认 east_round），
# 所以这里只需放行 v1。未来 v2 → v3 时本函数加显式 _migrate_v2_to_v3 步骤。
static func from_dict(d: Dictionary) -> RunState:
	if d == null or d.is_empty():
		return null
	var version: int = int(d.get("version", 0))
	if version != 1 and version != SAVE_VERSION:
		return null  # 未知版本（含未来版本）安全返 null
	var rs := RunState.new(int(d.get("run_seed", 0)))
	rs.hp = int(d.get("hp", BalanceConstants.lookup(&"starting_hp")))
	rs.max_hp = int(d.get("max_hp", BalanceConstants.lookup(&"max_hp")))
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
	for cd in d.get("consumables", []):
		if cd is Dictionary:
			var ci := ConsumableItem.from_dict(cd)
			if ci:
				rs.consumables.append(ci)
		else:
			rs.consumables.append(cd)
	for rd in d.get("relics", []):
		if rd is Dictionary:
			var ri := RelicItem.from_dict(rd)
			if ri:
				rs.relics.append(ri)
	rs.selected_character_id = StringName(d.get("selected_character_id", ""))
	rs.difficulty = int(d.get("difficulty", Difficulty.Level.NORMAL))
	rs.finished = bool(d.get("finished", false))
	rs.won = bool(d.get("won", false))
	# v1 存档没 speed_streak,默认 0 (= 重启从零开始连击,不破坏既有存档)
	rs.speed_streak = int(d.get("speed_streak", 0))
	return rs
