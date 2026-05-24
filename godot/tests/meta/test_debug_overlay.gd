extends GutTest

# DebugOverlay autoload — toggle / refresh 内部状态测试。


func _dbg() -> Node:
	return get_tree().root.get_node("/root/DebugOverlay")


func test_autoload_registered() -> void:
	assert_not_null(_dbg(), "/root/DebugOverlay autoload 应已挂载")


func test_starts_invisible() -> void:
	var d = _dbg()
	# CanvasLayer 初始 visible=false
	assert_false(d._layer.visible, "初始应不可见")


func test_toggle_flips_visibility() -> void:
	var d = _dbg()
	var was: bool = d._visible
	d.toggle()
	assert_eq(d._visible, not was)
	# 复原
	d.toggle()
	assert_eq(d._visible, was)


# _count_nodes 静态递归
func test_count_nodes_static() -> void:
	var root := Node.new()
	add_child_autofree(root)
	var a := Node.new(); root.add_child(a)
	var b := Node.new(); root.add_child(b)
	var c := Node.new(); a.add_child(c)
	# root + a + b + c = 4
	var count: int = _dbg()._count_nodes(root)
	assert_eq(count, 4)


# register_battle_controller 暴露 _active_bc
func test_register_battle_controller_stores_ref() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	var d = _dbg()
	d.register_battle_controller(bc)
	assert_eq(d._active_bc, bc, "register 后 _active_bc 应等于 bc")
	d.unregister_battle_controller(bc)
	assert_null(d._active_bc, "unregister 后 _active_bc 应 null")


# unregister 不同 bc 时不应清空当前的
func test_unregister_different_bc_no_op() -> void:
	var bc1 := BattleController.new(42, 0, false, TileId.E)
	var bc2 := BattleController.new(43, 0, false, TileId.E)
	var d = _dbg()
	d.register_battle_controller(bc1)
	d.unregister_battle_controller(bc2)  # 不应清空 bc1
	assert_eq(d._active_bc, bc1)
	d.unregister_battle_controller(bc1)
	assert_null(d._active_bc)
