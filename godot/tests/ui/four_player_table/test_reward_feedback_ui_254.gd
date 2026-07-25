extends GutTest

# E5-06 / #254：三出口 UI 互斥、ITEM_* 真相源、多实例库存、STT/静默、属性隔离。

const ProjScr = preload("res://ui/four_player_table/reward_feedback_projector.gd")
const TableScr = preload("res://ui/four_player_table/four_player_table.gd")
const ModelScr = preload("res://ui/four_player_table/seat_caption_model.gd")

const ROOM := "room_254"
const WINDOW_ID := "hand_3_window_1"
const WINDOW_NEXT := "hand_3_window_2"
const PRIZE_POOL := ["iron_shield_v1", "wall_peek_v1", "dora_charm_v1", "double_payout_v1"]
const VIEW_HASH := "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
const RULE_VERSION := "trash_talk_rules_v1"


func _env(kind: String, seq: int, payload: Dictionary) -> Dictionary:
	return {
		"protocol_version": 1,
		"server_seq": seq,
		"room_id": ROOM,
		"kind": kind,
		"payload": payload.duplicate(true),
		"view_hash": VIEW_HASH,
	}


func _opened(seq: int = 100) -> Dictionary:
	return _env("REWARD_WINDOW_OPENED", seq, {
		"window_id": WINDOW_ID,
		"hand_seq": 3,
		"window_index": 1,
		"phase": "OPEN",
		"window_exit": null,
		"prize_pool": PRIZE_POOL.duplicate(),
		"rule_version": RULE_VERSION,
	})


func _settled_full(seq: int = 120) -> Dictionary:
	return _env("REWARD_WINDOW_SETTLED", seq, {
		"window_id": WINDOW_ID,
		"outcome": "FULL_GRANT",
		"settle_reason": "FULL_24_NO_WIN",
		"rule_version": RULE_VERSION,
		"assignment_version": "assign_v1",
		"prize_pool": PRIZE_POOL.duplicate(),
		"matrix_summary": {
			"scores": [
				[1000, 0, 0, 0],
				[0, 900, 0, 0],
				[0, 0, 800, 0],
				[0, 0, 0, 700],
			],
		},
		"assignment": {
			"0": "iron_shield_v1",
			"1": "wall_peek_v1",
			"2": "dora_charm_v1",
			"3": "double_payout_v1",
		},
		"closing_boundary_server_seq": 110,
		"context_boundary_server_seq": 118,
		"grace_deadline_at": "2026-07-22T12:00:01.500Z",
		"grant_count": 4,
		"hand_seq": 3,
		"transcript_summary": {},
	})


func _settled_display(seq: int = 120) -> Dictionary:
	var base: Dictionary = _settled_full(seq)
	var p: Dictionary = (base["payload"] as Dictionary).duplicate(true)
	p["outcome"] = "DISPLAY_ONLY"
	p["settle_reason"] = "MATCH_END_NO_WIN"
	p["grant_count"] = 0
	return _env("REWARD_WINDOW_SETTLED", seq, p)


func _cancelled(seq: int = 121) -> Dictionary:
	return _env("REWARD_WINDOW_CANCELLED", seq, {
		"window_id": WINDOW_ID,
		"cancel_reason": "CANCELLED_BY_WIN",
		"closing_boundary_server_seq": 110,
		"grace_aborted": true,
		"scored": false,
		"grant_count": 0,
		"hand_seq": 3,
	})


func _item_granted(
	seat: int = 0,
	item_id: String = "iron_shield_v1",
	iid: String = "ii_a",
	seq: int = 122,
	affinity: bool = false
) -> Dictionary:
	return _env("ITEM_GRANTED", seq, {
		"window_id": WINDOW_ID,
		"rule_version": RULE_VERSION,
		"assignment_version": "assign_v1",
		"matched_rule_ids": ["stable_rule_id"],
		"item_id": item_id,
		"item_instance_id": iid,
		"seat": seat,
		"hand_seq": 3,
		"score": 1000,
		"affinity_match": affinity,
		"armed_for_window_id": WINDOW_NEXT if affinity else null,
	})


