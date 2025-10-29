class_name WeChatIconManager
extends Node

# 微信图标管理器
# 提供简化的图标管理接口

var downloader: WeChatIconDownloader
var is_downloading: bool = false

func _ready() -> void:
	"""初始化图标管理器"""
	# 创建下载器实例
	downloader = WeChatIconDownloader.new()
	add_child(downloader)

	# 连接下载器的信号
	downloader.download_started.connect(_on_download_started)
	downloader.download_progress.connect(_on_download_progress)
	downloader.download_completed.connect(_on_download_completed)

	print("✅ 微信图标管理器已初始化")

## 自动下载并部署官方图标（快速模式）
func auto_download_icon(callback: Callable = Callable()) -> void:
	"""
	自动下载微信官方图标 - 快速模式
	使用默认参数（40x40 SVG 格式）

	参数:
		callback: 完成回调函数，接收 (success: bool, message: String) 参数
	"""
	await download_icon(40, "svg", false, callback)

## 下载指定规格的图标
func download_icon(size: int = 40, format: String = "svg", force_refresh: bool = false, callback: Callable = Callable()) -> void:
	"""
	下载微信图标

	参数:
		size: 图标尺寸 (32, 40, 48, 64, 128)
		format: 图标格式 (svg, png)
		force_refresh: 是否强制刷新
		callback: 完成回调函数
	"""
	if is_downloading:
		print("⚠ 已有下载任务正在进行，请等待完成")
		return

	is_downloading = true
	print("🚀 开始下载微信官方图标...")
	print("📋 规格: %dx%d %s" % [size, size, format])

	var success = await downloader.download_icon(size, format, force_refresh)
	is_downloading = false

	if callback.is_valid():
		callback.call(success, "图标下载部署成功" if success else "图标下载部署失败")

## 获取可用的图标配置
func get_icon_specs() -> Dictionary:
	"""获取图标的规格信息"""
	return downloader.get_available_icons()

## 获取推荐的图标配置
func get_recommended_icon() -> Dictionary:
	"""获取推荐的图标配置"""
	var specs = downloader.get_available_icons()
	return {
		"size": specs.recommended_size,
		"format": specs.recommended_format,
		"color": specs.color
	}

## 清理下载缓存
func clear_icon_cache() -> void:
	"""清理图标下载缓存"""
	downloader.clear_cache()

## 内部回调：下载开始
func _on_download_started() -> void:
	"""下载开始时调用"""
	print("📥 图标下载开始")

## 内部回调：下载进度更新
func _on_download_progress(progress: float, message: String) -> void:
	"""下载进度更新时调用"""
	print("📊 [%.0f%%] %s" % [progress, message])

## 内部回调：下载完成
func _on_download_completed(success: bool, message: String) -> void:
	"""下载完成时调用"""
	if success:
		print("✅ 图标下载完成: %s" % message)
	else:
		print("❌ 图标下载失败: %s" % message)
