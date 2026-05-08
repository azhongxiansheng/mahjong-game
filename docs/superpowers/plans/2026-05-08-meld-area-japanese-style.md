# MeldArea 日麻风格副露视觉化实施 plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 4 人桌每个 seat 桌边渲染日麻风格副露（chi/pon/minkan/ankan/added_kan），含来源旋转与暗杠盖牌，替代现有 `seat_panel.tscn` 内的文字 Label `副露: [m×N]`。

**Architecture:** 拆 3 PR：
1. 纯算法 `MeldLayout.compute(meld, claimant_seat) -> Array[Slot]`，无 Godot scene tree 依赖，GUT 单测全覆盖
2. `MeldArea` Node2D 渲染层 + scene smoke harness（F6 手测肉眼验 layout）
3. `four_player_table.tscn` 加 4 个 MeldArea 节点 + 监听 BC events 流的 `TILE_CALLED` 触发刷新；同时 `seat_panel` 弃用 Melds Label

**Tech Stack:** Godot 4.5 / GDScript 2.0 / GUT 9.4.0 测试框架 / TextureExtractor autoload (atlas 切片)

**Spec:** `docs/superpowers/specs/2026-05-08-meld-area-japanese-style-design.md`（PR #146 merged）

---

## File Structure

| 文件 | 动作 | 责任 |
|---|---|---|
| `godot/ui/four_player_table/meld_layout.gd` | 创建 | 纯算法 class：给定 Meld + claimant_seat → Array[Slot] |
| `godot/tests/ui/four_player_table/test_meld_layout.gd` | 创建 | GUT 单测 chi/pon/minkan/ankan/added_kan 各情形 |
| `godot/ui/four_player_table/meld_area.gd` | 创建 | Node2D：set_melds(arr, claimant_seat) → rebuild children |
| `godot/ui/four_player_table/meld_area.tscn` | 创建 | 空 Node2D 节点容器（仅挂 script） |
| `godot/tests/scenes/four_player_table/meld_area_demo.gd` | 创建 | F6 scene driver：4 边各喂模拟 melds 看 layout |
| `godot/tests/scenes/four_player_table/meld_area_demo.tscn` | 创建 | 同上的场景文件 |
| `godot/ui/four_player_table/four_player_table.gd` | 修改 | 监听 BC events / 路由 `TILE_CALLED` → 对应 seat 的 MeldArea |
| `godot/ui/four_player_table/four_player_table.tscn` | 修改 | 加 4 个 MeldArea 节点（与 4 个 DiscardRiver 同结构） |
| `godot/ui/four_player_table/seat_panel.gd` | 修改 | `set_meld_count` 内 Label 设 invisible（弃用文字显示，留接口） |

---

## Chunk 1: PR 1 — MeldLayout 纯算法 + GUT

### Task 1.1: 准备分支 + 测试目录

**Files:**
- Create: `godot/tests/ui/four_player_table/` 目录

- [ ] **Step 1: 拉最新 main + 建分支**

```bash
cd /Users/yesone/project/mahjong-game/.claude/worktrees/wonderful-dhawan-9e76ee
git fetch origin --prune
git checkout -b feat/meld-area-p1-layout-algorithm
git reset --hard origin/main
```

- [ ] **Step 2: 创建测试子目录占位**

```bash
mkdir -p godot/tests/ui/four_player_table
```

### Task 1.2: 写 MeldLayout 失败测（chi 上家来）

**Files:**
- Test: `godot/tests/ui/four_player_table/test_meld_layout.gd`（新）

- [ ] **Step 1: 写第 1 个测**

```gdscript
extends GutTest

# MeldLayout: 纯算法，给定 Meld + claimant_seat → Array[Slot]
# 每 Slot = {tile_id: int, rotated: bool, face_down: bool, stacked_above: bool}

func test_chi_rotated_at_left():
	# CHI 仅来自上家。tiles 升序 [W2, W3, W4]，from_seat = (claimant - 1) % 4
	var tiles: Array[Tile] = [
		Tile.new(TileId.W2),
		Tile.new(TileId.W3),
		Tile.new(TileId.W4),
	]
	var meld := Meld.make_chi(tiles, 3)  # claimant=0, from=3 (上家)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_eq(layout.size(), 3, "3 张牌 3 个 Slot")
	assert_true(layout[0]["rotated"], "上家来 → 第 0 张 rotated")
	assert_false(layout[1]["rotated"])
	assert_false(layout[2]["rotated"])
	for s in layout:
		assert_false(s["face_down"], "chi 不该有 face_down")
		assert_false(s["stacked_above"], "chi 不该有 stacked_above")
```

- [ ] **Step 2: 跑测验证失败**

```bash
godot --headless --path godot --import 2>&1 | tail -2
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/ui/four_player_table -gselect=test_meld_layout -gexit 2>&1 | tail -10
```

Expected: FAIL with `Identifier "MeldLayout" not declared`

### Task 1.3: 实现 MeldLayout 最小骨架（chi 通过）

**Files:**
- Create: `godot/ui/four_player_table/meld_layout.gd`

- [ ] **Step 1: 写 MeldLayout 类骨架**

