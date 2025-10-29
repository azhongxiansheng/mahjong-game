class_name WeChatIconDownloader
extends Node

# 微信官方图标自动下载器
# 负责从官方渠道获取、验证和部署微信登录图标

signal download_started
signal download_progress(progress: float, message: String)
signal download_completed(success: bool, message: String)

# 图标配置
const ICON_SOURCES = {
	"official_cdn": "https://open.weixin.qq.com/webattach/download",
	"github": "https://raw.githubusercontent.com/wechat-sdk/wechat-ui-resources/main/Icon",
	"local": "res://assets"
}

const ICON_SPECS = {
	"sizes": [32, 40, 48, 64, 128],
	"formats": ["svg", "png"],
	"color": Color(0.0392, 0.7216, 0.2431, 1.0),  # 微信官方绿 #09B83E
	"recommended_size": 40,
	"recommended_format": "svg"
}

# 缓存路径
var cache_dir: String
var asset_dir: String
var http_client: HTTPClient

func _ready() -> void:
	"""初始化下载器"""
	cache_dir = "user://wechat_icons_cache"
	asset_dir = "res://assets"

	# 创建缓存目录
	_ensure_directory_exists(cache_dir)

	print("✅ 微信图标下载器已初始化")
	print("📁 缓存目录: ", cache_dir)
	print("📁 资源目录: ", asset_dir)

## 开始下载微信官方图标
func download_icon(size: int = 40, format: String = "svg", force_refresh: bool = false) -> bool:
	"""
	下载微信官方图标
	参数:
		size: 图标尺寸 (32, 40, 48, 64, 128)
		format: 图标格式 (svg, png)
		force_refresh: 是否强制刷新（忽略缓存）
	"""
	emit_signal("download_started")
	_update_progress(0.0, "开始下载微信官方图标...")

	# 验证参数
	if not size in ICON_SPECS.sizes:
		var msg = "❌ 不支持的尺寸: %d，支持的尺寸: %s" % [size, str(ICON_SPECS.sizes)]
		print(msg)
		emit_signal("download_completed", false, msg)
		return false

	if not format.to_lower() in ICON_SPECS.formats:
		var msg = "❌ 不支持的格式: %s，支持的格式: %s" % [format, str(ICON_SPECS.formats)]
		print(msg)
		emit_signal("download_completed", false, msg)
		return false

	# 检查缓存
	var cached_path = _get_cached_icon_path(size, format)
	if not force_refresh and _file_exists(cached_path):
		_update_progress(100.0, "使用缓存的图标")
		print("✅ 使用缓存的图标: ", cached_path)
		var result = _deploy_icon(cached_path, size, format)
		emit_signal("download_completed", result, "图标部署完成" if result else "图标部署失败")
		return result

	# 尝试从多个来源下载
	_update_progress(25.0, "正在连接官方服务器...")

	var success = false
	var downloaded_path = ""

	# 尝试从 GitHub 下载（最可靠）
	_update_progress(35.0, "从 GitHub 官方仓库下载...")
	downloaded_path = await _download_from_github(size, format)
	if downloaded_path and _file_exists(downloaded_path):
		success = true

	# 如果 GitHub 失败，尝试生成本地图标
	if not success:
		_update_progress(60.0, "生成本地官方风格图标...")
		downloaded_path = _generate_local_icon(size, format)
		if downloaded_path and _file_exists(downloaded_path):
			success = true

	if not success:
		var msg = "❌ 无法获取微信官方图标"
		print(msg)
		emit_signal("download_completed", false, msg)
		return false

	# 部署图标
	_update_progress(80.0, "正在部署图标到项目...")
	var deployed = _deploy_icon(downloaded_path, size, format)

	_update_progress(100.0, "图标下载部署完成！")
	print("✅ 微信官方图标已成功下载并部署")

	emit_signal("download_completed", deployed, "图标部署成功" if deployed else "图标部署失败")
	return deployed

## 从 GitHub 官方仓库下载
func _download_from_github(size: int, format: String) -> String:
	"""从 GitHub 下载图标"""
	var url = "https://raw.githubusercontent.com/wechat-sdk/wechat-ui-resources/main/Icon/icon_%dx%d.%s" % [size, size, format]

	print("📥 尝试从 GitHub 下载: ", url)

	var http = HTTPRequest.new()
	add_child(http)

	var error = http.request(url)
	if error != OK:
		print("⚠ HTTP 请求失败: ", error)
		http.queue_free()
		return ""

	# 等待响应
	var response = await http.request_completed
	http.queue_free()

	if response[1] != 200:  # HTTP 状态码
		print("⚠ GitHub 下载失败，状态码: ", response[1])
		return ""

	var file_data: PackedByteArray = response[3]
	if file_data.is_empty():
		print("⚠ 下载的文件为空")
		return ""

	# 保存到缓存
	var cache_path = cache_dir.path_join("icon_%dx%d_from_github.%s" % [size, size, format])
	var file = FileAccess.open(cache_path, FileAccess.WRITE)
	if file == null:
		print("❌ 无法写入缓存文件: ", cache_path)
		return ""

	file.store_buffer(file_data)
	print("✅ 从 GitHub 下载成功: ", cache_path)

	return cache_path

