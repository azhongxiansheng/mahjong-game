extends Node

# 麻将王 — 里程碑 4 第 2 步：SaveSystem autoload 占位（plan-4 D6）
#
# 本类仅声明接口，**不实装**任何持久化逻辑——存档文件读写在里程碑 5
# （抽卡 + 卡包 + 元进度 + 存档）才落地。本里程碑（M4 Run 流程骨架）
# 内 RunState 全部活在内存，杀进程即丢；UI 端会在 Run 流程内提示
# "v1 不支持中途存档"。
#
# 注：本脚本注册为 autoload `SaveSystem`（见 project.godot），属于
# Godot 引擎特殊规则下"通过节点路径访问的全局单例"。**没有 class_name**
# 也是有意：autoload 节点不应同时是 class_name（避免引用方既能 SaveSystem
# 静态 / 又能 get_node('/root/SaveSystem') 实例化的混淆）。
#
# 占位策略：4 个 API 全部安全可调（不抛错）；调用时 push_warning 提示
# "未实装（M5）"——不阻塞 Run 流程主线，让 UI 拉占位文字即可。

const SAVE_PATH: String = "user://savegame.json"

# 保存当前 Run 到磁盘。M5 实装真正的 to_json + write。
# 返回 OK / ERR_*
func save_run(_run_state) -> int:
	push_warning("SaveSystem.save_run: 未实装（M5 内容生产时落地）")
	return OK

# 从磁盘加载 Run。M5 返回反序列化后的 RunState；当前返 null。
func load_run():
	push_warning("SaveSystem.load_run: 未实装（M5 内容生产时落地）")
	return null

# 是否存在中途存档；M5 走 FileAccess.file_exists(SAVE_PATH)。
func has_save() -> bool:
	return false

# 清除当前 Run 的存档（用于 Run 失败 / 通关 / 玩家主动放弃）。
func clear_run() -> void:
	push_warning("SaveSystem.clear_run: 未实装（M5）")
