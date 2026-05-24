extends GutTest

# ConfirmDialog 通用确认对话框测试。


func _make() -> ConfirmDialog:
	return ConfirmDialog.show_dialog("test title", "test message",
		"OK", "Cancel", false)


func test_show_dialog_factory_sets_text() -> void:
	var d := _make()
	add_child_autofree(d)
	await get_tree().process_frame
	# 内部 var 应有 title / message
	assert_eq(d._title, "test title")
	assert_eq(d._message, "test message")
	assert_eq(d._confirm_text, "OK")
	assert_eq(d._cancel_text, "Cancel")


# confirm 按钮 → confirmed signal + 节点 queue_free
func test_confirm_emits_signal() -> void:
	var d := _make()
	add_child(d)
	var emitted := [false]
	d.confirmed.connect(func(): emitted[0] = true)
	await get_tree().process_frame
	d._on_confirm()
	# emitted 立刻 true
	assert_true(emitted[0])
	# 节点应 queue_free,1 帧后 not is_instance_valid
	await get_tree().process_frame
	assert_false(is_instance_valid(d), "queue_free 后失效")


func test_cancel_emits_signal() -> void:
	var d := _make()
	add_child(d)
	var emitted := [false]
	d.cancelled.connect(func(): emitted[0] = true)
	await get_tree().process_frame
	d._on_cancel()
	assert_true(emitted[0])


# Destructive=true → confirm 按钮有猩红 styling
func test_destructive_styling_applied() -> void:
	var d := ConfirmDialog.show_dialog("title", "msg", "DELETE", "Keep", true)
	add_child_autofree(d)
	await get_tree().process_frame
	# 找到 confirm 按钮 — text=DELETE
	var confirm_btn: Button = null
	var stack: Array = [d]
	while not stack.is_empty():
		var node = stack.pop_back()
		for child in node.get_children():
			if child is Button and (child as Button).text == "DELETE":
				confirm_btn = child
			stack.append(child)
	assert_not_null(confirm_btn, "应有 DELETE 按钮")
	# 应有 stylebox override
	var sb = confirm_btn.get_theme_stylebox("normal")
	assert_not_null(sb, "destructive=true 应有 stylebox override")


# 非 destructive 不加猩红
func test_non_destructive_no_red_styling() -> void:
	var d := ConfirmDialog.show_dialog("t", "m", "OK", "Cancel", false)
	add_child_autofree(d)
	await get_tree().process_frame
	# title 颜色应金色不红色
	var lbl: Label = null
	for child in d.get_children():
		for grand in child.get_children():
			if grand is Label and (grand as Label).text == "t":
				lbl = grand
				break
	assert_not_null(lbl)
	var color = lbl.get_theme_color("font_color")
	# 金黄(R=1, G=0.85, B=0.5),不是 红(R=1, G=0.5, B=0.5)
	assert_almost_eq(color.g, 0.85, 0.05)
