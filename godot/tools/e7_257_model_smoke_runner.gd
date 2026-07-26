extends Node

# #257：导出 app 内真实 WhisperModelManager 生产下载/校验 runner。
# 由 GameManager 在 E7_257_MODE 非空时挂载；编辑器 SceneTree 入口亦复用本逻辑。
# 环境：E7_257_MODELS_ROOT（必须 /tmp/mahjong-e7-257-*）、E7_257_MODE=download|check


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var models_root := OS.get_environment("E7_257_MODELS_ROOT")
	if models_root.is_empty() or not models_root.begins_with("/tmp/mahjong-e7-257-"):
		push_error("E7_257_MODELS_ROOT must be under /tmp/mahjong-e7-257-*")
		get_tree().quit(2)
		return
	var mode := OS.get_environment("E7_257_MODE")
	if mode.is_empty():
		mode = "check"
	var allow_public := mode == "download"
	var mgr := WhisperModelManager.new()
	add_child(mgr)
	mgr.set_models_root(models_root)
	mgr.apply_production_manifest()
	mgr.set_allow_public_network(allow_public)
	if mode == "download":
		print("E7_257_DOWNLOAD_START root=", models_root)
	mgr.ensure_ready()
	var max_frames := 360000
	var frames := 0
	var last_pct := -1
	while frames < max_frames:
		await get_tree().process_frame
		frames += 1
		var st: StringName = mgr.get_lifecycle_state()
		if st == &"downloading":
			var recv: int = mgr.get_received_bytes()
			var total: int = int(mgr.get_manifest().get("size_bytes", 0))
			var pct := 0
			if total > 0:
				pct = int((float(recv) * 100.0) / float(total))
			if pct != last_pct and (pct % 5 == 0 or frames % 300 == 0):
				print("E7_257_PROGRESS recv=", recv, " total=", total, " pct=", pct)
				last_pct = pct
		if st == &"ready" or st == &"failed" or st == &"cancelled":
			break
	var st2: StringName = mgr.get_lifecycle_state()
	print("E7_257_MANAGER_STATE=", st2)
	print("E7_257_MANAGER_READY=", mgr.is_model_ready())
	print("E7_257_ACTIVE=", mgr.active_model_path())
	print("E7_257_PARTIAL=", mgr.partial_model_path())
	print("E7_257_ERROR=", mgr.get_error_code())
	print("E7_257_RECV=", mgr.get_received_bytes())
	get_tree().quit(0 if st2 == &"ready" else 1)
