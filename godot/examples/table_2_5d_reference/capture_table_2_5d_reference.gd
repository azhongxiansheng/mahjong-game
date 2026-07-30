extends SceneTree


func _initialize() -> void:
	root.content_scale_size = Vector2i(1600, 900)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var packed := load("res://examples/table_2_5d_reference/table_2_5d_reference.tscn") as PackedScene
	if packed == null:
		quit(1)
		return
	var midgame = packed.instantiate()
	midgame.fixture_discard_count = 12
	root.add_child(midgame)
	var midgame_error := await _save_after_frames(
		"/tmp/mahjong-issue369-table-2-5d-midgame.png")
	midgame.queue_free()
	await process_frame
	var crowded = packed.instantiate()
	crowded.fixture_discard_count = 18
	root.add_child(crowded)
	var crowded_error := await _save_after_frames(
		"/tmp/mahjong-issue369-table-2-5d-crowded.png")
	quit(0 if midgame_error == OK and crowded_error == OK else 1)


func _save_after_frames(path: String) -> Error:
	for _index in range(40):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	print("[capture-369] ", path, " error=", error)
	return error
