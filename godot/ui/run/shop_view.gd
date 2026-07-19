class_name ShopView extends Control

# 麻将王 — 里程碑 5 第 3 步：商店 4 槽 UI（plan-5 D2 第 3 行）
#
# 进入时调 Gacha.refresh_shop(seed) 拿 4 个 GachaResult。每个 Button 显示
# 卡名 + 价格；点击后扣金币 + emit signal("item_bought", index)；玩家
# 点"下一步"emit signal("done")。

signal item_bought(slot_index: int, result: GachaResult)
signal done

# v1 占位价格（rarity → 金币）；M7 平衡时调
const PRICE_BY_RARITY: Array[int] = [10, 25, 60, 150]

@onready var _title: Label = $VBox/Title
@onready var _gold_label: Label = $VBox/GoldLabel
@onready var _slots_box: HBoxContainer = $VBox/SlotsBox
@onready var _next_btn: Button = $VBox/NextBtn

var _results: Array = []  # Array[GachaResult]
var _bought: Array[bool] = []
var _current_gold: int = 0
var _slot_buttons: Array[Button] = []

func _ready() -> void:
	RunUi.attach_background(self)
	RunUi.attach_panel_icon($VBox, "res://assets/run_icons/node_shop.png")
	if _next_btn:
		DT.apply_button_role(_next_btn, DT.BtnRole.PRIMARY)
		_next_btn.pressed.connect(func(): emit_signal("done"))

# ---- public setters ----

# 调用方先调 set_seed_and_gold(seed, gold) 进入；内部刷新 4 槽。
func set_seed_and_gold(seed: int, gold: int) -> void:
	_current_gold = gold
	_results = Gacha.refresh_shop(seed)
	_bought = []
	for i in range(_results.size()):
		_bought.append(false)
	if is_inside_tree():
		_rebuild()

# 购买被外部拒绝（背包满 / 重复遗物）时回滚槽位:取消已购标记、恢复文案、
# 按当前金币恢复可点状态。reason 显示在槽位文案尾行提示玩家原因。
func refund_slot(index: int, reason: String = "") -> void:
	if index < 0 or index >= _bought.size():
		return
	_bought[index] = false
	_current_gold += price_for(_results[index])
	if index < _slot_buttons.size():
		var btn := _slot_buttons[index]
		btn.disabled = _current_gold < price_for(_results[index])
		var lbl := _find_slot_label(btn)
		if lbl:
			lbl.text = format_slot_text(_results[index])
			if reason != "":
				lbl.text += "\n⚠️ %s" % reason

# 玩家在外部扣金币后调用此方法，UI 同步显示
func update_gold(gold: int) -> void:
	_current_gold = gold
	if _gold_label:
		_gold_label.text = format_gold_text(gold)
	# 重新评估按钮 disabled 状态
	for i in range(_slot_buttons.size()):
		_slot_buttons[i].disabled = _bought[i] or _current_gold < price_for(_results[i])

# ---- helpers (static) ----

static func price_for(result: GachaResult) -> int:
	if result == null:
		return 0
	if result.rarity < 0 or result.rarity >= PRICE_BY_RARITY.size():
		return 9999
	return PRICE_BY_RARITY[result.rarity]

static func format_gold_text(gold: int) -> String:
	return "金币: %d" % gold

static func _find_slot_label(btn: Button) -> Label:
	if btn == null:
		return null
	var named := btn.find_child("SlotLabel", true, false)
	if named is Label:
		return named
	# 兼容旧 make_text_card_button：直接子 Label
	if btn.get_child_count() > 0 and btn.get_child(0) is Label:
		return btn.get_child(0) as Label
	return null