func _item_applied(iid: String = "ii_a", item_id: String = "iron_shield_v1", seq: int = 130) -> Dictionary:
	return _env("ITEM_APPLIED", seq, {
		"item_instance_id": iid,
		"item_id": item_id,
		"seat": 0,
		"effect_id": item_id,
		"command_id": "550e8400-e29b-41d4-a716-0000000000c1",
	})


func _item_consumed(iid: String = "ii_a", item_id: String = "iron_shield_v1", seq: int = 131) -> Dictionary:
	return _env("ITEM_CONSUMED", seq, {
		"item_instance_id": iid,
		"item_id": item_id,
		"seat": 0,
		"command_id": "550e8400-e29b-41d4-a716-0000000000c1",
	})


func _match_settled(seq: int = 200) -> Dictionary:
	return _env("MATCH_SETTLED", seq, {
		"round_kind": "EAST",
		"final_scores": [25000, 25000, 25000, 25000],
		"seat_order": [0, 1, 2, 3],
	})


# ── 三出口互斥 ──────────────────────────────────────────

func test_three_exits_mutually_exclusive_messages() -> void:
	var p = ProjScr.new()
	var full: Dictionary = p.project(_settled_full())
	assert_true(bool(full.get("ok", false)), str(full))
	assert_eq(String(full.get("message", "")), "分配完成，等待到账事件")
	assert_eq(String(full.get("feedback_kind", "")), "SETTLED_FULL_GRANT")
	assert_true(full.has("assignment"), "FULL_GRANT 须展示分配")
	assert_false(bool(full.get("inventory_changed", false)), "SETTLED 不得改库存")

	var disp: Dictionary = p.project(_settled_display())
	assert_true(bool(disp.get("ok", false)), str(disp))
	assert_eq(String(disp.get("message", "")), "仅本场统计，未发放")
	assert_eq(String(disp.get("feedback_kind", "")), "SETTLED_DISPLAY_ONLY")
	assert_true(disp.has("assignment"))
	assert_false(bool(disp.get("show_arrival", false)), "DISPLAY_ONLY 不显示到账")

	var can: Dictionary = p.project(_cancelled())
	assert_true(bool(can.get("ok", false)), str(can))
	assert_eq(String(can.get("message", "")), "和牌优先，本窗作废")
	assert_eq(String(can.get("feedback_kind", "")), "CANCELLED_BY_WIN")
	assert_false(can.has("assignment"), "CANCELLED 不得展示分配")
	assert_false(can.has("matrix_summary"), "CANCELLED 不得展示矩阵")
	assert_false(bool(can.get("show_scores", false)))


func test_settled_full_grant_does_not_mutate_inventory() -> void:
	var p = ProjScr.new()
	p.ingest(_opened())
	p.ingest(_settled_full())
	assert_eq(p.inventory_count_for_seat(0), 0, "SETTLED 后库存仍为 0")
	assert_eq(p.local_inventory_instances().size(), 0)
	var banner := String(p.last_feedback_message())
	assert_eq(banner, "分配完成，等待到账事件")
	assert_true(p.has_assignment_display())
	# 仅 ITEM_GRANTED 到账
	p.ingest(_item_granted(0, "iron_shield_v1", "ii_seat0", 122, true))
	assert_eq(p.inventory_count_for_seat(0), 1)
	assert_eq(String(p.last_feedback_message()), "到账")
	assert_true(bool(p.last_feedback().get("show_arrival", false)))