```gdscript
class_name MeldLayout

# 麻将王 — 副露日麻风格视觉化算法层
#
# 给定 Meld + 副露者 seat id（claimant），返每张牌的渲染 Slot：
#   { tile_id: int, rotated: bool, face_down: bool, stacked_above: bool }
#
# 旋转规则（spec §10 通行日麻）：
#   from_seat 是 claimant 的上家 (claimant-1)%4 → 第 0 张 rotated
#   from_seat 是 claimant 的对家 (claimant+2)%4 → 第 1 张 rotated
#   from_seat 是 claimant 的下家 (claimant+1)%4 → 第 2 张 rotated
#
# Chi 仅允许从上家 → 旋转牌恒第 0 张。
# Ankan 首尾 2 张盖牌（D1 流派），无旋转牌。
# Added-kan 在原 pon 旋转牌正上方叠 1 张同 id 旋转牌。

# 计算 Meld 的渲染 Slot 列表
static func compute(meld: Meld, claimant_seat: int) -> Array:
	match meld.kind:
		Meld.Kind.CHI:
			return _compute_chi(meld)
		Meld.Kind.PON:
			return _compute_pon_or_minkan(meld, claimant_seat, 3)
		Meld.Kind.MINKAN:
			return _compute_pon_or_minkan(meld, claimant_seat, 4)
		Meld.Kind.ANKAN:
			return _compute_ankan(meld)
		Meld.Kind.ADDED_KAN:
			return _compute_added_kan(meld, claimant_seat)
	return []

# Chi: 3 张升序，旋转牌恒第 0 张（仅上家来）
static func _compute_chi(meld: Meld) -> Array:
	var slots: Array = []
	for i in range(meld.tiles.size()):
		slots.append({
			"tile_id": meld.tiles[i].id,
			"rotated": i == 0,
			"face_down": false,
			"stacked_above": false,
		})
	return slots

# Pon/Minkan: 3 或 4 张同 id，按 from_seat 旋转
static func _compute_pon_or_minkan(meld: Meld, claimant_seat: int, count: int) -> Array:
	var rotated_idx: int = _rotated_index_from_source(meld.from_seat, claimant_seat, count)
	var slots: Array = []
	for i in range(count):
		slots.append({
			"tile_id": meld.tiles[i].id,
			"rotated": i == rotated_idx,
			"face_down": false,
			"stacked_above": false,
		})
	return slots

# 来源 → 旋转索引（基于 3 张视角）
# 上家 (claimant-1)%4 → 0；对家 (claimant+2)%4 → 1；下家 (claimant+1)%4 → 2
# 4 张 minkan 同样规则（多出的第 4 张靠最右）
static func _rotated_index_from_source(from_seat: int, claimant_seat: int, _count: int) -> int:
	var diff: int = (from_seat - claimant_seat + 4) % 4
	match diff:
		3: return 0  # 上家
		2: return 1  # 对家
		1: return 2  # 下家
	return 0  # fallback

# Ankan: 4 张同 id，第 0 / 第 3 张 face_down，无旋转牌
static func _compute_ankan(meld: Meld) -> Array:
	var slots: Array = []
	for i in range(4):
		slots.append({
			"tile_id": meld.tiles[i].id,
			"rotated": false,
			"face_down": (i == 0 or i == 3),
			"stacked_above": false,
		})
	return slots

# Added-kan: 4 张同 id；先按原 pon 布局（3 张），再在原 rotated 位置正上方叠 1 张
static func _compute_added_kan(meld: Meld, claimant_seat: int) -> Array:
	var rotated_idx: int = _rotated_index_from_source(meld.from_seat, claimant_seat, 3)
	var slots: Array = []
	# 原 pon 3 张
	for i in range(3):
		slots.append({
			"tile_id": meld.tiles[i].id,
			"rotated": i == rotated_idx,
			"face_down": false,
			"stacked_above": false,
		})
	# 第 4 张：叠在原 rotated 位置上方
	slots.append({
		"tile_id": meld.tiles[3].id,
		"rotated": true,
		"face_down": false,
		"stacked_above": true,
	})
	return slots
```

- [ ] **Step 2: 跑测验证 chi 通过**

```bash
godot --headless --path godot --import 2>&1 | tail -2
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/ui/four_player_table -gselect=test_meld_layout -gexit 2>&1 | tail -10
```

Expected: `1/1 passed`

### Task 1.4: 加 PON 三方向测

**Files:**
- Modify: `godot/tests/ui/four_player_table/test_meld_layout.gd`

- [ ] **Step 1: 加 3 个测**

```gdscript
func test_pon_from_kamicha_rotated_at_left():
	# 上家 = (claimant - 1) % 4. claimant=0, kamicha=3
	var tiles: Array[Tile] = [Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5)]
	var meld := Meld.make_pon(tiles, 3)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_eq(layout.size(), 3)
	assert_true(layout[0]["rotated"], "上家来 → 第 0 张")
	assert_false(layout[1]["rotated"])
	assert_false(layout[2]["rotated"])

func test_pon_from_toimen_rotated_at_middle():
	# 对家 = (claimant + 2) % 4. claimant=0, toimen=2
	var tiles: Array[Tile] = [Tile.new(TileId.S7), Tile.new(TileId.S7), Tile.new(TileId.S7)]
	var meld := Meld.make_pon(tiles, 2)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_false(layout[0]["rotated"])
	assert_true(layout[1]["rotated"], "对家来 → 第 1 张")
	assert_false(layout[2]["rotated"])

func test_pon_from_shimocha_rotated_at_right():
	# 下家 = (claimant + 1) % 4. claimant=0, shimocha=1
	var tiles: Array[Tile] = [Tile.new(TileId.HAKU), Tile.new(TileId.HAKU), Tile.new(TileId.HAKU)]
	var meld := Meld.make_pon(tiles, 1)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_false(layout[0]["rotated"])
	assert_false(layout[1]["rotated"])
	assert_true(layout[2]["rotated"], "下家来 → 第 2 张")
```

