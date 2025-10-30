extends Control

@onready var title_label: Label = $TitleLabel
@onready var particles_container: Node2D = $ParticlesContainer

var particles: Array = []
var particle_count: int = 30
var time_passed: float = 0.0

class Particle:
	var position: Vector2
	var velocity: Vector2
	var lifetime: float
	var max_lifetime: float
	var size: float
	var color: Color
	
	func _init(pos: Vector2, vel: Vector2, life: float, s: float, c: Color):
		position = pos
		velocity = vel
		lifetime = 0.0
		max_lifetime = life
		size = s
		color = c

func _ready():
	# 初始化粒子
	for i in range(particle_count):
		_spawn_particle()

func _process(delta: float):
	time_passed += delta
	
	# 更新和绘制粒子
	for particle in particles:
		particle.position += particle.velocity * delta
		particle.lifetime += delta
		
		# 粒子老化后重生
		if particle.lifetime >= particle.max_lifetime:
			_respawn_particle(particle)
	
	queue_redraw()

func _draw():
	var container_size = size
	
	for particle in particles:
		var alpha = 1.0 - (particle.lifetime / particle.max_lifetime)
		var draw_color = Color(particle.color.r, particle.color.g, particle.color.b, alpha * 0.8)
		
		# 绘制发光粒子
		draw_circle(particle.position, particle.size, draw_color)
		# 添加外发光
		var glow_color = Color(particle.color.r, particle.color.g, particle.color.b, alpha * 0.3)
		draw_circle(particle.position, particle.size * 2.0, glow_color)

func _spawn_particle():
	var container_size = size
	var center = container_size / 2.0
	
	# 在文字周围随机生成
	var angle = randf() * TAU
	var distance = randf_range(150.0, 250.0)
	var pos = center + Vector2(cos(angle), sin(angle)) * distance
	
	# 向中心移动的速度
	var vel = (center - pos).normalized() * randf_range(20.0, 50.0)
	
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
		randf_range(2.0, 4.0),
		randf_range(2.0, 4.0),
		particle_color
	)
	particles.append(particle)

func _respawn_particle(particle: Particle):
	var container_size = size
	var center = container_size / 2.0
	
	var angle = randf() * TAU
	var distance = randf_range(150.0, 250.0)
	particle.position = center + Vector2(cos(angle), sin(angle)) * distance
	particle.velocity = (center - particle.position).normalized() * randf_range(20.0, 50.0)
	particle.lifetime = 0.0
	particle.max_lifetime = randf_range(2.0, 4.0)
	particle.size = randf_range(2.0, 4.0)
