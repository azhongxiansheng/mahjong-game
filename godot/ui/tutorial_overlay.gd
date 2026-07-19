class_name TutorialOverlay extends Control

# 首次启动新手引导 — 5 页文本概览,Prev/Next/Skip 按钮。
# RunFlow._ready 调 if not SettingsManager.tutorial_seen: 弹出。
# 玩家点 Skip 或读完最后一页都会标 settings.tutorial_seen=true → 持久化。
# 玩家也可从 SettingsOverlay "查看新手引导" 按钮重开(覆盖 tutorial_seen)。

signal closed

const PANEL_W: int = 760
const PANEL_H: int = 540

const PAGES: Array = [
	{
		"title": "欢迎来到《麻将王》",
		"body": "本作是 日式麻将 + 肉鸽 的混合作品。\n\n" +
				"每场 Run 由章节地图组成,完成 4 个节点(包括 1 个 Boss) 即通关该章。\n\n" +
				"通关 4 章 → Run 胜利。HP 归零 → Run 失败。\n\n" +
				"按 ESC 随时打开设置面板调节音量、查看战绩。"
	},
	{
		"title": "对战操作 (1/4 — 切牌)",
		"body": "你的座位在屏幕底部(东家或闲家)。\n\n" +
				"摸牌后,点击手牌任意一张切出(或按 D 键切第一张)。\n\n" +
				"立直状态下手牌被锁,只能 tsumogiri (自动切刚摸的牌)。\n\n" +
				"右上角的 toast 会提示重要事件:立直 / 自摸 / 海底 等。"
	},
	{
		"title": "对战操作 (2/4 — 立直/自摸/荣和)",
		"body": "门清听牌时,可点 [立直] 按钮宣告立直(扣 1000 点,胡牌 +1 番)。\n\n" +
				"摸到胡牌张 → 点 [自摸] 按钮宣告。\n\n" +
				"对家弃牌是你的胡牌张 → 点 [荣和] 按钮宣告(无役不能胡)。\n\n" +
				"鸣牌窗口可点 [跳过] 让 AI 继续。"
	},
	{
		"title": "对战操作 (3/4 — 鸣牌)",
		"body": "对家弃的牌可被你鸣:\n\n" +
				"[吃] — 仅可吃上家弃牌,构成顺子(数牌)\n" +
				"[碰] — 任意家弃牌,2 张同手 + 1 张弃组成刻子\n" +
				"[杠] — 任意家弃牌,3 张同手 + 1 张弃组成杠子\n\n" +
				"注意:鸣牌后破门清,无法立直 / 平和 / 一気通貫 减 1 番。"
	},
	{
		"title": "肉鸽元素 (4/4)",
		"body": "角色:选 3 个起始角色之一,各有被动能力(透视/翻倍/抢 dora 等)。\n\n" +
				"卡组:起始包决定初始组合。每节点结算抽奖更新卡池。\n\n" +
				"技能 / 道具 / 遗物:奖励池中随机抽取,影响对战与全局。\n\n" +
				"商店 / 营地 / 事件节点:消费金币 / HP 回复 / 随机奖励或惩罚。"
	}
]

var _current_page: int = 0
var _title_lbl: Label = null
var _body_lbl: Label = null
var _prev_btn: Button = null
var _next_btn: Button = null
var _skip_btn: Button = null
var _page_indicator: Label = null


func _init() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(DT.BG_BASE.r, DT.BG_BASE.g, DT.BG_BASE.b, DT.MODAL_BG_DIM)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var panel := DT.make_centered_panel(PANEL_W, PANEL_H)
	add_child(panel)
	DT.popin(panel)

	_title_lbl = Label.new()
	_title_lbl.position = Vector2(0, 32)
	_title_lbl.size = Vector2(PANEL_W, 50)
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_font_size_override("font_size", DT.FONT_TITLE)
	_title_lbl.add_theme_color_override("font_color", DT.TEXT_TITLE)
	panel.add_child(_title_lbl)

	_body_lbl = Label.new()
	_body_lbl.position = Vector2(40, 100)
	_body_lbl.size = Vector2(PANEL_W - 80, PANEL_H - 200)
	_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_body_lbl.add_theme_font_size_override("font_size", DT.FONT_BODY)
	_body_lbl.add_theme_color_override("font_color", DT.TEXT_PRIMARY)
	panel.add_child(_body_lbl)

	# 底部按钮组
	_prev_btn = Button.new()
	_prev_btn.text = "← 上一页"
	_prev_btn.position = Vector2(40, PANEL_H - 60)
	_prev_btn.custom_minimum_size = Vector2(140, 40)
	_prev_btn.pressed.connect(_on_prev)
	panel.add_child(_prev_btn)

	_page_indicator = Label.new()
	_page_indicator.position = Vector2(0, PANEL_H - 56)
	_page_indicator.size = Vector2(PANEL_W, 32)
	_page_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_indicator.add_theme_font_size_override("font_size", DT.FONT_CAPTION)
	_page_indicator.add_theme_color_override("font_color", DT.TEXT_MUTED)
	panel.add_child(_page_indicator)

	_next_btn = Button.new()
	_next_btn.text = "下一页 →"
	_next_btn.position = Vector2(PANEL_W - 40 - 140, PANEL_H - 60)
	_next_btn.custom_minimum_size = Vector2(140, 40)
	_next_btn.pressed.connect(_on_next)
	panel.add_child(_next_btn)

	_skip_btn = Button.new()
	_skip_btn.text = "跳过引导"
	_skip_btn.position = Vector2(PANEL_W - 40 - 120, 32)
	_skip_btn.custom_minimum_size = Vector2(120, 32)
	_skip_btn.pressed.connect(_on_skip)
	panel.add_child(_skip_btn)

	_render_page()
	z_index = 200


func _render_page() -> void:
	var p: Dictionary = PAGES[_current_page]
	if _title_lbl:
		_title_lbl.text = String(p.get("title", ""))
	if _body_lbl:
		_body_lbl.text = String(p.get("body", ""))
	if _page_indicator:
		_page_indicator.text = "%d / %d" % [_current_page + 1, PAGES.size()]
	if _prev_btn:
		_prev_btn.disabled = (_current_page == 0)
	if _next_btn:
		if _current_page == PAGES.size() - 1:
			_next_btn.text = "开始游戏 ✓"
		else:
			_next_btn.text = "下一页 →"


func _on_prev() -> void:
	if _current_page > 0:
		_current_page -= 1
		_render_page()


func _on_next() -> void:
	if _current_page < PAGES.size() - 1:
		_current_page += 1
		_render_page()
	else:
		_finish()


func _on_skip() -> void:
	_finish()


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo:
			match k.keycode:
				KEY_ESCAPE:
					_finish()
					get_viewport().set_input_as_handled()
				KEY_LEFT:
					_on_prev()
					get_viewport().set_input_as_handled()
				KEY_RIGHT:
					_on_next()
					get_viewport().set_input_as_handled()


# 持久化 tutorial_seen=true,通知 SettingsManager。
func _finish() -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.set_tutorial_seen(true)
	closed.emit()
	queue_free()
