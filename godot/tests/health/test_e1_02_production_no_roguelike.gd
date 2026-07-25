extends GutTest

# 生产入口只保留大厅与四人牌桌；退役的肉鸽 Run 与旧中式客户端不再留在仓库。

const REMOVED_AUTOLOADS: Array[String] = [
	"SaveSystem",
	"MetaProgress",
	"BattlePass",
	"DailyQuest",
	"SaveToast",
]

const REMOVED_PATHS: Array[String] = [
	"res://ui/run",
	"res://legacy",
	"res://meta/save_system.gd",
	"res://meta/meta_progress.gd",
	"res://meta/battle_pass.gd",
	"res://meta/daily_quest.gd",
	"res://meta/save_toast.gd",
	"res://meta/run_state.gd",
	"res://tools/simulate_runs.gd",
	"res://tools/simulation_harness.gd",
]

const LOBBY_SCENE := "res://ui/lobby/lobby_shell.tscn"
const LEGACY_SAVE_PATH := "user://savegame.json"


func test_production_does_not_register_roguelike_autoloads() -> void:
	for autoload_name in REMOVED_AUTOLOADS:
		assert_false(
			ProjectSettings.has_setting("autoload/%s" % autoload_name),
			"生产配置不得注册肉鸽 Autoload：%s" % autoload_name
		)
		assert_null(
			get_tree().root.get_node_or_null(autoload_name),
			"生产场景树不得挂载肉鸽单例：%s" % autoload_name
		)


func test_retired_gameplay_paths_are_removed() -> void:
	for path in REMOVED_PATHS:
		assert_false(
			FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path),
			"退役玩法文件不得继续留在仓库：%s" % path
		)


func test_legacy_save_does_not_change_lobby_cold_start() -> void:
	var had_original := FileAccess.file_exists(LEGACY_SAVE_PATH)
	var original_bytes := _read_bytes(LEGACY_SAVE_PATH) if had_original else PackedByteArray()
	var sentinel := "{\"legacy_run\":true,\"sentinel\":\"e1-02\"}"
	var file := FileAccess.open(LEGACY_SAVE_PATH, FileAccess.WRITE)
	assert_not_null(file, "应能创建隔离的 legacy 存档夹具")
	if file == null:
		return
	file.store_string(sentinel)
	file.close()

	var shell: Node = load(LOBBY_SCENE).instantiate()
	add_child_autofree(shell)
	await get_tree().process_frame
	assert_true(shell is LobbyShell, "存在旧存档时仍应直接实例化大厅")
	assert_eq(
		_read_bytes(LEGACY_SAVE_PATH).get_string_from_utf8(),
		sentinel,
		"大厅冷启动不得读取后改写或清除旧 Run 存档"
	)

	if had_original:
		_write_bytes(LEGACY_SAVE_PATH, original_bytes)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY_SAVE_PATH))
	await get_tree().create_timer(0.3).timeout


func test_settings_overlay_has_no_tutorial_or_run_save_entry() -> void:
	var overlay := SettingsOverlay.new()
	add_child_autofree(overlay)
	await get_tree().process_frame
	var copy := _control_copy(overlay)
	assert_true(copy.contains("试听"), "设置页应保留试听入口")
	assert_true(copy.contains("全屏"), "设置页应保留全屏入口")
	assert_true(copy.contains("查看战绩"), "设置页应保留战绩入口")
	assert_true(copy.contains("关闭"), "设置页应保留关闭入口")
	for forbidden in ["重看新手引导", "放弃本场", "SaveSystem", "Run"]:
		assert_false(copy.contains(forbidden), "设置页不得显示肉鸽入口：%s" % forbidden)
	await get_tree().create_timer(0.3).timeout


func test_stats_view_only_shows_mahjong_stats_and_achievements() -> void:
	var view := StatsView.new()
	add_child_autofree(view)
	await get_tree().process_frame
	var copy := _control_copy(view)
	assert_true(copy.contains("对局总数"), "战绩页应保留麻将对局统计")
	assert_true(copy.contains("胡牌次数"), "战绩页应保留麻将胡牌统计")
	for forbidden in ["Run 开局", "通关一次", "肉鸽常胜", "首次完成 Run", "通关 5 次"]:
		assert_false(copy.contains(forbidden), "战绩页不得显示肉鸽统计/成就：%s" % forbidden)
	await get_tree().create_timer(0.3).timeout


func test_help_overlay_has_no_tutorial_or_run_shortcuts() -> void:
	var help_copy := ""
	for section in HelpOverlay.SECTIONS:
		help_copy += str(section) + "\n"
	for forbidden in ["重看引导", "放弃 Run", "新手引导上一页", "新手引导下一页"]:
		assert_false(help_copy.contains(forbidden), "帮助页不得显示旧流程说明：%s" % forbidden)


func _control_copy(root: Node) -> String:
	var copy := ""
	for node in root.find_children("*", "", true, false):
		if node is Label:
			copy += (node as Label).text + "\n"
		elif node is BaseButton:
			copy += (node as BaseButton).text + "\n"
	return copy


func _read_bytes(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(bytes)
	file.close()