- [ ] **Step 2: 跑测**

```bash
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/ui/four_player_table -gselect=test_meld_layout -gexit 2>&1 | tail -10
```

Expected: `4/4 passed`

### Task 1.5: 加 MINKAN 4 张测

**Files:**
- Modify: `godot/tests/ui/four_player_table/test_meld_layout.gd`

- [ ] **Step 1: 加测**

```gdscript
func test_minkan_4_tiles_rotated_per_source():
	# MINKAN 4 张同 id，旋转索引规则同 PON
	var tiles: Array[Tile] = [
		Tile.new(TileId.T9), Tile.new(TileId.T9),
		Tile.new(TileId.T9), Tile.new(TileId.T9),
	]
	# 对家来 → 第 1 张 rotated
	var meld := Meld.make_minkan(tiles, 2)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_eq(layout.size(), 4, "MINKAN 4 张 4 个 Slot")
	assert_false(layout[0]["rotated"])
	assert_true(layout[1]["rotated"])
	assert_false(layout[2]["rotated"])
	assert_false(layout[3]["rotated"])
	for s in layout:
		assert_false(s["face_down"], "MINKAN 不该有 face_down")
```

- [ ] **Step 2: 跑测**

```bash
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/ui/four_player_table -gselect=test_meld_layout -gexit 2>&1 | tail -10
```

Expected: `5/5 passed`

### Task 1.6: 加 ANKAN 测

**Files:**
- Modify: `godot/tests/ui/four_player_table/test_meld_layout.gd`

- [ ] **Step 1: 加 2 个测**

```gdscript
func test_ankan_face_down_outer_two():
	# 暗杠 4 张同 id，第 0 / 第 3 张 face_down（D1 流派）
	var tiles: Array[Tile] = [
		Tile.new(TileId.W1), Tile.new(TileId.W1),
		Tile.new(TileId.W1), Tile.new(TileId.W1),
	]
	var meld := Meld.make_ankan(tiles)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_eq(layout.size(), 4)
	assert_true(layout[0]["face_down"], "第 0 张 face_down")
	assert_false(layout[1]["face_down"], "第 1 张正面")
	assert_false(layout[2]["face_down"], "第 2 张正面")
	assert_true(layout[3]["face_down"], "第 3 张 face_down")
	for s in layout:
		assert_false(s["rotated"], "ankan 无旋转牌")

func test_ankan_no_dependency_on_claimant_seat():
	# 暗杠不来自任何人，claimant_seat 不影响 layout
	var tiles: Array[Tile] = [
		Tile.new(TileId.E), Tile.new(TileId.E),
		Tile.new(TileId.E), Tile.new(TileId.E),
	]
	var meld := Meld.make_ankan(tiles)
	var layout_a: Array = MeldLayout.compute(meld, 0)
	var layout_b: Array = MeldLayout.compute(meld, 2)
	for i in range(4):
		assert_eq(layout_a[i]["face_down"], layout_b[i]["face_down"],
			"ankan layout 不随 claimant_seat 变化")
```

- [ ] **Step 2: 跑测**

```bash
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/ui/four_player_table -gselect=test_meld_layout -gexit 2>&1 | tail -10
```

Expected: `7/7 passed`

### Task 1.7: 加 ADDED_KAN 测

**Files:**
- Modify: `godot/tests/ui/four_player_table/test_meld_layout.gd`

- [ ] **Step 1: 加 2 个测**

```gdscript
func test_added_kan_4_slots_with_stacked():
	# 加杠 = 原 pon 3 张 + 第 4 张叠在 rotated 位置上方
	# 上家 来源（rotated_idx=0），加杠后第 4 个 slot stacked_above=true 且 rotated=true
	var tiles: Array[Tile] = [
		Tile.new(TileId.S5), Tile.new(TileId.S5),
		Tile.new(TileId.S5), Tile.new(TileId.S5),
	]
	var meld := Meld.make_added_kan(tiles, 3)  # claimant=0, from=上家
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_eq(layout.size(), 4, "加杠 4 个 Slot")
	# 原 pon 3 张
	assert_true(layout[0]["rotated"], "原 rotated 仍在 idx 0")
	assert_false(layout[1]["rotated"])
	assert_false(layout[2]["rotated"])
	assert_false(layout[0]["stacked_above"])
	# 第 4 张：叠加 + 旋转
	assert_true(layout[3]["stacked_above"], "第 4 张 stacked_above")
	assert_true(layout[3]["rotated"], "第 4 张 rotated")
	assert_false(layout[3]["face_down"])

func test_added_kan_stacked_position_matches_source():
	# 对家来 → rotated_idx=1；加杠 stacked 仍是第 4 个 Slot；rendering 时叠在 idx=1 上方
	var tiles: Array[Tile] = [
		Tile.new(TileId.T3), Tile.new(TileId.T3),
		Tile.new(TileId.T3), Tile.new(TileId.T3),
	]
	var meld := Meld.make_added_kan(tiles, 2)  # 对家
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_true(layout[1]["rotated"], "对家来 → idx 1 rotated")
	assert_true(layout[3]["stacked_above"])
	assert_true(layout[3]["rotated"])
```

- [ ] **Step 2: 跑测**

```bash
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/ui/four_player_table -gselect=test_meld_layout -gexit 2>&1 | tail -10
```

Expected: `9/9 passed`

