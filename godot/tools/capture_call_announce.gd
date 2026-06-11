extends SceneTree

# 一次性视觉验证:CallAnnounce 宣告演出中帧截图。
#   godot --path godot -s tools/capture_call_announce.gd
# 输出 /tmp/shot_announce_*.png

func _initialize() -> void:
	_run()

func _run() -> void:
	root.content_scale_size = Vector2i(1280, 800)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	await process_frame
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.32, 0.20)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	await process_frame

	# 三组:碰(右家)/ 立直(对面)/ 荣和(自家,带占位头像)
	var cases: Array = [
		[&"pon", 1, false, "pon"],
		[&"riichi", 2, false, "riichi"],
		[&"ron", 0, true, "ron"],
		[&"yakuman", 0, false, "yakuman"],
	]
	for c in cases:
		var avatar: Texture2D = null
		if c[2]:
			avatar = load("res://assets/feifan_logo_transparent.png") as Texture2D
		var ca := CallAnnounce.play(bg, c[0], c[1], avatar)
		# 0.45s 处:滑入已完成、光晕/冲击波进行中 — 最佳代表帧
		await create_timer(0.45).timeout
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("/tmp/shot_announce_%s.png" % c[3])
		print("[capture] saved /tmp/shot_announce_%s.png" % c[3])
		if is_instance_valid(ca):
			ca.queue_free()
		await create_timer(0.2).timeout
	quit()
