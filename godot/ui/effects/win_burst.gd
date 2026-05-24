class_name WinBurst extends Node2D

# 胡牌粒子爆发 — 中央 burst 金/橙/白色粒子,按 han / yakuman 分级。
# Tween-based 程序化粒子,无 shader,所有 4.x 平台兼容。
#
# 用法:
#   var burst := WinBurst.new()
#   parent.add_child(burst)
#   burst.position = Vector2(640, 400)  # 屏幕中心
#   burst.play(WinBurst.Tier.YAKUMAN)
#
# 1 秒后自动 queue_free。

enum Tier { LIGHT, MEDIUM, HEAVY, YAKUMAN }

const PARTICLE_COUNTS: Dictionary = {
	Tier.LIGHT: 24,
	Tier.MEDIUM: 48,
	Tier.HEAVY: 80,
	Tier.YAKUMAN: 140,
}

const TIER_COLORS: Dictionary = {
	Tier.LIGHT: Color(1.0, 0.95, 0.75),       # 米白
	Tier.MEDIUM: Color(1.0, 0.78, 0.4),       # 橙
	Tier.HEAVY: Color(1.0, 0.6, 0.2),         # 深橙
	Tier.YAKUMAN: Color(1.0, 0.85, 0.3),      # 金黄
}

const TIER_DURATIONS: Dictionary = {
	Tier.LIGHT: 0.65,
	Tier.MEDIUM: 0.85,
	Tier.HEAVY: 1.0,
	Tier.YAKUMAN: 1.4,
}


func _init() -> void:
	# 不让 z_index 被 parent's CanvasLayer 影响
	z_index = 200
	z_as_relative = false


# Tier 决定粒子数 / 颜色 / 持续时间。返回值留作未来扩展(链式 API)。
func play(tier: int) -> WinBurst:
	var count: int = int(PARTICLE_COUNTS.get(tier, 24))
	var color: Color = TIER_COLORS.get(tier, Color(1, 1, 1, 1))
	var duration: float = float(TIER_DURATIONS.get(tier, 0.6))
	for i in range(count):
		_spawn_particle(color, duration, i, count)
	# 自动清理整个 burst 节点
	var t := create_tween()
	t.tween_interval(duration + 0.2)
	t.tween_callback(queue_free)
	return self


# 单个粒子 = ColorRect,从 (0,0) 沿随机方向以随机速度飞出,带渐隐 + 缩小。
func _spawn_particle(base_color: Color, duration: float, idx: int, total: int) -> void:
	var rect := ColorRect.new()
	var size: float = randf_range(6.0, 14.0)
	rect.size = Vector2(size, size)
	rect.position = Vector2(-size / 2, -size / 2)
	# 颜色 ±15% 亮度抖动
	var jitter := 1.0 + randf_range(-0.15, 0.15)
	rect.color = Color(
		clamp(base_color.r * jitter, 0, 1),
		clamp(base_color.g * jitter, 0, 1),
		clamp(base_color.b * jitter, 0, 1),
		1.0
	)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)

	# 角度均匀分布 + ±15° 抖动,避免完全规则圆形
	var angle_step: float = TAU / float(total)
	var angle: float = idx * angle_step + randf_range(-0.13, 0.13)
	# 速度随机化 + 上方略偏(更"喷出"感)
	var speed: float = randf_range(180, 420)
	var dx: float = cos(angle) * speed
	var dy: float = sin(angle) * speed - randf_range(40, 120)  # 略往上飘
	var target := Vector2(dx, dy) * duration

	# 旋转 — 让粒子翻滚
	var rot_speed: float = randf_range(-TAU, TAU) * duration

	var tween := create_tween().set_parallel(true)
	tween.tween_property(rect, "position", target + Vector2(-size / 2, -size / 2), duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(rect, "modulate:a", 0.0, duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(rect, "scale", Vector2(0.3, 0.3), duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(rect, "rotation", rot_speed, duration)
