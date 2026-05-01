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
var _bought: Array[bool] = [false, false, false, false]
var _current_gold: int = 0
var _slot_buttons: Array[Button] = []

func _ready() -> void:
	if _next_btn:
		_next_btn.pressed.connect(func(): emit_signal("done"))

# ---- public setters ----

# 调用方先调 set_seed_and_gold(seed, gold) 进入；内部刷新 4 槽。
func set_seed_and_gold(seed: int, gold: int) -> void:
	_current_gold = gold
	_results = Gacha.refresh_shop(seed)
	_bought = [false, false, false, false]
	if is_inside_tree():
		_rebuild()

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

static func format_slot_text(result: GachaResult) -> String:
	if result == null:
		return "(空)"
	var name_str: String = ""
	if result.kind == GachaResult.KIND_TILE and result.tile_variant:
		name_str = result.tile_variant.display_name if result.tile_variant.display_name != "" else String(result.tile_variant.id)
	elif result.kind == GachaResult.KIND_ABILITY and result.ability:
		name_str = result.ability.display_name if result.ability.display_name != "" else String(result.ability.id)
	var rarity_label := Rarity.display_name(result.rarity)
	var price := price_for(result)
	return "%s\n[%s]\n💰 %d" % [name_str, rarity_label, price]

# ---- internal ----

func _rebuild() -> void:
	if _gold_label:
		_gold_label.text = format_gold_text(_current_gold)
	if _slots_box == null:
		return
	for child in _slots_box.get_children():
		child.queue_free()
	_slot_buttons.clear()
	for i in range(_results.size()):
		var r: GachaResult = _results[i]
		var btn := Button.new()
		btn.text = format_slot_text(r)
		btn.custom_minimum_size = Vector2(220, 200)
		btn.disabled = _current_gold < price_for(r)
		var captured_index: int = i
		btn.pressed.connect(func(): _on_slot_pressed(captured_index))
		_slots_box.add_child(btn)
		_slot_buttons.append(btn)

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
	_slot_buttons[index].text += "\n(已购)"
	emit_signal("item_bought", index, result)
	# 同步刷新 gold + 其它按钮 disabled
	if _gold_label:
		_gold_label.text = format_gold_text(_current_gold)
	for i in range(_slot_buttons.size()):
		if not _bought[i]:
			_slot_buttons[i].disabled = _current_gold < price_for(_results[i])
