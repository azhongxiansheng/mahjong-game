class_name FuritenChecker

# 振听判定：纯函数。waits 与 discard_pile 有交集即振听。
# 永久 / 暂时 / 立直振听的状态切换由 FuritenState 维护，本 checker 只判 bool。

static func is_furiten(waits: Array, discard_pile: Array) -> bool:
	for w in waits:
		if w in discard_pile:
			return true
	return false