### Task 1.8: 加 tile_id 顺序保持测

**Files:**
- Modify: `godot/tests/ui/four_player_table/test_meld_layout.gd`

- [ ] **Step 1: 加测**

```gdscript
func test_tile_ids_preserved_in_order():
	# CHI 顺子 tile_id 顺序保持（W2 → W3 → W4）
	var tiles: Array[Tile] = [
		Tile.new(TileId.W2),
		Tile.new(TileId.W3),
		Tile.new(TileId.W4),
	]
	var meld := Meld.make_chi(tiles, 3)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_eq(int(layout[0]["tile_id"]), TileId.W2)
	assert_eq(int(layout[1]["tile_id"]), TileId.W3)
	assert_eq(int(layout[2]["tile_id"]), TileId.W4)
```

- [ ] **Step 2: 跑测验证 10/10**

```bash
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/ui/four_player_table -gselect=test_meld_layout -gexit 2>&1 | tail -10
```

Expected: `10/10 passed`

### Task 1.9: 跑全套 GUT 防回归

- [ ] **Step 1: 全套 GUT**

```bash
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -ginclude_subdirs -gexit 2>&1 | grep -E "Tests|Passing|All tests"
```

Expected: `All tests passed!` 数量 = 现 main 数 + 10

### Task 1.10: 提交 + PR + merge

- [ ] **Step 1: 加 + commit + push**

```bash
git add godot/ui/four_player_table/meld_layout.gd \
        godot/ui/four_player_table/meld_layout.gd.uid \
        godot/tests/ui/four_player_table/test_meld_layout.gd \
        godot/tests/ui/four_player_table/test_meld_layout.gd.uid

git commit -m "$(cat <<'EOF'
feat(ui/m12): MeldLayout 纯算法 — 副露日麻风格 Slot 计算

接 spec docs/superpowers/specs/2026-05-08-meld-area-japanese-style-design.md
（PR #146）。给定 Meld + claimant_seat → Array[Slot]：
- chi: 3 张升序，旋转牌恒第 0 张
- pon/minkan: 按 from_seat 上家=0 / 对家=1 / 下家=2 旋转
- ankan: 第 0/3 face_down（D1 流派）
- added_kan: 原 pon + 第 4 张 stacked_above + rotated

10 GUT 测覆盖 chi/pon/minkan/ankan/added_kan 各情形 + claimant_seat
不影响 ankan + tile_id 顺序保持。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"

git push -u origin feat/meld-area-p1-layout-algorithm
```

- [ ] **Step 2: 创建 PR**

```bash
gh pr create --title "feat(ui/m12): MeldLayout 纯算法 + GUT (副露视觉化第 1 步)" --body "$(cat <<'EOF'
## Summary

接 spec PR #146（merged）。第 1 步：纯算法层，无 Godot scene tree 依赖。

## API

\`\`\`gdscript
MeldLayout.compute(meld: Meld, claimant_seat: int) -> Array[Slot]
# Slot = {tile_id: int, rotated: bool, face_down: bool, stacked_above: bool}
\`\`\`

## 旋转规则

| from_seat 相对 claimant | rotated 索引 |
|---|---|
| 上家 (claimant-1)%4 | 第 0 张 |
| 对家 (claimant+2)%4 | 第 1 张 |
| 下家 (claimant+1)%4 | 第 2 张 |

CHI 仅上家来。ANKAN 第 0/3 face_down（D1 流派）。ADDED_KAN 第 4 张 stacked_above + rotated。

## Test plan

- [x] 10 GUT 测：chi 上家 / pon 三方向 / minkan / ankan 双测（含 claimant 不变性）/ added_kan 双测 / tile_id 顺序保持
- [x] 全套 GUT 0 回归

## 后续

PR 2: MeldArea Node2D 渲染层。
PR 3: four_player_table 接入 TILE_CALLED 监听。

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: merge**

```bash
gh pr merge $(gh pr list --head feat/meld-area-p1-layout-algorithm --json number --jq '.[0].number') --squash
```

---

## Chunk 2: PR 2 — MeldArea Node2D 渲染 + scene smoke

### Task 2.1: 准备分支

- [ ] **Step 1: 拉最新 main + 建分支**

```bash
git fetch origin --prune
git checkout -b feat/meld-area-p2-rendering
git reset --hard origin/main
```

### Task 2.2: MeldArea 类骨架

**Files:**
- Create: `godot/ui/four_player_table/meld_area.gd`
- Create: `godot/ui/four_player_table/meld_area.tscn`

- [ ] **Step 1: 写 meld_area.gd**

```gdscript
class_name MeldArea extends Node2D

# 麻将王 — 副露日麻风格视觉渲染（单 seat 用）
#
# Node2D 旋转 0/-90/180/+90 让面朝桌心；4 桌边各 1 个实例。
# 内部按 MeldLayout.compute(...) 的 Slot 描述摆 TextureRect 子节点。
# 多组 meld 累积横排（最早的在最右；新加的在最左 — 标准日麻"副露往左推"）

const TILE_W: int = 32
const TILE_H: int = 48
const MELD_GAP: int = 8       # 多组 meld 之间间距

var _seat_id: int = -1
var _melds: Array = []        # Array[Meld]

# claimant_seat = self._seat_id；分开存便于测
func set_melds(melds: Array, claimant_seat: int) -> void:
	_seat_id = claimant_seat
	_melds = melds
	_rebuild()

