class_name TableState

# ARCH-CORE #399：core/ 拥有的纯对局状态。
# 只承载 TurnEngine / 日麻规则运行一局所需的权威字段；
# 技能框架、Momentum 等对战运行时字段由 battle/ 的 BattleState 继承扩展。
# 本类不含工厂 —— 发牌/洗墙等一局装配逻辑仍由 BattleState.for_east_round 负责。

var seats: Array = []                  # Array[Seat] 长度 4
var wall: Wall                         # 含 dead_wall 切片
var dora_indicators: DoraIndicators
var dealer_seat: int = 0               # 庄家 seat_id（一局内不变）
var current_seat: int = 0
var phase: int = BattlePhase.Kind.DRAW
var round_wind: int = TileId.E         # 东风战恒为东
var hand_number: int = 1               # 1..4 (东 1..东 4)
var honba: int = 0
var riichi_sticks: int = 0
# E2-02 / #232：局序号命名空间；Wall 用 hand_seq*136+serial 分配 instance_id
var hand_seq: int = 0

# 0e 巡数 / 第一巡
var turn_count: int = 0
var first_round_active: bool = true
