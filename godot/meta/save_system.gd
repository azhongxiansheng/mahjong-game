extends Node

# 麻将王 — 里程碑 5 第 2 步：SaveSystem 真持久化（plan-5 D5；替 M4 占位）
#
# 注：本脚本注册为 autoload `SaveSystem`（见 project.godot）。**没有 class_name**
# 也是有意：autoload 节点不应同时是 class_name（避免引用方既能 SaveSystem
# 静态 / 又能 get_node('/root/SaveSystem') 实例化的混淆）。
#
# JSON 文件结构：直接存 RunState.to_dict() 顶层 dict（含 version 字段供未来迁移）。
# 错误处理：load 失败返 null + 写 user://logs/save_load_error.log；save 失败返 ERR_*。

const SAVE_PATH: String = "user://savegame.json"

# save / clear 操作成功完成时 emit,UI 层(SaveToast autoload)挂监听显示
# "💾 已保存" toast。
signal save_completed
signal save_cleared


# 保存当前 RunState 到磁盘。返 OK / ERR_*。
func save_run(run_state) -> int:
	if run_state == null:
		push_warning("SaveSystem.save_run: run_state 为 null")
		return ERR_INVALID_PARAMETER
	var d: Dictionary = run_state.to_dict()
	var json_str: String = JSON.stringify(d, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		var err: int = FileAccess.get_open_error()
		push_error("SaveSystem.save_run: 无法打开 %s（err=%d）" % [SAVE_PATH, err])
		return err if err != OK else ERR_FILE_CANT_WRITE
	file.store_string(json_str)
	file.close()
	save_completed.emit()
	return OK

# 从磁盘加载 Run。返 RunState 或 null（不存在 / 解析失败 / 版本不匹配）。
func load_run():
	if not has_save():
		return null
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveSystem.load_run: 无法打开 %s（err=%d）" % [SAVE_PATH, FileAccess.get_open_error()])
		return null
	var json_str: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_str)
	if parsed == null:
		push_error("SaveSystem.load_run: JSON 解析失败")
		return null
	if not (parsed is Dictionary):
		push_error("SaveSystem.load_run: 顶层不是 Dictionary")
		return null
	var rs = RunState.from_dict(parsed)
	if rs == null:
		push_warning("SaveSystem.load_run: from_dict 返回 null（版本不匹配？）")
	return rs

# 是否存在中途存档
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

# 清除存档（Run 失败 / 通关 / 玩家主动放弃）
func clear_run() -> void:
	if not has_save():
		return
	var err: int = DirAccess.remove_absolute(SAVE_PATH)
	if err != OK:
		push_warning("SaveSystem.clear_run: 删除 %s 失败（err=%d）" % [SAVE_PATH, err])
		return
	save_cleared.emit()
