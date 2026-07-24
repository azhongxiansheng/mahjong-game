class_name IAuthoritativeBattleController extends IBattleController

# 麻将王 — E2-02：本地权威控制器契约。
# BattleController / PlayableBattleController / GameDriver 本地路径依赖本接口。
# NetworkedBattleController 不得继承本类。
#
# 公开 API 仅在此声明 facade，并转调 protected implementation。
# BattleController 只覆写 _impl_*，从而 get_script_method_list 各层各只有一份公开入口。
# 无公开 apply_ron：荣和只能走 Action.ron → apply_action。

var state: BattleState = null
var engine: TurnEngine = null
var registry: SkillRegistry = null
var scheduler: SkillScheduler = null
var ai: SimpleAi = null
var events: Array = []


func run_to_end() -> Dictionary:
	return _impl_run_to_end()


func apply_action(action: Action, source: StringName = ActionSource.HUMAN) -> ActionResolution:
	return _impl_apply_action(action, source)


func decision_context_for_seat(seat: int) -> DecisionContext:
	return _impl_decision_context_for_seat(seat)


func action_journal() -> Array:
	return _impl_action_journal()


func load_replay_journal(raw: Variant) -> bool:
	return _impl_load_replay_journal(raw)


func replay_status() -> StringName:
	return _impl_replay_status()


## Server-draw 领域推进：仅合法 DRAW 且未 settle 时推进一拍。
## true = 正常摸牌或荒牌 settle 等已成功领域推进；false = 未推进。
func progress_server_draw() -> bool:
	return _impl_progress_server_draw()


# ---- protected implementation（子类覆写） ----

func _impl_run_to_end() -> Dictionary:
	push_error("IAuthoritativeBattleController._impl_run_to_end() 必须被 override")
	return {}


func _impl_apply_action(_action: Action, _source: StringName) -> ActionResolution:
	push_error("IAuthoritativeBattleController._impl_apply_action() 必须被 override")
	return ActionResolution.rejected(ActionResolution.INVALID_ACTION)


func _impl_decision_context_for_seat(_seat: int) -> DecisionContext:
	push_error("IAuthoritativeBattleController._impl_decision_context_for_seat() 必须被 override")
	return null


func _impl_action_journal() -> Array:
	push_error("IAuthoritativeBattleController._impl_action_journal() 必须被 override")
	return []


func _impl_load_replay_journal(_raw: Variant) -> bool:
	push_error("IAuthoritativeBattleController._impl_load_replay_journal() 必须被 override")
	return false


func _impl_replay_status() -> StringName:
	push_error("IAuthoritativeBattleController._impl_replay_status() 必须被 override")
	return &"IDLE"


func _impl_progress_server_draw() -> bool:
	push_error("IAuthoritativeBattleController._impl_progress_server_draw() 必须被 override")
	return false
