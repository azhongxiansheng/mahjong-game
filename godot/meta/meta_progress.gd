extends Node

# 麻将王 — 里程碑 5 第 2 步：元进度（声望）跨 Run 持久化（plan-5 D6；spec §9.4）
#
# 注：autoload 单例；project.godot 注册名 `MetaProgress`。
#
# v1 简化：仅累计声望显示在 RunSummary，不实际解锁内容（M6 内容化时再做
# "声望 ≥ N → 解锁起始包 X"映射）。
#
# 声望 v1 占位数值：通关 +50 / 失败 +5（与 RunSummary.format_renown_placeholder
# 一致）。

const META_PATH: String = "user://meta_progress.json"
const META_VERSION: int = 1

const RENOWN_RUN_WON: int = 50
const RENOWN_RUN_FAILED: int = 5

var renown: int = 0
var runs_completed: int = 0
var runs_won: int = 0

func _ready() -> void:
	_load_meta()

# 调用方在 Run 终态时调
func add_renown_for_run(won: bool) -> int:
	var amount: int = RENOWN_RUN_WON if won else RENOWN_RUN_FAILED
	renown += amount
	runs_completed += 1
	if won:
		runs_won += 1
	save_meta()
	return amount


# 撤销最近一次 add_renown_for_run。RunFlow 复活时调:_on_run_failed 已经
# finalize (renown +5 / runs_completed +1),复活后玩家继续 run,本次终态
# 还没真的到。需要撤回避免玩家"故意失败 + 复活"刷 renown/runs_completed。
# clamp 到 ≥0 不让负数,防御 partial save 之类。
func revert_last_run(won_was: bool) -> void:
	var amount: int = RENOWN_RUN_WON if won_was else RENOWN_RUN_FAILED
	renown = max(0, renown - amount)
	runs_completed = max(0, runs_completed - 1)
	if won_was:
		runs_won = max(0, runs_won - 1)
	save_meta()

# ---- 持久化 ----

func save_meta() -> int:
	var d: Dictionary = to_dict()
	var json_str: String = JSON.stringify(d, "\t")
	var file := FileAccess.open(META_PATH, FileAccess.WRITE)
	if file == null:
		var err: int = FileAccess.get_open_error()
		push_error("MetaProgress.save_meta: %s 无法写（err=%d）" % [META_PATH, err])
		return err if err != OK else ERR_FILE_CANT_WRITE
	file.store_string(json_str)
	file.close()
	return OK

func _load_meta() -> void:
	if not FileAccess.file_exists(META_PATH):
		return
	var file := FileAccess.open(META_PATH, FileAccess.READ)
	if file == null:
		push_error("MetaProgress._load_meta: 打开失败")
		return
	var json_str: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_str)
	if not (parsed is Dictionary):
		push_warning("MetaProgress._load_meta: JSON 解析失败 / 类型错")
		return
	if int(parsed.get("version", 0)) != META_VERSION:
		push_warning("MetaProgress._load_meta: 版本不匹配，忽略并保留默认值")
		return
	renown = int(parsed.get("renown", 0))
	runs_completed = int(parsed.get("runs_completed", 0))
	runs_won = int(parsed.get("runs_won", 0))

func get_renown() -> int:
	return renown

func is_unlocked(unlock_key: StringName) -> bool:
	return renown >= unlock_threshold(unlock_key)

static func unlock_threshold(key: StringName) -> int:
	match key:
		&"starter_aggro", &"starter_fast", &"starter_control":
			return 0
		&"lin_yeche", &"qiu_jue", &"bai_touli":
			return 0
		&"relic_lucky_cat_v1":
			return 0
		&"relic_iron_will_v1":
			return 30
		&"relic_soul_mirror_v1":
			return 100
		&"relic_wall_eye_v1":
			return 200
	return 0

func reset() -> void:
	# 用于测试或玩家主动清档
	renown = 0
	runs_completed = 0
	runs_won = 0
	if FileAccess.file_exists(META_PATH):
		DirAccess.remove_absolute(META_PATH)

# ---- 序列化（测试用 + 内部） ----

func to_dict() -> Dictionary:
	return {
		"version": META_VERSION,
		"renown": renown,
		"runs_completed": runs_completed,
		"runs_won": runs_won,
	}
