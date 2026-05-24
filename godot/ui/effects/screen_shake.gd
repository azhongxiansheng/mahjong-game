class_name ScreenShake extends RefCounted

# 屏幕震动 — 对目标 Control / Node2D 的 position 加随机 offset,Tween 衰减归零。
# RefCounted 而非 Node,持有者(PlayableTable)负责管 lifetime。
#
# 用法:
#   var shake := ScreenShake.new(self, 8.0, 0.3)  # target / 强度 / 持续秒
#   shake.start()
#
# 强度按 tier 推荐:
#   LIGHT=4 / MEDIUM=8 / HEAVY=14 / YAKUMAN=22
#   持续秒按 tier:0.15 / 0.25 / 0.35 / 0.5

const TIER_INTENSITY: Dictionary = {
	WinBurst.Tier.LIGHT: 4.0,
	WinBurst.Tier.MEDIUM: 8.0,
	WinBurst.Tier.HEAVY: 14.0,
	WinBurst.Tier.YAKUMAN: 22.0,
}

const TIER_DURATION: Dictionary = {
	WinBurst.Tier.LIGHT: 0.15,
	WinBurst.Tier.MEDIUM: 0.25,
	WinBurst.Tier.HEAVY: 0.35,
	WinBurst.Tier.YAKUMAN: 0.5,
}

var _target: CanvasItem
var _intensity: float
var _duration: float
var _original_position: Vector2

# 按 tier 构造的便利 ctor
static func for_tier(target: CanvasItem, tier: int) -> ScreenShake:
	var i: float = float(TIER_INTENSITY.get(tier, 4.0))
	var d: float = float(TIER_DURATION.get(tier, 0.15))
	return ScreenShake.new(target, i, d)


func _init(target: CanvasItem, intensity: float, duration: float) -> void:
	_target = target
	_intensity = intensity
	_duration = duration
	_original_position = Vector2.ZERO  # 在 start() 内确定


# 立刻开始震动。Tween 取 target.get_tree() 创建。
func start() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	_original_position = _target_position()

	var tree := _target.get_tree() if _target.has_method("get_tree") else null
	if tree == null:
		return
	var tween := tree.create_tween()
	# 把 duration 划成 ~10 段 keyframe,每段一个随机 offset,逐段衰减
	var segments: int = max(6, int(_duration * 30))  # ~30 Hz
	var seg_time: float = _duration / segments
	for i in range(segments):
		var decay: float = 1.0 - float(i) / segments
		var ox: float = randf_range(-_intensity, _intensity) * decay
		var oy: float = randf_range(-_intensity, _intensity) * decay
		var target_pos := _original_position + Vector2(ox, oy)
		_tween_position(tween, target_pos, seg_time)
	# 收尾:回原点
	_tween_position(tween, _original_position, seg_time * 0.5)


func _target_position() -> Vector2:
	if _target is Node2D:
		return (_target as Node2D).position
	if _target is Control:
		return (_target as Control).position
	return Vector2.ZERO


# 不同 target 类型用不同 property name,但 Tween.tween_property 用 NodePath
# 都是 "position",所以可以统一。
func _tween_position(tween: Tween, pos: Vector2, time: float) -> void:
	tween.tween_property(_target, "position", pos, time)
