extends SceneTree

const DEFAULT_OUTPUT := "/tmp/mahjong-issue369-tile-pose-lab-r1.png"


func _initialize() -> void:
	root.content_scale_size = Vector2i(1600, 900)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var packed := load(
		"res://examples/table_2_5d_reference/tile_pose_lab_369.tscn") as PackedScene
	if packed == null:
		quit(1)
		return
	root.add_child(packed.instantiate())
	for _index in range(50):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	var output := OS.get_environment("MAHJONG_369_POSE_OUTPUT")
	if output.is_empty():
		output = DEFAULT_OUTPUT
	var error := image.save_png(output)
	print("[capture-369-pose] ", output, " size=", image.get_size(),
		" format=", image.get_format(), " error=", error)
	quit(0 if error == OK else 1)