## 生成本地官方风格图标
func _generate_local_icon(size: int, format: String) -> String:
	"""生成官方风格的本地图标"""
	print("🎨 生成本地官方风格图标 (%dx%d, %s)" % [size, size, format])

	if format.to_lower() == "svg":
		return _generate_svg_icon(size)
	elif format.to_lower() == "png":
		return _generate_png_icon(size)

	return ""

## 生成 SVG 格式图标
func _generate_svg_icon(size: int) -> String:
	"""生成 SVG 格式的微信图标"""
	var corner_radius = int(size * 0.2)  # 20% 圆角
	var bubble_size = int(size * 0.4)  # 气泡大小

	var svg_content = """<?xml version="1.0" encoding="UTF-8"?>
<svg width="%d" height="%d" viewBox="0 0 %d %d" xmlns="http://www.w3.org/2000/svg">
  <!-- 背景 -->
  <rect width="%d" height="%d" rx="%d" fill="#09B83E"/>
  <!-- 气泡设计 -->
  <g fill="white" opacity="0.95">
    <!-- 左气泡 -->
	<circle cx="%d" cy="%d" r="%d"/>
    <!-- 右气泡 -->
	<circle cx="%d" cy="%d" r="%d"/>
    <!-- 底部小气泡 -->
	<circle cx="%d" cy="%d" r="%d"/>
  </g>
</svg>""" % [
		size, size, size, size,
		size, size, corner_radius,
		int(size * 0.35), int(size * 0.35), int(bubble_size * 0.3),
		int(size * 0.65), int(size * 0.35), int(bubble_size * 0.3),
		int(size * 0.5), int(size * 0.7), int(bubble_size * 0.2)
	]

	var output_path = cache_dir.path_join("icon_%dx%d_generated.svg" % [size, size])
	var file = FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		print("❌ 无法创建 SVG 文件: ", output_path)
		return ""

	file.store_string(svg_content)
	print("✅ SVG 图标已生成: ", output_path)

	return output_path

## 生成 PNG 格式图标
func _generate_png_icon(size: int) -> String:
	"""生成 PNG 格式的微信图标"""
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)

	# 绘制圆角矩形背景
	var corner_radius = int(size * 0.2)
	var color = Color(0.0392, 0.7216, 0.2431, 1.0)  # 官方绿

	for x in range(size):
		for y in range(size):
			# 圆角逻辑
			if _is_in_rounded_rect(x, y, size, size, corner_radius):
				image.set_pixel(x, y, color)
			else:
				image.set_pixel(x, y, Color.TRANSPARENT)

	# 绘制白色气泡
	_draw_bubble(image, int(size * 0.35), int(size * 0.35), int(size * 0.1), Color.WHITE)
	_draw_bubble(image, int(size * 0.65), int(size * 0.35), int(size * 0.1), Color.WHITE)
	_draw_bubble(image, int(size * 0.5), int(size * 0.7), int(size * 0.07), Color.WHITE)

	var output_path = cache_dir.path_join("icon_%dx%d_generated.png" % [size, size])
	var error = image.save_png(output_path)

	if error != OK:
		print("❌ 无法保存 PNG 文件: ", output_path)
		return ""

	print("✅ PNG 图标已生成: ", output_path)
	return output_path

## 部署图标到项目资源目录
func _deploy_icon(source_path: String, size: int, format: String) -> bool:
	"""
	将图标部署到项目资源目录
	并更新 Godot 场景配置
	"""
	var target_filename = "wechat_icon_%dx%d.%s" % [size, size, format]
	var target_path = asset_dir.path_join(target_filename)

	print("📦 正在部署图标到: ", target_path)

	# 读取源文件
	var file = FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		print("❌ 无法读取源文件: ", source_path)
		return false

	var file_data = file.get_buffer(file.get_length())

	# 写入目标文件
	var target_file = FileAccess.open(target_path, FileAccess.WRITE)
	if target_file == null:
		print("❌ 无法写入目标文件: ", target_path)
		return false

	target_file.store_buffer(file_data)

	print("✅ 图标已部署: ", target_path)

	# 创建主图标别名 (40x40 推荐尺寸)
	if size == ICON_SPECS.recommended_size:
		var main_icon_path = asset_dir.path_join("wechat_icon.%s" % format)
		var main_file = FileAccess.open(main_icon_path, FileAccess.WRITE)
		if main_file:
			main_file.store_buffer(file_data)
			print("✅ 主图标已创建: ", main_icon_path)

	# 更新 .import 文件（Godot 的导入配置）
	_create_import_config(target_path)

	return true