func test_item_applied_feedback_truth_source() -> void:
	var p = ProjScr.new()
	p.ingest(_item_granted(0, "iron_shield_v1", "ii_a", 122, false))
	p.ingest(_item_applied("ii_a", "iron_shield_v1", 130))
	var fb: Dictionary = p.last_feedback()
	assert_eq(String(fb.get("feedback_kind", "")), "ITEM_APPLIED")
	assert_true(String(fb.get("message", "")).contains("发动") \
		or String(fb.get("message", "")).contains("效果"))
	assert_eq(String(fb.get("item_instance_id", "")), "ii_a")


func test_item_consumed_and_match_settled_remove_inventory() -> void:
	var p = ProjScr.new()
	p.ingest(_item_granted(0, "iron_shield_v1", "ii_a", 122, false))
	p.ingest(_item_granted(0, "iron_shield_v1", "ii_b", 123, false))
	assert_eq(p.inventory_count_for_seat(0), 2)
	p.ingest(_item_consumed("ii_a", "iron_shield_v1", 131))
	assert_eq(p.inventory_count_for_seat(0), 1)
	assert_false(p.has_instance("ii_a"))
	assert_true(p.has_instance("ii_b"))
	p.ingest(_match_settled(200))
	assert_eq(p.inventory_count_for_seat(0), 0)
	assert_eq(p.local_inventory_instances().size(), 0)


func test_same_item_id_multi_instance_rows_and_use_target() -> void:
	var p = ProjScr.new()
	p.ingest(_item_granted(0, "iron_shield_v1", "ii_a", 122, false))
	p.ingest(_item_granted(0, "iron_shield_v1", "ii_b", 123, true))
	var rows: Array = p.local_inventory_instances()
	assert_eq(rows.size(), 2)
	var ids: Array = []
	for r in rows:
		ids.append(String(r.get("item_instance_id", "")))
		assert_eq(String(r.get("item_id", "")), "iron_shield_v1")
		assert_true(r.has("status"))
		assert_true(r.has("effect_summary") or r.has("description"))
	assert_true(ids.has("ii_a"))
	assert_true(ids.has("ii_b"))
	# 精确 USE 目标
	assert_eq(String(p.use_target_instance_id("ii_b")), "ii_b")
	assert_eq(String(p.use_target_instance_id("ii_a")), "ii_a")
	assert_eq(String(p.use_target_instance_id("missing")), "")


func test_room_snapshot_restores_full_seat_inventory() -> void:
	var p = ProjScr.new()
	# 先有事件库存
	p.ingest(_item_granted(0, "iron_shield_v1", "ii_old", 122, false))
	assert_eq(p.inventory_count_for_seat(0), 1)
	# ROOM_SNAPSHOT 完整替换本席集合
	var snap_payload := {
		"modules": [
			{
				"module_key": "item_inventory",
				"schema_version": 1,
				"payload": {
					"seat": 0,
					"items": [
						{
							"item_instance_id": "ii_snap_1",
							"item_id": "wall_peek_v1",
							"status": "held",
							"affinity_match": false,
							"armed_for_window_id": null,
						},
						{
							"item_instance_id": "ii_snap_2",
							"item_id": "wall_peek_v1",
							"status": "held",
							"affinity_match": true,
							"armed_for_window_id": WINDOW_NEXT,
						},
						{
							"item_instance_id": "ii_snap_3",
							"item_id": "dora_charm_v1",
							"status": "armed",
							"affinity_match": false,
							"armed_for_window_id": null,
						},
					],
					"active_window_id": null,
					"pending_window_id": null,
				},
			},
			{
				"module_key": "reward_window",
				"schema_version": 1,
				"payload": {
					"phase": "OPEN",
					"window_id": WINDOW_ID,
					"window_exit": null,
					"prize_pool": PRIZE_POOL.duplicate(),
					"discard_count": 7,
					"hand_seq": 3,
					"window_index": 1,
					"rule_version": RULE_VERSION,
				},
			},
		],
	}
	var wire := _env("ROOM_SNAPSHOT", 150, {
		"snapshot_server_seq": 150,
		"next_server_seq": 151,
		"seat_view": 0,
		"modules": snap_payload["modules"],
	})
	# 某些 schema 可能包一层；走 projector 专用 restore API 亦可
	var ok: bool = bool(p.restore_from_snapshot_modules(snap_payload["modules"] as Array))
	assert_true(ok, "snapshot restore 必须成功")
	assert_eq(p.inventory_count_for_seat(0), 3)
	assert_false(p.has_instance("ii_old"), "快照须完整替换而非追加")
	assert_true(p.has_instance("ii_snap_1"))
	assert_true(p.has_instance("ii_snap_2"))
	assert_true(p.has_instance("ii_snap_3"))
	assert_eq(p.discard_progress(), 7)
	assert_eq(p.prize_pool().size(), 4)
	assert_eq(String(wire["kind"]), "ROOM_SNAPSHOT")


