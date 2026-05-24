extends GutTest

# 场景 / 资源 健康检查 — 扫所有 res:// 下 .tscn / .tres / .gd,
# 断言 ResourceLoader.exists + load() != null。
# 一次跑一发 catch 漂移:.import 缺失、.tscn 引用已删除节点、循环引用、
# class_name 重复等。CI 阶段比启动 + F6 手测更早 catch 问题。


const SKIP_DIRS: Array = [
	"res://addons",       # 第三方插件,不自验
	"res://.godot",       # 引擎生成
	"res://_staging",     # 资产管线暂存
	"res://_raw_tiles",
	# Legacy dirs per CLAUDE.md — 旧中式麻将 + WeChat login + 死代码,
	# 不在新引擎活跃路径上,被新引擎不依赖。
	"res://legacy",
	"res://scripts",
	"res://scenes",       # legacy 场景 main.tscn 等
]

# 单文件 skip(legacy 顶层入口 main.tscn 仍可被 ResourceLoader 看见,但其
# 依赖链含 legacy 脚本,load() 会触发 legacy compile chain)
const SKIP_FILES: Array = [
	"res://main.tscn",
]

# 已知会 fail load() 的资源(白名单跳过 — 比如 .uid 系统文件不是真资源)
const SKIP_EXTENSIONS: Array = [".uid", ".import"]


# 扫 res:// 收集所有可加载文件 — 只 .tscn / .tres / .png(.gd 经 GUT 启动验证不
# 必再 load,且 load 一个未用 .gd 可能触发依赖链 compile,意外引爆 legacy)
static func _collect_files(dir_path: String, out: Array) -> void:
	for skip in SKIP_DIRS:
		if dir_path.begins_with(skip):
			return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name: String = dir.get_next()
		if name == "":
			break
		if name.begins_with("."):
			continue
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			_collect_files(full, out)
		else:
			var ext: String = name.get_extension()
			# 只验 binary-ish 资源 — .gd 跳过(已由 GUT 启动验证 + class_name 解析)
			if ext in ["tscn", "tres", "png"]:
				out.append(full)
	dir.list_dir_end()


# 一次性 entry,枚举所有资源然后逐个 try load。把失败聚合成 1 个断言
# 避免几百个 sub-test。
func test_all_scenes_and_resources_load() -> void:
	var files: Array = []
	_collect_files("res://", files)
	assert_gt(files.size(), 50, "应扫到 >50 个 .tscn/.tres/.png 资源")
	var failures: Array[String] = []
	for path in files:
		if path in SKIP_FILES:
			continue
		if not ResourceLoader.exists(path):
			if not FileAccess.file_exists(path):
				failures.append("%s — file不存在" % path)
			continue
		var res = ResourceLoader.load(path)
		if res == null:
			failures.append("%s — load() 返 null" % path)
	if not failures.is_empty():
		gut.p("Resource load failures (%d):" % failures.size())
		for f in failures.slice(0, 10):
			gut.p("  - " + f)
	assert_eq(failures.size(), 0, "所有 .tscn/.tres/.png 应可 load")


# 确认关键场景可实例化(load + instantiate)
func test_critical_scenes_instantiate() -> void:
	var critical: Array[String] = [
		"res://ui/run/run_flow.tscn",
		"res://ui/four_player_table/playable_table.tscn",
		"res://ui/four_player_table/four_player_table.tscn",
		"res://ui/four_player_table/player_action_panel.tscn",
		"res://ui/four_player_table/seat_panel.tscn",
		"res://ui/run/run_hud.tscn",
		"res://ui/run/run_summary.tscn",
	]
	var failures: Array[String] = []
	for path in critical:
		if not ResourceLoader.exists(path):
			failures.append("%s 不存在" % path)
			continue
		var packed: PackedScene = ResourceLoader.load(path)
		if packed == null:
			failures.append("%s load 失败" % path)
			continue
		var inst = packed.instantiate()
		if inst == null:
			failures.append("%s instantiate 失败" % path)
			continue
		inst.free()
	assert_eq(failures.size(), 0, "关键场景应可实例化: %s" % str(failures))


# 必备 38 张麻将牌 atlas 都存在
func test_mahjong_tile_atlas_complete() -> void:
	var prefixes: Array[String] = []
	# 数牌 1m-9m / 1p-9p / 1s-9s
	for suit in ["m", "p", "s"]:
		for i in range(1, 10):
			prefixes.append("%d%s" % [i, suit])
	# 字牌 1z..7z
	for i in range(1, 8):
		prefixes.append("%dz" % i)
	# 赤宝 0m / 0p / 0s + 牌背
	prefixes.append_array(["0m", "0p", "0s", "back"])
	var missing: Array[String] = []
	for key in prefixes:
		var path: String = "res://assets/mahjong_tiles_riichi/%s.png" % key
		if not ResourceLoader.exists(path):
			missing.append(path)
	assert_eq(missing.size(), 0, "38 张牌 atlas 全应存在,缺: %s" % str(missing))
