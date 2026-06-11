extends Control

# F6 手测:CallAnnounce 宣告演出逐个预览。
# 按 1-9 播放 9 种 kind(座位轮换),按 0 四座位同 kind 连播对比方向。

const KINDS: Array = [
	&"chi", &"pon", &"minkan", &"ankan", &"added_kan",
	&"riichi", &"tsumo", &"ron", &"yakuman",
]

var _seat: int = 0

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.32, 0.20)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var hint := Label.new()
	hint.text = "按 1-9 播放: 吃/碰/明杠/暗杠/加杠/立直/自摸/荣和/役満(座位轮换)\n按 0: 四座位方向对比"
	hint.position = Vector2(20, 20)
	add_child(hint)

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := event as InputEventKey
	if k.keycode >= KEY_1 and k.keycode <= KEY_9:
		var idx: int = k.keycode - KEY_1
		CallAnnounce.play(self, KINDS[idx], _seat)
		_seat = (_seat + 1) % 4
	elif k.keycode == KEY_0:
		for s in range(4):
			var captured := s
			get_tree().create_timer(s * 0.35).timeout.connect(func():
				CallAnnounce.play(self, &"pon", captured))
