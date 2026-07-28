class_name SnapshotModuleRegistry
extends RefCounted

# #241：module_key 唯一的 provider 注册表。
# Worker 侧 serialize/组合；NBC 侧两阶段 stage→commit 原子 restore。
# 不读取、推导或改写模块业务 payload。

const ERR_DUPLICATE_KEY := "SNAPSHOT_MODULE_DUPLICATE"
const ERR_SCHEMA_UNSUPPORTED := "SNAPSHOT_SCHEMA_UNSUPPORTED"
const ERR_RESTORE_FAILED := "SNAPSHOT_RESTORE_FAILED"
const ERR_REQUIRED_MISSING := "SNAPSHOT_REQUIRED_MODULE_MISSING"
const ERR_SERIALIZE_FAILED := "SNAPSHOT_SERIALIZE_FAILED"
const ERR_INVALID := "SNAPSHOT_MODULE_INVALID"


var _providers: Dictionary = {}  # module_key -> SnapshotModuleProvider


static func make_standard() -> SnapshotModuleRegistry:
	var reg := SnapshotModuleRegistry.new()
	var r: Dictionary = reg.register(CoreTableSnapshotProvider.new())
	if not bool(r.get("ok", false)):
		push_error("SnapshotModuleRegistry.make_standard failed: %s" % str(r))
	# #374：匹配元数据（角色 roster）对 STANDARD / TRASH_TALK 均必需。
	var r_meta: Dictionary = reg.register(MatchingMetaSnapshotProvider.new())
	if not bool(r_meta.get("ok", false)):
		push_error("SnapshotModuleRegistry.make_standard matching_meta failed: %s" % str(r_meta))
	return reg


## #252+#253：TRASH_TALK 生产注册表：
## core_table + item_inventory + reward_window + 四个 optional viewer 模块（升序）。
## 不把 AuthorityReplaySnapshot 放入线上协议。
static func make_trash_talk() -> SnapshotModuleRegistry:
	var reg := make_standard()
	var r_inv: Dictionary = reg.register(ItemInventorySnapshotProvider.new())
	if not bool(r_inv.get("ok", false)):
		push_error("SnapshotModuleRegistry.make_trash_talk item_inventory failed: %s" % str(r_inv))
	var r: Dictionary = reg.register(RewardWindowSnapshotProvider.new())
	if not bool(r.get("ok", false)):
		push_error("SnapshotModuleRegistry.make_trash_talk reward_window failed: %s" % str(r))
	var r_prediction: Dictionary = reg.register(ViewerNextDrawSnapshotProvider.new())
	if not bool(r_prediction.get("ok", false)):
		push_error("SnapshotModuleRegistry.make_trash_talk viewer_next_draw failed: %s" \
			% str(r_prediction))
	var r_wall_top: Dictionary = reg.register(ViewerWallTopSnapshotProvider.new())
	if not bool(r_wall_top.get("ok", false)):
		push_error("SnapshotModuleRegistry.make_trash_talk viewer_wall_top failed: %s" \
			% str(r_wall_top))
	var r_forecast: Dictionary = reg.register(ViewerSeatDrawForecastSnapshotProvider.new())
	if not bool(r_forecast.get("ok", false)):
		push_error("SnapshotModuleRegistry.make_trash_talk viewer_seat_draw_forecast failed: %s" \
			% str(r_forecast))
	var r_tenpai: Dictionary = reg.register(ViewerTenpaiWaitsSnapshotProvider.new())
	if not bool(r_tenpai.get("ok", false)):
		push_error("SnapshotModuleRegistry.make_trash_talk viewer_tenpai_waits failed: %s" \
			% str(r_tenpai))
	return reg


func register(provider: SnapshotModuleProvider) -> Dictionary:
	if provider == null:
		return _fail(ERR_INVALID, "null provider")
	var key: String = provider.module_key()
	if key.is_empty():
		return _fail(ERR_INVALID, "empty module_key")
	if int(provider.schema_version()) < 1:
		return _fail(ERR_INVALID, "bad schema_version")
	if _providers.has(key):
		return _fail(ERR_DUPLICATE_KEY, "duplicate module_key: %s" % key)
	_providers[key] = provider
	return _ok()


func has_module(module_key: String) -> bool:
	return _providers.has(module_key)


func provider_for(module_key: String) -> SnapshotModuleProvider:
	if not _providers.has(module_key):
		return null
	return _providers[module_key] as SnapshotModuleProvider


func registered_keys() -> Array:
	var keys: Array = _providers.keys()
	keys.sort()
	return keys


## STANDARD 生产默认：core_table + matching_meta（#374）。
func is_standard_only() -> bool:
	var keys: Array = registered_keys()
	return keys.size() == 2 \
			and str(keys[0]) == CoreTableSnapshotProvider.MODULE_KEY \
			and str(keys[1]) == MatchingMetaSnapshotProvider.MODULE_KEY