func _rebuild() -> void:
	if not is_inside_tree():
		return
	# 清空旧 children
	for child in get_children():
		child.queue_free()
	if _melds.is_empty():
		return
	var extractor: Node = get_tree().root.get_node_or_null("TextureExtractor")
	if extractor == null:
		return
	# 先算总宽：从右往左累积，最早 meld 在最右
	var x_cursor: float = 0.0
	for meld_idx in range(_melds.size()):
		var meld: Meld = _melds[meld_idx]
		var slots: Array = MeldLayout.compute(meld, _seat_id)
		x_cursor = _render_meld(slots, x_cursor)
		x_cursor -= MELD_GAP

# 在 x_cursor 起点（最右侧）从右往左渲染 1 组 meld；返新 x_cursor（更靠左）
func _render_meld(slots: Array, x_start: float) -> float:
	var x: float = x_start
	# 先收集占用宽度（一张正常 = TILE_W；旋转 = TILE_H 横置；stacked_above 不占新宽）
	for i in range(slots.size() - 1, -1, -1):  # 从右往左摆
		var slot: Dictionary = slots[i]
		if bool(slot["stacked_above"]):
			# 叠在前 1 张同位置上方；不占新宽
			# 找前 1 个 rotated slot 位置叠上去
			continue
		var w: float = TILE_H if bool(slot["rotated"]) else TILE_W
		x -= w
		_spawn_tile(slot, x)
	# 处理 stacked_above 牌：叠在某张 rotated 牌上方
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		if not bool(slot["stacked_above"]):
			continue
		# 找该 meld 内第 1 个 rotated 牌的 x（不含 stacked 自己）
		var anchor_x: float = _find_rotated_anchor_x(slots, x_start)
		_spawn_tile(slot, anchor_x, -TILE_W)  # 上方偏移 -TILE_W（视觉叠加）
	return x

# 在 (x, y_offset) 摆 1 张 tile 子节点
func _spawn_tile(slot: Dictionary, x: float, y_offset: float = 0.0) -> void:
	var tex_rect := TextureRect.new()
	if bool(slot["face_down"]):
		# 用 CardTileBack 背面；简化为放置占位 ColorRect 等也可
		var bg := ColorRect.new()
		bg.size = Vector2(TILE_W, TILE_H)
		bg.color = Color(0.15, 0.15, 0.20)
		bg.position = Vector2(x, y_offset)
		add_child(bg)
		return
	var extractor = get_tree().root.get_node_or_null("TextureExtractor")
	var key: String = CardTileBack.tile_id_to_atlas_key(int(slot["tile_id"]))
	if key == "" or extractor == null:
		return
	var tex = extractor.get_tile_texture(key)
	if tex == null:
		return
	tex_rect.texture = tex
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	tex_rect.size = Vector2(TILE_W, TILE_H)
	tex_rect.position = Vector2(x, y_offset)
	if bool(slot["rotated"]):
		tex_rect.pivot_offset = Vector2(TILE_W / 2.0, TILE_H / 2.0)
		tex_rect.rotation_degrees = 90.0
		# 旋转后实际占 TILE_H 宽 × TILE_W 高；视觉上从 x 向右占 TILE_H
		tex_rect.position = Vector2(x, y_offset + (TILE_H - TILE_W) / 2.0)
	add_child(tex_rect)

# 给定 slots，找已渲染好的 rotated 牌 x（用于 stacked_above 锚定）
func _find_rotated_anchor_x(slots: Array, x_start: float) -> float:
	var x: float = x_start
	for i in range(slots.size() - 1, -1, -1):
		var slot: Dictionary = slots[i]
		if bool(slot["stacked_above"]):
			continue
		var w: float = TILE_H if bool(slot["rotated"]) else TILE_W
		x -= w
		if bool(slot["rotated"]):
			return x
	return x_start
```

> ⚠️ **注**：执行此 Task 时，先 grep 确认 `TextureExtractor.get_tile_texture(key)` 接口名（可能是 `get_atlas_texture` 等）；如名字不同，按现有接口调整。可参考 `discard_river.gd` 的调用方式。

- [ ] **Step 2: 写 meld_area.tscn**

```text
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://ui/four_player_table/meld_area.gd" id="1"]

[node name="MeldArea" type="Node2D"]
script = ExtResource("1")
```

- [ ] **Step 3: 跑 import 让 class_name 注册**

```bash
godot --headless --path godot --import 2>&1 | tail -2
```

### Task 2.3: 写 scene smoke harness

**Files:**
- Create: `godot/tests/scenes/four_player_table/meld_area_demo.gd`
- Create: `godot/tests/scenes/four_player_table/meld_area_demo.tscn`

- [ ] **Step 1: 写 demo.gd**

```gdscript
extends Node2D

# F6 手测：4 桌边各 1 个 MeldArea，喂模拟 melds 看 layout 对不对
# 跑法：editor 中打开 .tscn，按 F6
#
# 期待视觉：
#   底（玩家）= PON 上家来（左旋转） + ANKAN（首尾盖牌）
#   右   = MINKAN 对家来（中旋转）
#   上（对家）= CHI 上家来（左旋转）
#   左   = ADDED_KAN（旋转牌上方再叠 1 张）

const MeldAreaScene = preload("res://ui/four_player_table/meld_area.tscn")

func _ready() -> void:
	# 底（玩家 seat 0）
	_spawn(Vector2(640, 600), 0.0, _player_melds(), 0)
	# 右（seat 1）
	_spawn(Vector2(1100, 360), -90.0, _shimocha_melds(), 1)
	# 上（seat 2）
	_spawn(Vector2(640, 100), 180.0, _toimen_melds(), 2)
	# 左（seat 3）
	_spawn(Vector2(180, 360), 90.0, _kamicha_melds(), 3)

