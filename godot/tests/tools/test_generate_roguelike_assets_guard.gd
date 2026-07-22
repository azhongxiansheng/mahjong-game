extends GutTest

# 角色输出路径：真实调用 Python 验证函数（不触发付费生成）
# + 多文件旧 IP 文案静态负向扫描
# + 无参数 CLI 安全默认

const SCRIPT_RES := "res://tools/asset_gen/generate_roguelike_assets.py"

const IP_SCAN_FILES: Array = [
	"res://tools/asset_gen/generate_roguelike_assets.py",
	"res://tools/asset_gen/tile_specs.py",
	"res://tools/asset_gen/generate_misc.py",
	"res://tools/asset_gen/generate_sheets.py",
	"res://ui/run_theme.tres",
	"res://ui/run/run_ui.gd",
]

const BANNED_IP_FRAGMENTS: Array = [
	"akagi", "kaiji", "fukumoto", "nobuyuki", "斗牌传说",
	"char_akagi", "char_kaiji", "char_washizu",
	"アカギ", "原著",
]

func test_character_output_defaults_to_staging_subdir():
	var text := _read_text(SCRIPT_RES)
	assert_true(text.find("CHAR_STAGING_DIR") >= 0)
	assert_true(text.find("_staging") >= 0)
	assert_true(text.find("validate_character_output_dir") >= 0
		or text.find("is_forbidden_character_output_dir") >= 0,
		"必须暴露纯路径验证函数")

func test_no_args_must_not_default_to_all_static():
	# 静态锁：无参数不得默认 args.all = True（Red 不执行危险无参命令）
	var text := _read_text(SCRIPT_RES)
	assert_false(text.find("args.all = True") >= 0,
		"无参数不得默认开启 --all 生成")
	assert_true(
		text.find("return 2") >= 0,
		"无参数必须 return 2"
	)
	assert_true(
		text.find("print_help") >= 0,
		"无参数应 print_help"
	)

func test_no_args_prints_help_and_exits_2():
	# Green 后真实执行：无参数 → exit 2 + 帮助文案，不触发生成
	var script_abs := ProjectSettings.globalize_path(SCRIPT_RES)
	var output: Array = []
	var code: int = OS.execute("python3", [script_abs], output, true)
	assert_eq(code, 2, "无参数 exit 应为 2，实际 %s out=%s" % [code, str(output)])
	var joined := "\n".join(output)
	assert_true(
		joined.find("usage:") >= 0
		or joined.find("Generate roguelike") >= 0
		or joined.find("--relics") >= 0
		or joined.find("--all") >= 0,
		"输出应含帮助信息，实际: %s" % joined.substr(0, 400)
	)

func test_path_validation_rejects_production_allows_staging():
	var script_abs := ProjectSettings.globalize_path(SCRIPT_RES)
	var godot_root := ProjectSettings.globalize_path("res://")
	var prod_root := godot_root.path_join("assets/roguelike/characters")
	var prod_nested := prod_root.path_join("nested/sub")
	var staging := godot_root.path_join("tools/asset_gen/_staging/characters")
	var staging_nested := staging.path_join("e1_06_draft")
	var outside_staging := godot_root.path_join("tests/_tmp_character_output")

	assert_eq(_py_check_char_out(script_abs, prod_root), 1,
		"production root 必须拒绝 (exit 1)")
	assert_eq(_py_check_char_out(script_abs, prod_nested), 1,
		"production nested 必须拒绝 (exit 1)")
	assert_eq(_py_check_char_out(script_abs, outside_staging), 1,
		"staging 之外的任意目录必须拒绝 (exit 1)")
	assert_eq(_py_check_char_out(script_abs, staging), 0,
		"默认 staging 必须允许 (exit 0)")
	assert_eq(_py_check_char_out(script_abs, staging_nested), 0,
		"staging 子目录必须允许 (exit 0)")

func test_asset_gen_and_theme_have_no_ip_art_direction_names():
	for path in IP_SCAN_FILES:
		assert_true(FileAccess.file_exists(path), "应存在: %s" % path)
		var text := _read_text(path).to_lower()
		var raw := _read_text(path)
		for bad in BANNED_IP_FRAGMENTS:
			var needle: String = bad
			var hay := raw if (bad.find("斗") >= 0 or bad.find("ア") >= 0 or bad.find("原") >= 0) else text
			assert_false(hay.find(needle) >= 0,
				"%s 不得含旧 IP 指向: %s" % [path, bad])
			if bad.to_lower() != bad:
				assert_false(hay.find(bad.to_lower()) >= 0,
					"%s 不得含旧 IP 指向(lower): %s" % [path, bad])
		if path.ends_with(".py") or path.ends_with(".tres"):
			assert_false(text.find("char_akagi\"") >= 0)
			assert_false(text.find("char_kaiji\"") >= 0)

func test_tile_specs_face_suffix_not_crammed():
	var text := _read_text("res://tools/asset_gen/tile_specs.py")
	# 禁止 is "    "centered 这类挤在同一行的相邻字面量
	assert_false(text.find('is "    "centered') >= 0,
		"tile_specs _FACE_SUFFIX 不得把 is 与 centered 挤在同一字符串字面量")
	assert_true(
		text.find("stands upright, is ") >= 0
		and text.find("\n    \"centered and fills") >= 0,
		"is / centered 应分行相邻拼接"
	)

func _py_check_char_out(script_abs: String, out_dir: String) -> int:
	var output: Array = []
	var code: int = OS.execute(
		"python3",
		[script_abs, "--check-char-out", out_dir],
		output,
		true
	)
	assert_true(code == 0 or code == 1,
		"python --check-char-out 应返回 0/1，实际 %s output=%s" % [code, str(output)])
	return code

func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, path)
	return f.get_as_text()