## TRASH_TALK：core_table + item/reward + matching_meta + 四个 optional viewer（升序）。
func is_trash_talk_registry() -> bool:
	var keys: Array = registered_keys()
	return keys.size() == 8 \
			and str(keys[0]) == CoreTableSnapshotProvider.MODULE_KEY \
			and str(keys[1]) == ItemInventorySnapshotProvider.MODULE_KEY \
			and str(keys[2]) == MatchingMetaSnapshotProvider.MODULE_KEY \
			and str(keys[3]) == RewardWindowSnapshotProvider.MODULE_KEY \
			and str(keys[4]) == ViewerNextDrawSnapshotProvider.MODULE_KEY \
			and str(keys[5]) == ViewerSeatDrawForecastSnapshotProvider.MODULE_KEY \
			and str(keys[6]) == ViewerTenpaiWaitsSnapshotProvider.MODULE_KEY \
			and str(keys[7]) == ViewerWallTopSnapshotProvider.MODULE_KEY


## 权威侧：按 module_key 升序组合 modules 数组。失败返回 {ok:false,...}。
func serialize_modules(ctx: Dictionary, seat: int) -> Dictionary:
	if seat < 0 or seat > 3:
		return _fail(ERR_SERIALIZE_FAILED, "bad seat")
	var keys: Array = registered_keys()
	if keys.is_empty():
		return _fail(ERR_SERIALIZE_FAILED, "no providers")
	var modules: Array = []
	for k in keys:
		var p: SnapshotModuleProvider = _providers[k] as SnapshotModuleProvider
		var payload: Variant = p.serialize(ctx, seat)
		if payload == null:
			if p.is_required():
				return _fail(ERR_SERIALIZE_FAILED, "serialize failed: %s" % k)
			continue
		# 组合器只包装三键，不改写 payload 内容
		modules.append({
			"module_key": str(k),
			"schema_version": int(p.schema_version()),
			"payload": payload,
		})
	return {"ok": true, "code": "", "message": "", "modules": modules}


## 客户端两阶段原子 restore：
## 1) 全部 can_restore + stage_restore（无 target 副作用）
## 2) capture target → 全部 commit_restore；任一步失败则 restore_module_restore_state 回滚
## 未知未注册模块可解析但不应用。
func restore_modules(modules: Variant, seat: int, target: Object) -> Dictionary:
	if typeof(modules) != TYPE_ARRAY:
		return _fail(ERR_INVALID, "modules not array")
	if seat < 0 or seat > 3:
		return _fail(ERR_INVALID, "bad seat")
	if target == null:
		return _fail(ERR_INVALID, "null target")

	var arr: Array = modules
	var seen: Dictionary = {}
	var staged_steps: Array = []  # {provider, staged}

	for item in arr:
		if typeof(item) != TYPE_DICTIONARY:
			return _fail(ERR_INVALID, "module entry not dict")
		var md: Dictionary = item
		var key: String = str(md.get("module_key", ""))
		if key.is_empty():
			return _fail(ERR_INVALID, "empty module_key")
		if seen.has(key):
			return _fail(ERR_DUPLICATE_KEY, "duplicate in snapshot: %s" % key)
		seen[key] = true
		if not _providers.has(key):
			# 未知未注册：协议可解析，客户端不应用
			continue
		var p: SnapshotModuleProvider = _providers[key] as SnapshotModuleProvider
		var sver: int = int(md.get("schema_version", -1))
		if sver != int(p.schema_version()):
			# 必需 provider：未知版本稳定拒绝；可选 provider：安全跳过不应用
			if p.is_required():
				return _fail(ERR_SCHEMA_UNSUPPORTED, "schema %s@%d" % [key, sver])
			continue
		var payload: Variant = md.get("payload", null)
		if not p.can_restore(payload, seat):
			return _fail(ERR_RESTORE_FAILED, "preflight failed: %s" % key)
		var staged: Variant = p.stage_restore(payload, seat)
		if staged == null:
			return _fail(ERR_RESTORE_FAILED, "stage failed: %s" % key)
		staged_steps.append({"provider": p, "staged": staged})

	# 必需 provider 必须出现
	for k in _providers.keys():
		var p2: SnapshotModuleProvider = _providers[k] as SnapshotModuleProvider
		if p2.is_required() and not seen.has(k):
			return _fail(ERR_REQUIRED_MISSING, "missing required: %s" % k)

	# 有待 commit 时 target 必须在任何 commit 前提供严格 capture/restore
	if not staged_steps.is_empty():
		if not target.has_method("capture_module_restore_state") \
				or not target.has_method("restore_module_restore_state"):
			return _fail(ERR_INVALID, "target missing capture/restore protocol")
		var prev_state: Variant = target.call("capture_module_restore_state")
		for step in staged_steps:
			var p3: SnapshotModuleProvider = step["provider"] as SnapshotModuleProvider
			if not p3.commit_restore(step["staged"], seat, target):
				target.call("restore_module_restore_state", prev_state)
				return _fail(ERR_RESTORE_FAILED, "commit failed: %s" % p3.module_key())
	return _ok()


func _ok() -> Dictionary:
	return {"ok": true, "code": "", "message": ""}


func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