func _spawn(pos: Vector2, rot_deg: float, melds: Array, seat_id: int) -> void:
	var area: MeldArea = MeldAreaScene.instantiate()
	area.position = pos
	area.rotation_degrees = rot_deg
	add_child(area)
	area.set_melds(melds, seat_id)

func _player_melds() -> Array:
	# PON 上家来（W5）+ ANKAN（T9）
	var pon_tiles: Array[Tile] = [
		Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5),
	]
	var ankan_tiles: Array[Tile] = [
		Tile.new(TileId.T9), Tile.new(TileId.T9),
		Tile.new(TileId.T9), Tile.new(TileId.T9),
	]
	return [Meld.make_pon(pon_tiles, 3), Meld.make_ankan(ankan_tiles)]

func _shimocha_melds() -> Array:
	# MINKAN 对家来（HAKU）— claimant=1, toimen=3
	var tiles: Array[Tile] = [
		Tile.new(TileId.HAKU), Tile.new(TileId.HAKU),
		Tile.new(TileId.HAKU), Tile.new(TileId.HAKU),
	]
	return [Meld.make_minkan(tiles, 3)]

func _toimen_melds() -> Array:
	# CHI 上家来 — claimant=2, kamicha=1
	var tiles: Array[Tile] = [
		Tile.new(TileId.S2), Tile.new(TileId.S3), Tile.new(TileId.S4),
	]
	return [Meld.make_chi(tiles, 1)]

func _kamicha_melds() -> Array:
	# ADDED_KAN 上家来 — claimant=3, kamicha=2
	var tiles: Array[Tile] = [
		Tile.new(TileId.W7), Tile.new(TileId.W7),
		Tile.new(TileId.W7), Tile.new(TileId.W7),
	]
	return [Meld.make_added_kan(tiles, 2)]
```

- [ ] **Step 2: 写 .tscn**

```text
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/scenes/four_player_table/meld_area_demo.gd" id="1"]

[node name="MeldAreaDemo" type="Node2D"]
script = ExtResource("1")

[node name="Bg" type="ColorRect" parent="."]
offset_right = 1280.0
offset_bottom = 720.0
color = Color(0.05, 0.18, 0.05, 1)
```

- [ ] **Step 3: 跑 import 防 cache 问题**

```bash
godot --headless --path godot --import 2>&1 | tail -2
```

### Task 2.4: 全套 GUT 防回归

- [ ] **Step 1: 跑全套**

```bash
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -ginclude_subdirs -gexit 2>&1 | grep -E "Tests|Passing|All tests"
```

Expected: `All tests passed!`，数量与 PR 1 后相同（本 PR 不加 GUT）

### Task 2.5: 提交 + PR + merge

- [ ] **Step 1: stage + commit + push**

```bash
git add godot/ui/four_player_table/meld_area.gd \
        godot/ui/four_player_table/meld_area.gd.uid \
        godot/ui/four_player_table/meld_area.tscn \
        godot/ui/four_player_table/meld_area.tscn.uid \
        godot/tests/scenes/four_player_table/meld_area_demo.gd \
        godot/tests/scenes/four_player_table/meld_area_demo.gd.uid \
        godot/tests/scenes/four_player_table/meld_area_demo.tscn \
        godot/tests/scenes/four_player_table/meld_area_demo.tscn.uid

git commit -m "$(cat <<'EOF'
feat(ui/m12): MeldArea Node2D 渲染层 + scene smoke

接 PR (chunk 1) MeldLayout 算法层。

- meld_area.gd / .tscn：Node2D 单 seat 副露视觉容器；set_melds(arr, seat) 调
  MeldLayout.compute → 渲染 TextureRect 子节点；多组 meld 从右往左累积；
  ankan 第 0/3 面盖；added_kan 在原旋转牌上方叠加；旋转 pivot 居中
- meld_area_demo.tscn / .gd：F6 手测，4 桌边各喂模拟 melds（PON+ANKAN /
  MINKAN / CHI / ADDED_KAN）肉眼验 layout

不在覆盖：face_down 用 ColorRect 占位（CardTileBack 背面纹理留 PR 3 接入
TILE_CALLED 时一并整合）。

GUT 0 回归。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"

git push -u origin feat/meld-area-p2-rendering
```

- [ ] **Step 2: 创建 PR + merge**

```bash
gh pr create --title "feat(ui/m12): MeldArea Node2D 渲染 + scene smoke (副露视觉化第 2 步)" --body "$(cat <<'EOF'
## Summary

接 chunk 1 MeldLayout 算法层。提供 Node2D 渲染容器：

- \`set_melds(arr, claimant_seat)\` → 调 MeldLayout.compute → 摆 TextureRect 子节点
- 多组 meld 从右往左累积（标准日麻"副露往左推"）
- 每张牌：旋转的 90°（pivot 居中避免位移）/ 盖牌占位 / stacked_above 叠加

## Scene smoke

\`tests/scenes/four_player_table/meld_area_demo.tscn\`：4 桌边各喂模拟 melds，F6 看 layout 对：
- 底（玩家）= PON 上家 + ANKAN
- 右 = MINKAN 对家
- 上 = CHI 上家
- 左 = ADDED_KAN 上家

## Test plan

- [x] GUT 0 回归
- [ ] F6 手测 layout 视觉验证（reviewer 跑 demo.tscn 看是否日麻样）

## 后续

PR 3: four_player_table 监听 TILE_CALLED → 触发 4 个 MeldArea 刷新。
弃用 seat_panel 内 \`副露: [m×N]\` Label。

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"

gh pr merge $(gh pr list --head feat/meld-area-p2-rendering --json number --jq '.[0].number') --squash
```

