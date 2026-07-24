extends GutTest

# 麻将王 — M11 Path C 第 1 步：IBattleController 接口抽象单测
#
# 验证：
# - BattleController IS-A IBattleController（spec §4.3 抽象）
# - GameDriver / 各 caller 仍能正常创建 BattleController（向后兼容）
# - 真实 BattleController facade：run_to_end / 类型引用行为
#
# E2-02：IBattleController 仅为轻量 marker；run_to_end / apply_action 在
# IAuthoritativeBattleController。不再测试 IBattleController 上不存在的
# default apply_ron / run_to_end 接口。

func test_battle_controller_is_i_battle_controller():
	# class hierarchy assertion — BattleController extends IBattleController
	var bc := BattleController.new(42, 0)
	assert_true(bc is IBattleController, "BattleController extends IBattleController")
	# 公共字段从基类继承
	assert_not_null(bc.state, "state 非空")
	assert_not_null(bc.engine, "engine 非空")
	assert_not_null(bc.registry, "registry 非空")
	assert_not_null(bc.scheduler, "scheduler 非空")
	assert_not_null(bc.ai, "ai 非空")
	# events 在构造后是空 list
	assert_eq(bc.events.size(), 0, "构造后 events 为空")


func test_run_to_end_returns_dict():
	# 跑通一局，确认 run_to_end 返回 Dictionary 形态
	var bc := BattleController.new(42, 0, true)
	var result: Dictionary = bc.run_to_end()
	assert_true(result.has("last_event"), "result 含 last_event")
	assert_true(result.has("events"), "result 含 events")
	assert_true(result.events is Array, "events 是 Array")


func test_typed_signature_with_i_battle_controller():
	# 验证 caller 能用 IBattleController 类型 hold BattleController 实例
	var bc: IBattleController = BattleController.new(42, 0)
	assert_not_null(bc.state, "通过 IBattleController 类型访问 state")
	assert_not_null(bc.engine)
	# duck typing：方法调用走子类 override（IAuthoritative facade）
	assert_true(bc is IAuthoritativeBattleController,
		"BattleController 亦为 IAuthoritativeBattleController")
	var auth: IAuthoritativeBattleController = bc as IAuthoritativeBattleController
	assert_true(auth.run_to_end() is Dictionary, "通过权威 facade 调 run_to_end")
