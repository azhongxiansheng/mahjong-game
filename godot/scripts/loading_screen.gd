extends Control

var progress_bar: ProgressBar = null
var status_label: Label = null
var tips_label: Label = null

var tips = [
	"Tip: Clear hands can double points",
	"Goal: Win using various hand patterns",
	"AI opponent is ready",
	"Loading game...",
	"Optimizing textures...",
	"Welcome to Mahjong world"
]

func _ready():
	print("LoadingScreen._ready() started")
	
	# 安全获取节点
	progress_bar = get_node_or_null("VBoxContainer/ProgressBar")
	status_label = get_node_or_null("VBoxContainer/StatusLabel")
	tips_label = get_node_or_null("VBoxContainer/TipsLabel")
	
	if not progress_bar:
		print("⚠ ProgressBar not found")
	if not status_label:
		print("⚠ StatusLabel not found")
	if not tips_label:
		print("⚠ TipsLabel not found")
	
	print("Loading screen loaded")
	show_loading_screen()

func show_loading_screen():
	if progress_bar:
		progress_bar.value = 0
	if status_label:
		status_label.text = "Initializing..."
	if tips_label:
		tips_label.text = tips[randi() % tips.size()]
	print("Loading screen UI initialized")
	load_game_async()

func load_game_async():
	print("Starting game load...")
	
	await _load_phase("Initializing resources", 30)
	await _load_phase("Loading audio", 60)
	await _load_phase("Initializing AI", 80)
	await _load_phase("Preparing scene", 100)
	
	print("Load complete, transitioning to main...")
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://ui/lobby/lobby_shell.tscn")

func _load_phase(message: String, to: int):
	if status_label:
		status_label.text = message
	
	if progress_bar:
		while progress_bar.value < to:
			progress_bar.value += randf_range(1, 3)
			await get_tree().process_frame
		
		progress_bar.value = to
	else:
		await get_tree().create_timer(0.5).timeout
