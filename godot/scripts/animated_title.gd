extends Control

var particles: Array = []
var particle_count: int = 80
var time_passed: float = 0.0
var fire_particles: Array = []  # 火焰粒子
var text: String = "飞凡娱乐"
var font_size: int = 84

class Particle:
	var position: Vector2
	var velocity: Vector2
	var lifetime: float
	var max_lifetime: float
	var size: float
	var color: Color
	var is_fire: bool = false  # 是否为火焰粒子
	
	func _init(pos: Vector2, vel: Vector2, life: float, s: float, c: Color, fire: bool = false):
		position = pos
		velocity = vel
		lifetime = 0.0
		max_lifetime = life
		size = s
		color = c
		is_fire = fire

func _ready():
	# 初始化环绕粒子
	for i in range(40):
		_spawn_particle()
	
	# 初始化火焰粒子
	for i in range(40):
		_spawn_fire_particle()

func _process(delta: float):
	time_passed += delta
	
	# 更新和绘制粒子
	for particle in particles:
		if particle.is_fire:
			# 火焰粒子向上飘动
			particle.position.y -= 30.0 * delta
			particle.position.x += sin(particle.lifetime * 3.0) * 20.0 * delta
		else:
			# 环绕粒子
			particle.position += particle.velocity * delta
		
		particle.lifetime += delta
		
		# 粒子老化后重生
		if particle.lifetime >= particle.max_lifetime:
			if particle.is_fire:
				_respawn_fire_particle(particle)
			else:
				_respawn_particle(particle)
	
	queue_redraw()

func _draw():
	var container_size = size
	var center = container_size / 2.0
	
	# 先绘制粒子（在文字下方）
	for particle in particles:
		var alpha = 1.0 - (particle.lifetime / particle.max_lifetime)
		var draw_color = Color(particle.color.r, particle.color.g, particle.color.b, alpha * 0.9)
		
		if particle.is_fire:
			# 火焰粒子：渐变从橙红到黄色
			var fire_progress = particle.lifetime / particle.max_lifetime
			if fire_progress < 0.5:
				# 橙红色
				draw_color = Color(1.0, 0.4, 0.1, alpha * 0.8)
			else:
				# 渐变到黄色
				draw_color = Color(1.0, 0.8, 0.2, alpha * 0.6)
			
			# 绘制火焰粒子（更大更亮）
			draw_circle(particle.position, particle.size * 1.5, draw_color)
			var glow_color = Color(1.0, 0.6, 0.0, alpha * 0.4)
			draw_circle(particle.position, particle.size * 3.5, glow_color)
		else:
			# 环绕粒子
			draw_circle(particle.position, particle.size, draw_color)
			var glow_color = Color(particle.color.r, particle.color.g, particle.color.b, alpha * 0.3)
			draw_circle(particle.position, particle.size * 2.5, glow_color)
	
	# 绘制文字（带多层描边和发光）
	var text_pos = center - Vector2(len(text) * font_size * 0.3, font_size * 0.3)
	
	# 外发光层（橙色）
	for offset_x in range(-12, 13, 4):
		for offset_y in range(-12, 13, 4):
			if offset_x != 0 or offset_y != 0:
				var glow_pos = text_pos + Vector2(offset_x, offset_y)
				var distance = sqrt(offset_x * offset_x + offset_y * offset_y)
				var glow_alpha = 0.3 * (1.0 - distance / 15.0)
				draw_string(ThemeDB.fallback_font, glow_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.5, 0.0, glow_alpha))
	
	# 深色描边（立体感）
	for offset in [Vector2(-3, -3), Vector2(-3, 3), Vector2(3, -3), Vector2(3, 3)]:
		draw_string(ThemeDB.fallback_font, text_pos + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.2, 0.1, 0.0, 1.0))
	
	# 金属质感层
	var time_glow = sin(time_passed * 2.0) * 0.2 + 0.8
	draw_string(ThemeDB.fallback_font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.85 * time_glow, 0.2, 1.0))
	
	# 高光层（动态移动）
	var highlight_offset = sin(time_passed * 1.5) * 2.0
	draw_string(ThemeDB.fallback_font, text_pos + Vector2(-2 + highlight_offset, -3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 1.0, 0.8, 0.5))

func _spawn_particle():
	var container_size = size
	var center = container_size / 2.0
	
	# 在文字周围随机生成
	var angle = randf() * TAU
	var distance = randf_range(180.0, 280.0)
	var pos = center + Vector2(cos(angle), sin(angle)) * distance
	
	# 向中心移动的速度
	var vel = (center - pos).normalized() * randf_range(15.0, 40.0)
	
	# 金色粒子
	var colors = [
		Color(1.0, 0.9, 0.3),  # 金黄色
		Color(1.0, 0.7, 0.2),  # 橙金色
		Color(1.0, 0.5, 0.0),  # 橙色
	]
	var particle_color = colors[randi() % colors.size()]
	
	var particle = Particle.new(
		pos,
		vel,
		randf_range(3.0, 5.0),
		randf_range(2.5, 5.0),
		particle_color,
		false
	)
	particles.append(particle)

# 生成火焰粒子（在文字周围向上飘）
func _spawn_fire_particle():
	var container_size = size
	var center = container_size / 2.0
	
	# 在文字底部和周围生成
	var offset_x = randf_range(-200.0, 200.0)
	var offset_y = randf_range(-30.0, 50.0)
	var pos = center + Vector2(offset_x, offset_y)
	
	# 火焰颜色
	var fire_colors = [
		Color(1.0, 0.3, 0.0),  # 橙红色
		Color(1.0, 0.5, 0.0),  # 橙色
		Color(1.0, 0.7, 0.1),  # 橙黄色
	]
	var fire_color = fire_colors[randi() % fire_colors.size()]
	
	var particle = Particle.new(
		pos,
		Vector2.ZERO,  # 火焰粒子不需要初始速度
		randf_range(1.5, 2.5),
		randf_range(3.0, 6.0),
		fire_color,
		true
	)
	particles.append(particle)

func _respawn_fire_particle(particle: Particle):
	var container_size = size
	var center = container_size / 2.0
	
	var offset_x = randf_range(-200.0, 200.0)
	var offset_y = randf_range(-30.0, 50.0)
	particle.position = center + Vector2(offset_x, offset_y)
	particle.lifetime = 0.0
	particle.max_lifetime = randf_range(1.5, 2.5)
	particle.size = randf_range(3.0, 6.0)

func _respawn_particle(particle: Particle):
	var container_size = size
	var center = container_size / 2.0
	
	var angle = randf() * TAU
	var distance = randf_range(180.0, 280.0)
	particle.position = center + Vector2(cos(angle), sin(angle)) * distance
	particle.velocity = (center - particle.position).normalized() * randf_range(15.0, 40.0)
	particle.lifetime = 0.0
	particle.max_lifetime = randf_range(3.0, 5.0)
	particle.size = randf_range(2.5, 5.0)