func test_prize_pool_four_unique_and_discard_progress() -> void:
	var p = ProjScr.new()
	p.ingest(_opened())
	var pool: Array = p.prize_pool()
	assert_eq(pool.size(), 4)
	var seen := {}
	for id in pool:
		assert_false(seen.has(String(id)), "奖池互不重复")
		seen[String(id)] = true
	assert_eq(p.discard_progress(), 0)
	p.apply_reward_window_view({
		"phase": "OPEN",
		"window_id": WINDOW_ID,
		"prize_pool": PRIZE_POOL.duplicate(),
		"discard_count": 24,
		"window_exit": null,
	})
	assert_eq(p.discard_progress(), 24)
	# HUD 进度文案
	var title: String = String(p.pool_title_text())
	assert_true(title.contains("垃圾话奖池"))
	assert_true(title.contains("24") or title.contains("24/24") or title.contains("24 ·"))


func test_stt_empty_final_vs_silent_seat() -> void:
	var model = ModelScr.new()
	# 终态空文本发言尝试 → 转写失败
	var fail: Dictionary = model.ingest({
		"seat": 0,
		"utterance_id": "utt_fail",
		"text": "",
		"kind": "final",
		"source": "server_stt",
		"lang": "zh",
		"now_ms": 1000,
		"stt_failed": true,
	})
	assert_true(bool(fail.get("ok", false)), str(fail))
	var d0: Dictionary = model.display_for_seat(0)
	assert_true(String(d0.get("text", "")).contains("转写失败") \
		or String(d0.get("text", "")).contains("未计分"))
	assert_true(bool(d0.get("stt_failed", false)))
	assert_false(bool(d0.get("is_reward", false)), "不得伪装发奖")

	# 完全无发言记录 → 静默席
	assert_true(model.is_silent_seat(1))
	assert_false(model.is_silent_seat(0))

	var p = ProjScr.new()
	p.ingest(_settled_full())
	# FULL_GRANT 静默席仍展示稳定分配
	assert_true(p.should_show_assignment_for_seat(1, true))
	p = ProjScr.new()
	p.ingest(_cancelled())
	assert_false(p.should_show_assignment_for_seat(1, true), "CANCELLED 不展示分配")
	assert_false(p.has_assignment_display())


