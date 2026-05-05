extends GutTest

# 麻将王 — M11 Path C 第 1 步：IBattleController 接口抽象单测
#
# 验证：
# - BattleController IS-A IBattleController（spec §4.3 抽象）
# - GameDriver / 各 caller 仍能正常创建 BattleController（向后兼容）
# - IBattleController 默认 run_to_end / apply_ron 推 push_error（必须 override）

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

func test_i_base_run_to_end_pushes_error():
	# IBattleController 直接 .new() 调 run_to_end 应推 push_error
	# （GUT 不能直接捕 push_error，但可验证返空 Dictionary）
	var ibase := IBattleController.new()
	var result: Dictionary = ibase.run_to_end()
	assert_eq(result.size(), 0, "未 override 的 run_to_end 返空 dict")

func test_i_base_apply_ron_returns_false():
	var ibase := IBattleController.new()
	# 用 null 占位（仅验证 default 推错路径）
	var ok: bool = ibase.apply_ron(0, null, 1, false)
	assert_false(ok, "未 override 的 apply_ron 返 false")

func test_typed_signature_with_i_battle_controller():
	# 验证 caller 能用 IBattleController 类型 hold BattleController 实例
	var bc: IBattleController = BattleController.new(42, 0)
	assert_not_null(bc.state, "通过 IBattleController 类型访问 state")
	assert_not_null(bc.engine)
	# duck typing：方法调用走子类 override
	assert_true(bc.run_to_end() is Dictionary, "通过基类引用调子类 run_to_end")
