extends SceneTree

const SCENE_PATH := \
	"res://examples/table_2_5d_reference/table_3d_prototype_369.tscn"


func _initialize() -> void:
	root.content_scale_size = Vector2i(1600, 900)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		quit(1)
		return
	root.add_child(packed.instantiate())
	for _index in range(70):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	var phase := OS.get_environment("MAHJONG_369_TABLE_PHASE")
	if phase.is_empty():
		phase = "crowded"
	var view := OS.get_environment("MAHJONG_369_TABLE_VIEW")
	if view.is_empty():
		view = "main"
	var output := OS.get_environment("MAHJONG_369_TABLE_OUTPUT")
	if output.is_empty():
		output = "/tmp/mahjong-issue369-table-3d-%s-%s.png" % [phase, view]
	var error := image.save_png(output)
	print("[capture-369-table3d] phase=", phase, " view=", view,
		" output=", output,
		" size=", image.get_size(), " format=", image.get_format(),
		" error=", error)
	quit(0 if error == OK else 1)