func test_final_ai_affinity_badges_display_only_no_hidden() -> void:
	var model = ModelScr.new()
	# final 中文含关键词 → 属性徽标
	assert_true(bool(model.ingest({
		"seat": 0,
		"utterance_id": "utt_zh",
		"text": "燃烧起来热血立直一发",
		"kind": "final",
		"source": "server_stt",
		"lang": "zh",
		"now_ms": 1000,
		"character_id": "qiu_jue",
	}).get("ok", false)))
	var d0: Dictionary = model.display_for_seat(0)
	var badges: Array = d0.get("affinity_badges", [])
	assert_gt(badges.size(), 0, "final 命中应有属性徽标")
	for b in badges:
		assert_true(String(b) in ["DOMINATION", "CALM", "CUNNING", "PASSION", "MYSTIC"] \
			or String(b) in ["统治", "冷静", "诡诈", "热血", "神秘"])

	# AI 强制 source=ai_text
	var table = TableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var ai: Dictionary = table.inject_ai_caption_display({
		"seat": 2,
		"utterance_id": "ai_1",
		"text": "Quiet. I'm still reading your spine.",
		"language": "en",
		"character_id": "lin_yeche",
		"source": "local_mic",  # 伪装应被覆盖
		"kind": "partial",
	})
	assert_true(bool(ai.get("ok", false)), str(ai))
	var d2: Dictionary = table.caption_overlay.model().display_for_seat(2)
	assert_eq(String(d2.get("source", "")), "ai_text")
	assert_false(bool(d2.get("is_mic", true)))
	# 隐藏信息不得进入徽标计算输入
	assert_false(d2.has("hidden_tiles"))
	assert_false(d2.has("seed"))
	assert_false(d2.has("wall"))


func test_table_hud_and_drawer_integration() -> void:
	var table = TableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame

	assert_not_null(table.get_node_or_null("RewardPoolHud"), "须有奖池 HUD")
	assert_not_null(table.get_node_or_null("ItemInventoryDrawer"), "须有库存抽屉")
	assert_false(table.is_inventory_drawer_open(), "抽屉默认关闭")

	assert_true(bool(table.inject_reward_feedback(_opened()).get("ok", false)))
	var hud = table.get_node("RewardPoolHud")
	assert_true(hud.visible)
	assert_eq(table.prize_pool_display().size(), 4)
	assert_true(String(table.pool_title_text()).contains("垃圾话奖池"))

	assert_true(bool(table.inject_reward_feedback(_settled_full()).get("ok", false)))
	assert_eq(table.reward_feedback_text(), "分配完成，等待到账事件")
	assert_eq(table.inventory_count(), 0, "SETTLED 不改库存")

	assert_true(bool(table.inject_reward_feedback(
		_item_granted(0, "iron_shield_v1", "ii_a", 122, false)).get("ok", false)))
	assert_eq(table.inventory_count(), 1)
	assert_eq(table.reward_feedback_text(), "到账")

	table.open_inventory_drawer()
	assert_true(table.is_inventory_drawer_open())
	var rows: Array = table.inventory_row_ids()
	assert_eq(rows.size(), 1)
	assert_eq(String(rows[0]), "ii_a")

	# 同 ID 第二实例
	assert_true(bool(table.inject_reward_feedback(
		_item_granted(0, "iron_shield_v1", "ii_b", 123, false)).get("ok", false)))
	assert_eq(table.inventory_count(), 2)
	rows = table.inventory_row_ids()
	assert_eq(rows.size(), 2)
	assert_true(rows.has("ii_a"))
	assert_true(rows.has("ii_b"))

	# 滚动容纳大量实例（视图，非权威上限）
	for i in range(20):
		table.inject_reward_feedback(_item_granted(
			0, "wall_peek_v1", "ii_mass_%d" % i, 200 + i, false))
	assert_gte(table.inventory_count(), 22)
	assert_eq(table.inventory_row_ids().size(), table.inventory_count())
	var drawer = table.get_node("ItemInventoryDrawer")
	assert_true(drawer.has_method("scroll_container") or drawer.get_node_or_null("Scroll") != null \
		or drawer.get_node_or_null("ScrollContainer") != null)


func test_cancelled_and_display_only_table_banner() -> void:
	var table = TableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	assert_true(bool(table.inject_reward_feedback(_settled_display()).get("ok", false)))
	assert_eq(table.reward_feedback_text(), "仅本场统计，未发放")
	assert_eq(table.inventory_count(), 0)
	assert_true(bool(table.inject_reward_feedback(_cancelled()).get("ok", false)))
	assert_eq(table.reward_feedback_text(), "和牌优先，本窗作废")
	assert_false(table.has_assignment_display())