---

## Chunk 3: PR 3 — four_player_table 接入 TILE_CALLED + seat_panel Label 弃用

### Task 3.1: 准备分支

- [ ] **Step 1: 拉最新 main + 建分支**

```bash
git fetch origin --prune
git checkout -b feat/meld-area-p3-integration
git reset --hard origin/main
```

### Task 3.2: 调研现 four_player_table 监听 BC events 路径

- [ ] **Step 1: 找 events 路由代码**

```bash
grep -n "events\|TILE_DISCARDED\|TILE_CALLED\|TILE_DRAWN" \
  godot/ui/four_player_table/four_player_table.gd \
  godot/ui/four_player_table/playable_table.gd 2>/dev/null | head -20
```

> ⚠️ **注**：观察 discard_river 是如何在 events 流中收到弃牌事件的。本 PR 跟同一个路由模式接 `TILE_CALLED` 即可（spec §3.6 数据流图）。如果发现 discard_river 不是直接听 events 而是通过 polling `seat.discards`，则 MeldArea 也走 polling `seat.melds` —— 跟同模式。

- [ ] **Step 2: 找 BC.events emit TILE_CALLED 的地方**

```bash
grep -n "TILE_CALLED" godot/battle/*.gd godot/core/turn_engine/*.gd 2>/dev/null
```

Expected: 发现 BC._emit(&"TILE_CALLED", ...) 或 turn_engine 内 emit 路径。

### Task 3.3: 改 four_player_table.tscn 加 4 个 MeldArea 节点

**Files:**
- Modify: `godot/ui/four_player_table/four_player_table.tscn`

> ⚠️ **注**：本 task 改 .tscn 文件结构，建议在 Godot 编辑器中操作（直接 sed 改 tscn 容易破坏 SubResource 引用）。如执行环境无 GUI，改用 minimal 的 sed 加 4 个 Node2D 节点声明（参考 DiscardRiver 的 4 处节点写法）。

- [ ] **Step 1: 加 4 个 MeldArea 节点（与 4 个 DiscardRiver 同结构）**

具体做法：
1. 编辑器打开 `four_player_table.tscn`
2. 找到 4 个 DiscardRiver 节点（每边 1 个）
3. 在每个 DiscardRiver **同级旁** 加 1 个 MeldArea 节点：name 形如 `MeldArea_Bottom` / `MeldArea_Right` / `MeldArea_Top` / `MeldArea_Left`
4. 4 个 MeldArea 的 position / rotation_degrees 复用 four_player_table.gd 内 `_river_layout_for_seat()` 的同样逻辑（同 seat → 同方位），但 position 偏移到手牌右下角（spec §3.2）
5. 保存

- [ ] **Step 2: 跑 import**

```bash
godot --headless --path godot --import 2>&1 | tail -2
```

### Task 3.4: 改 four_player_table.gd 监听 TILE_CALLED

**Files:**
- Modify: `godot/ui/four_player_table/four_player_table.gd`

- [ ] **Step 1: 加 4 个 MeldArea 节点引用 + 路由**

```gdscript
# 在 _ready 或 setup 函数中拿 4 个 MeldArea 引用：
@onready var _meld_areas: Array[MeldArea] = [
	$MeldArea_Bottom,
	$MeldArea_Right,
	$MeldArea_Top,
	$MeldArea_Left,
]

# 在现有 BC events 路由函数中（grep TILE_DISCARDED 看在哪），加：
func _on_event(ev: BattleEvent) -> void:
	# ...现有 TILE_DRAWN / TILE_DISCARDED 处理...
	if ev.type == &"TILE_CALLED":
		var claimant: int = ev.actor_seat
		if claimant >= 0 and claimant < 4 and _meld_areas[claimant] != null:
			# state.seats[claimant].melds 已被 turn_engine.apply_chi/pon/minkan 更新
			var melds: Array = _state.seats[claimant].melds  # 实际字段名按代码取
			_meld_areas[claimant].set_melds(melds, claimant)
```

> ⚠️ **注**：`_state` / `state` / `_battle_state` 实际字段名按 four_player_table.gd 当前用法取（grep `state.seats`）。如果 four_player_table 不直接持 state，按现有 discard_river 同样的拿数据方式调用。

- [ ] **Step 2: import + 跑 GUT**

```bash
godot --headless --path godot --import 2>&1 | tail -2
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -ginclude_subdirs -gexit 2>&1 | grep -E "Tests|Passing|All tests"
```

Expected: 0 回归

### Task 3.5: 弃用 seat_panel Melds Label

**Files:**
- Modify: `godot/ui/four_player_table/seat_panel.gd`

- [ ] **Step 1: 改 set_meld_count 让 Label 隐藏**

```gdscript
func set_meld_count(n: int) -> void:
	_meld_count = n
	if _label_melds != null:
		# spec 2026-05-08 MeldArea：副露已用 MeldArea 视觉化，弃用此文字 Label。
		# 保留 set_meld_count 接口防 callers break；将来可彻底删 Label 节点。
		_label_melds.visible = false
```

- [ ] **Step 2: 跑 GUT 防回归**

```bash
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -ginclude_subdirs -gexit 2>&1 | grep -E "Tests|Passing|All tests"
```

