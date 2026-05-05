class_name IBattleController extends RefCounted

# 麻将王 — M11 Path C 第 1 步：BattleController 接口抽象（spec §4.3 Phase 2 联机扩展点）
#
# 把 v1 的 BattleController 升级为"具体实现继承自 IBattleController"。
# v1 BattleController（本地单机 + 单一权威）保持现状；M12+ 加入
# NetworkedBattleController 时同样 extends IBattleController，让外部代码
# (GameDriver / RunFlow / tests) 只依赖接口而非具体类。
#
# spec §4.3 v1 守约 — "所有对局副作用都通过 _emit + SkillScheduler 处理" — 已
# 由 v1 BattleController 守住，无需在本接口层重申；不存在"绕过总线直接修改
# state"的代码路径。
#
# 本接口只声明公共字段和方法签名（GDScript 没有真正的接口，用 abstract base
# class + push_error 实现）。具体类必须 override run_to_end() / apply_ron()
# 等动作方法。
#
# 不在本接口范围（M12+ 加）：
#   - send_action(action: Action) — 客户端发送给 server
#   - on_server_event(event: NetworkedEvent) — 客户端收到 server 广播
#   - request_authoritative_state() — 客户端请求 state 镜像

# ---- 公共字段（具体类构造时填充） ----

# 战斗状态机数据
var state: BattleState = null
# turn engine: 摸 / 弃 / 鸣 / 立直 / 胡的状态机
var engine: TurnEngine = null
# skill registry: 本局活跃技能
var registry: SkillRegistry = null
# skill scheduler: emit event → trigger hook 调度
var scheduler: SkillScheduler = null
# AI 决策器（玩家联机时 server 端不需要本字段；client 端可保留作占位）
var ai: SimpleAi = null
# 事件 log（NetworkedBattleController 在 commit 时填充）
var events: Array = []

# ---- 公共方法（签名；具体类必须 override） ----

# 主入口 — 跑到流局或胡牌；返 {last_event: StringName, events: Array[BattleEvent]}
func run_to_end() -> Dictionary:
	push_error("IBattleController.run_to_end() 必须被 override")
	return {}

# 玩家声明荣胡（返 true 表示成功；false 表示参数无效或已结算）
func apply_ron(_winner_seat: int, _ron_tile: Tile, _discarder_seat: int, _is_houtei: bool = false) -> bool:
	push_error("IBattleController.apply_ron() 必须被 override")
	return false
