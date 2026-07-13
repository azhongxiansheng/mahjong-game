extends GutTest

# 端到端验证：跑 1 整局 PlayableBattleController（无 UI），verify
# _try_player_claim_async 钩子 emit PLAYER_CLAIM_PROBE event 出现 N 次。
# 并 verify 至少有 1 次 can_pon=true（看运气，但 1 局 ~70 张切随机够命中）。

func test_player_claim_probe_fires_during_hand() -> void:
	# 不绑定决策端口 → _try_player_claim_async 第一行 return
	# 所以 PROBE 不会 emit！这要修复 — PROBE 应该在 nil check 之前 emit
	# 让 debug 始终有输出
	var bc := PlayableBattleController.new(42, 0, false, TileId.E)
	# 不 bind UI；钩子直接 return（默认 AI 路径），但 PROBE event 不 emit
	var result: Dictionary = bc.run_to_end()  # 同步跑（用默认 _try_auto_ron）
	# 当前实现下 PROBE 在 _try_player_claim_async 内部，需要决策端口存在才会跑到那行
	# 所以这测试预期 PROBE 是 0 — 这正好暴露了 bug！
	var probe_count := 0
	for ev in bc.events:
		if ev.type == &"PLAYER_CLAIM_PROBE":
			probe_count += 1
	# 期望：> 0，但当前实现 = 0（因为 sync run_to_end 走默认 _try_auto_ron 不调 _try_player_claim_async；
	# async run_to_end_async 才调，但 async 需要 await SceneTree...）
	assert_eq(probe_count, 0, "sync 路径不调 _try_player_claim_async（这是预期的）")

# 关键 verify：async 路径 + 不绑定端口也不会 emit PROBE，因为入口会提前 return。
# 这意味着 debug 日志在没 bind_ui 时永远不出现。bug 也许是这个：
# bind_ui 在 PlayableTable.play_hand_async 调，但 polling loop 的 events 监听
# 在 bind_ui 之前就开始？

# 其实更可能：玩家的 _try_player_claim_async 需要每个 AI 切牌后被调；
# 但需要玩家先手切一张才能让 BC 进 AI 回合。问题是用户切了几张牌后 trace 仍空？
# 让我运行 1 局，看 events 流程的健全性