Expected: 0 回归。如有 test 断言 `_label_melds.text` 内容，改成检查 `visible == false`。

### Task 3.6: 玩家手测 F5 跑一局触发 chi/pon

- [ ] **Step 1: 编辑器打开项目跑主场景 (RunFlow)**

```bash
godot --path godot
```

- [ ] **Step 2: 触发玩家 chi 或 pon**

操作：
1. starter pick → 进章节地图 → 点战斗节点
2. 等到 AI 切牌时若手牌可吃，player_action_panel 弹按钮
3. 点 chi 或 pon 按钮
4. 看玩家自家（底边）MeldArea 是否出现该 meld，旋转牌位置正确（chi 上家来 → 左；pon 按 from_seat 映射）

- [ ] **Step 3: 截屏附 PR 描述（可选）**

如果手测 OK，记录"玩家 F5 手测 1 次 PON / 1 次 CHI 触发，副露牌正确显示"作为 PR 描述补充。

### Task 3.7: 提交 + PR + merge

- [ ] **Step 1: stage + commit + push**

```bash
git add godot/ui/four_player_table/four_player_table.gd \
        godot/ui/four_player_table/four_player_table.tscn \
        godot/ui/four_player_table/seat_panel.gd

git commit -m "$(cat <<'EOF'
feat(ui/m12): four_player_table 接入 MeldArea + 弃用 seat_panel 文字 Label

接 chunk 1+2（MeldLayout + MeldArea）。最后一步：

- four_player_table.tscn 加 4 个 MeldArea 节点（与 4 个 DiscardRiver 同结构）
- four_player_table.gd 监听 BC.events 流；TILE_CALLED → 对应 seat 的 MeldArea
  调 set_melds(seat.melds, seat_id) 重建子节点
- seat_panel.gd: set_meld_count 内 Label 隐藏（保留接口防 callers break）

玩家 F5 手测：触发 PON / CHI 后副露牌真显示，旋转位置匹配 from_seat。

闭合 spec docs/superpowers/specs/2026-05-08-meld-area-japanese-style-design.md。

GUT 0 回归。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"

git push -u origin feat/meld-area-p3-integration
```

- [ ] **Step 2: 创建 PR + merge**

```bash
gh pr create --title "feat(ui/m12): four_player_table 接入 MeldArea + 弃用 seat_panel 文字 Label (副露视觉化第 3 步收尾)" --body "$(cat <<'EOF'
## Summary

接 chunks 1+2 (MeldLayout 算法 + MeldArea 渲染)。最后一步：

- \`four_player_table.tscn\` 加 4 个 MeldArea 节点
- \`four_player_table.gd\` 监听 BC events / 路由 \`TILE_CALLED\` → MeldArea 刷新
- \`seat_panel.gd\` 弃用 \`副露: [m×N]\` Label（保留 set_meld_count 接口防 callers break）

闭合 spec PR #146（merged）+ chunks 1/2 实现。

## 验证

- [x] GUT 0 回归
- [x] 玩家 F5 手测：PON / CHI 触发 → 副露牌实际显示，旋转位置正确

## 后续（spec 列出范围）

- AI 主动 chi/pon — 单独 PR
- 玩家 chi companion 手选 UI — 单独 PR
- 副露红 dora 标识 — 单独 PR
- 副露动画（牌从弃牌河飞到副露区）— 单独 PR

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"

gh pr merge $(gh pr list --head feat/meld-area-p3-integration --json number --jq '.[0].number') --squash
```

---

## Final Verification

### Task 4.1: 验收 spec 全部完成

- [ ] **Step 1: 拉最新 main**

```bash
git fetch origin --prune
git checkout main 2>/dev/null || git checkout -b _verify origin/main
git reset --hard origin/main
```

- [ ] **Step 2: 玩家手测**

跑 `godot --path godot`，启动 RunFlow，触发若干 chi/pon/minkan 看副露视觉是否合 spec：
- 上家来 → 左旋转 ✅
- 对家来 → 中旋转 ✅
- 下家来 → 右旋转 ✅
- 暗杠 → 首尾盖牌（中间 2 张正面）✅
- 加杠 → 旋转牌上方再叠 1 张 ✅
- seat_panel 不再显示 "副露: [m×N]" 文字 ✅

- [ ] **Step 3: 全套 GUT**

```bash
godot --headless --path godot -d -s addons/gut/gut_cmdml.gd \
  -gdir=res://tests -ginclude_subdirs -gexit 2>&1 | grep -E "Tests|Passing|All tests"
```

Expected: `All tests passed!` 数量 = 现 main 数 + 10（chunk 1 加的）

---

## 后续 PR 候选（spec 出范围，如需可单独开 plan）

| 主题 | 描述 |
|---|---|
| AI 主动 chi/pon | 修改 SimpleAi / HeuristicAi 加 decide_chi / decide_pon 接 ClaimValidator |
| Chi companion 手选 UI | 玩家 chi 时 player_action_panel 弹组合候选；当前自动取首组 |
| 副露红 dora 标识 | Tile.is_red_dora 已存在；需在 MeldArea 渲染时加 modulate |
| 副露动画 | TWEEN 牌从弃牌河飞到 MeldArea 位置；现 v1 直接 rebuild children |

---

## Plan complete 

**保存到** `docs/superpowers/plans/2026-05-08-meld-area-japanese-style.md`。

下一步：使用 superpowers:subagent-driven-development 执行（每 Task 派 fresh subagent + 两段 review）。