static func format_slot_text(result: GachaResult) -> String:
	if result == null:
		return "(空)"
	var name_str: String = ""
	var desc_str: String = ""
	if result.kind == GachaResult.KIND_TILE and result.tile_variant:
		name_str = result.tile_variant.display_name if result.tile_variant.display_name != "" else String(result.tile_variant.id)
		desc_str = result.tile_variant.description
	elif result.kind == GachaResult.KIND_ABILITY and result.ability:
		name_str = result.ability.display_name if result.ability.display_name != "" else String(result.ability.id)
		desc_str = result.ability.description
	elif result.kind == GachaResult.KIND_CONSUMABLE and result.consumable:
		name_str = result.consumable.display_name if result.consumable.display_name != "" else String(result.consumable.id)
		desc_str = result.consumable.description
	elif result.kind == GachaResult.KIND_RELIC and result.relic:
		name_str = result.relic.display_name if result.relic.display_name != "" else String(result.relic.id)
		desc_str = result.relic.description
	var rarity_label := Rarity.display_name(result.rarity)
	var price := price_for(result)
	var text := "%s\n[%s]\n💰 %d" % [name_str, rarity_label, price]
	if desc_str != "":
		text += "\n%s" % desc_str
	return text

# ---- internal ----

func _rebuild() -> void:
	# 槽位数跟 Gacha.refresh_shop 实际返回走，别信 tscn 里的死文案
	if _title:
		_title.text = "商店 — %d 个槽位（明牌可挑选）" % _results.size()
	if _gold_label:
		_gold_label.text = format_gold_text(_current_gold)
	if _slots_box == null:
		return
	for child in _slots_box.get_children():
		child.queue_free()
	_slot_buttons.clear()
	for i in range(_results.size()):
		var r: GachaResult = _results[i]
		var border := Rarity.color(r.rarity) if r else DT.TEXT_MUTED
		var btn := _make_shop_slot_button(r, border)
		_slots_box.add_child(btn)
		btn.disabled = _current_gold < price_for(r)
		var captured_index: int = i
		btn.pressed.connect(func(): _on_slot_pressed(captured_index))
		_slot_buttons.append(btn)
	# 槽位错峰入场,商品"摆上货架"的节奏感
	DT.stagger_in(_slot_buttons, "fade_in_up", 0.25, 0.06)


# 商店槽：大 icon + 价签；仍是 Button（兼容 refund/disabled）
func _make_shop_slot_button(r: GachaResult, border_color: Color) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(230, 300)
	btn.text = ""
	btn.clip_contents = true
	DT.apply_card_button_styles(btn, border_color)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 10
	vbox.offset_right = -10
	vbox.offset_top = 10
	vbox.offset_bottom = -10
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(vbox)
	# 顶条稀有色
	var stripe := ColorRect.new()
	stripe.custom_minimum_size = Vector2(0, 5)
	stripe.color = border_color
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(stripe)
	var icon_path: String = RunUi.resolve_gacha_icon_path(r)
	var icon := RunUi.make_item_icon(icon_path, 88)
	if icon:
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(icon)
	var lbl := Label.new()
	lbl.name = "SlotLabel"
	lbl.text = format_slot_text(r)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", DT.FONT_CAPTION)
	lbl.add_theme_color_override("font_color", DT.TEXT_PRIMARY)
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(lbl)
	return btn


func _on_slot_pressed(index: int) -> void:
	if _bought[index]:
		return
	var result: GachaResult = _results[index]
	var price := price_for(result)
	if _current_gold < price:
		return
	_bought[index] = true
	_current_gold -= price
	_slot_buttons[index].disabled = true
	# 把"(已购)"追加到内嵌 Label,而不是 Button.text(text 是空的)
	var lbl := _find_slot_label(_slot_buttons[index])
	if lbl:
		lbl.text += "\n(已购)"
	emit_signal("item_bought", index, result)
	# 同步刷新 gold + 其它按钮 disabled
	if _gold_label:
		_gold_label.text = format_gold_text(_current_gold)
	for i in range(_slot_buttons.size()):
		if not _bought[i]:
			_slot_buttons[i].disabled = _current_gold < price_for(_results[i])