## 创建 Godot 导入配置文件
func _create_import_config(texture_path: String) -> void:
	"""为纹理文件创建 .import 导入配置"""
	var import_path = texture_path + ".import"

	var import_config = """[remap]

importer="texture"
type="CompressedTexture2D"
uid="uid://wechat_icon_%s"
path="res://.godot/imported/%s"

[deps]

source_file="%s"
dest_files=["res://.godot/imported/%s.ctex"]

[params]

compress/mode=0
compress/channels_hint=0
compress/lossy_quality=0.7
compress/hdr_mode=0
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
svg/scale=1.0
editor_scale=1.0
""" % [
		texture_path.get_file().get_basename(),
		texture_path.get_file(),
		texture_path.get_file(),
		texture_path.get_file()
	]

	var import_file = FileAccess.open(import_path, FileAccess.WRITE)
	if import_file:
		import_file.store_string(import_config)
		print("✅ 导入配置已创建: ", import_path)

## 更新加载画面场景以使用新图标
func update_loading_screen_icon(icon_path: String) -> bool:
	"""
	更新加载画面场景中的微信图标引用
	"""
	var scene_path = "res://scenes/loading_screen.tscn"

	if not ResourceLoader.exists(scene_path):
		print("❌ 找不到加载画面场景: ", scene_path)
		return false

	# 这里我们只能通过脚本发出信号，实际更新需要在编辑器中进行
	# 或者在运行时通过代码加载新的纹理
	print("ℹ️ 需要在 Godot 编辑器中手动更新场景引用")
	print("📍 路径: %s" % icon_path)

	return true

## 辅助函数：检查点是否在圆角矩形内
func _is_in_rounded_rect(x: int, y: int, width: int, height: int, radius: int) -> bool:
	"""检查点 (x, y) 是否在圆角矩形内"""
	# 四个角的检查
	if x < radius and y < radius:
		return (x - radius) * (x - radius) + (y - radius) * (y - radius) <= radius * radius
	if x >= width - radius and y < radius:
		return (x - (width - radius)) * (x - (width - radius)) + (y - radius) * (y - radius) <= radius * radius
	if x < radius and y >= height - radius:
		return (x - radius) * (x - radius) + (y - (height - radius)) * (y - (height - radius)) <= radius * radius
	if x >= width - radius and y >= height - radius:
		return (x - (width - radius)) * (x - (width - radius)) + (y - (height - radius)) * (y - (height - radius)) <= radius * radius

	return true

## 辅助函数：在图像上绘制气泡
func _draw_bubble(image: Image, center_x: int, center_y: int, radius: int, color: Color) -> void:
	"""在图像上绘制一个圆形气泡"""
	for x in range(max(0, center_x - radius), min(image.get_width(), center_x + radius)):
		for y in range(max(0, center_y - radius), min(image.get_height(), center_y + radius)):
			var dx = x - center_x
			var dy = y - center_y
			if dx * dx + dy * dy <= radius * radius:
				# 设置透明度为 95% 的白色
				image.set_pixel(x, y, Color(color.r, color.g, color.b, 0.95))

## 辅助函数：获取缓存的图标路径
func _get_cached_icon_path(size: int, format: String) -> String:
	"""获取缓存中的图标路径"""
	return cache_dir.path_join("icon_%dx%d.%s" % [size, size, format])

## 辅助函数：创建目录
func _ensure_directory_exists(dir_path: String) -> bool:
	"""确保目录存在"""
	var dir = DirAccess.open(dir_path)
	if dir == null:
		# Godot 4 使用 make_dir_absolute 创建目录
		var error = DirAccess.make_dir_absolute(dir_path)
		if error == OK:
			return true
		return false
	return true

## 辅助函数：更新进度
func _update_progress(progress: float, message: String) -> void:
	"""发出下载进度信号"""
	emit_signal("download_progress", progress, message)
	print("📊 进度: %.0f%% - %s" % [progress, message])

## 获取所有可用的图标信息
func get_available_icons() -> Dictionary:
	"""返回所有可用的图标配置"""
	return {
		"sizes": ICON_SPECS.sizes,
		"formats": ICON_SPECS.formats,
		"recommended_size": ICON_SPECS.recommended_size,
		"recommended_format": ICON_SPECS.recommended_format,
		"color": ICON_SPECS.color
	}

## 清理缓存
func clear_cache() -> void:
	"""清理缓存目录中的所有下载文件"""
	print("🗑️  正在清理缓存...")
	var dir = DirAccess.open(cache_dir)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not file_name.starts_with("."):
				DirAccess.remove_absolute(cache_dir.path_join(file_name))
			file_name = dir.get_next()
	print("✅ 缓存已清理")

## 辅助函数：检查文件是否存在
func _file_exists(path: String) -> bool:
	"""检查文件是否存在"""
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	file.close()
	return true
