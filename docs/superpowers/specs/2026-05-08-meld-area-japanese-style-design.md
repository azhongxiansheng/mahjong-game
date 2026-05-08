# 副露区（MeldArea）— 日麻风格视觉化 spec

> **类型**：UI feature spec。当前 4 人桌 `seat_panel.tscn` 仅用 Label `副露: [m×N]` 描述副露数；玩家 chi/pon/minkan 已 work（PR #141），但视觉无反馈。本 spec 设计独立 `MeldArea` Node2D，按日麻通行风格渲染副露牌（含来源旋转 + 暗杠 / 加杠区分）。

## TL;DR

- 4 桌边各一个 `MeldArea` Node2D，与 `discard_river` 同级，rotation 0/-90/180/+90 让面朝桌心
- 每组 meld 内 1 张牌按 `from_seat` 相对 `claimant_seat` 旋转 90°（上家=左 / 对家=中 / 下家=右）
- Ankan 首尾 2 张盖牌、中间 2 张正面（D1 标准日麻流派）
- Added-kan 在原 pon 的旋转牌正上方再叠 1 张同 id 旋转牌，组成 90° L 形
- 纯算法 `meld_layout(meld, claimant_seat) -> Array[Slot]` 可 GUT 单测；scene-driven smoke test 用 F6 手测
- `seat_panel.tscn` 内 `Melds` Label 弃用（保留 `set_meld_count` 兼容路径以防回滚）

## 1. 为什么

PR #141（玩家可玩战斗 smoke）已 ship 玩家 chi/pon/minkan 流程；PR #145 修了 AI 切牌后玩家鸣牌窗口的 dispatch bug。但 4 人桌副露**只在文字 Label 上显示数量**：

```
[node name="Melds" type="Label" parent="VBox"]
text = "副露: [m×0]"
```

玩家成功 chi 后，hand 减 2 张但桌面无反馈 — 视觉 break，沉浸感丢失。本 spec 修这个洞。

## 2. 当前架构（已工作部分，本 spec 不改）

```
Player UI (player_action_panel)
  ↓ chi/pon/minkan 按钮
PlayableBattleController._try_player_claim_async
  ↓ engine.apply_chi / apply_pon / apply_minkan
TurnEngine.apply_chi (claimant_seat, claimed_tile, companion_ids)
  ↓ 创建 Meld（含 from_seat）
Seat.melds.append(meld)
  ↓ BC._emit(&"TILE_CALLED", claimant, ...)
events 流出
```

`Meld` 已带必要字段：

```gdscript
class_name Meld
enum Kind { CHI, PON, MINKAN, ANKAN, ADDED_KAN }
const NO_SOURCE_SEAT: int = -1
var kind: Kind
var tiles: Array[Tile]
var from_seat: int  # ankan 用 NO_SOURCE_SEAT
```

底层数据完整。本 spec 只改视觉层。

## 3. 设计

### 3.1 范围

| 组件 | 状态 | 本 spec 动作 |
|---|---|---|
| `Meld` 数据结构 | ✅ 完整 | 不动 |
| `ClaimValidator` / `TurnEngine.apply_*` | ✅ 完整 | 不动 |
| `PlayableBattleController` 玩家 claim 流 | ✅ 完整 | 不动 |
| `seat_panel.gd` `Melds` Label 显示数量 | ⚠️ 仅文字 | 弃用，保留兼容路径 |
| 副露视觉渲染 | ❌ 不存在 | **新增 `MeldArea`** |
| AI 主动 chi/pon | ❌ 不存在 | 不在本 spec 范围 |
| Chi 选 companion UI | ⚠️ 自动取首组 | 不在本 spec 范围 |

### 3.2 新增组件

#### MeldArea（`godot/ui/four_player_table/meld_area.gd` + `.tscn`）

```gdscript
class_name MeldArea extends Node2D

const TILE_W: int = 32        # 同 discard_river
const TILE_H: int = 48
const MELD_GAP: int = 8       # 多组 meld 之间间距

func set_melds(melds: Array, claimant_seat: int) -> void
```

**职责**：给定 `seat.melds` 数组 + 该 seat 的 id，按日麻规范渲染 tiles。`set_melds` 内 rebuild 所有 children；不增量。

**位置**：`four_player_table.tscn` 内 4 边各加一个 MeldArea，rotation 与 discard_river 同 4 边方向。具体桌面坐标：手牌右下角偏外（discard_river 之外侧 + 偏右），不与现有 layout 重叠。

#### 纯算法函数（`MeldArea` 静态方法或 `Meld` 类拓展）

```gdscript
# 给定 Meld + claimant 视角，返每张 tile 的渲染 Slot 描述
static func meld_layout(meld: Meld, claimant_seat: int) -> Array
# 返：Array[Slot]
# Slot = {
#   tile_id: int,         # 牌名
#   rotated: bool,        # 是否旋转 90°
#   face_down: bool,      # 是否盖牌（暗杠首尾 2 张）
#   stacked_above: bool,  # 是否叠在前一张上方（added-kan 加牌）
# }
```

**位置**：放 `MeldArea` 类的 static func；纯算法不依赖 Godot scene tree，方便 GUT 单测。

### 3.3 旋转规则（spec §10 / 通行日麻）

```
from_seat 相对 claimant_seat：
  上家 (claimant - 1) % 4 → 旋转牌在第 1 张（最左）
  对家 (claimant + 2) % 4 → 旋转牌在第 2 张（中间）
  下家 (claimant + 1) % 4 → 旋转牌在第 3 张（最右）
```

**Chi 例外**：日麻 chi 仅允许从上家 → 旋转牌恒第 1 张。

### 3.4 渲染细节

| Meld kind | tiles 序 | rotated 索引 | face_down 索引 |
|---|---|---|---|
| CHI | 3 张顺子升序 | 第 0 张（上家来） | 无 |
| PON | 3 张同 id | 按 from_seat 映射 | 无 |
| MINKAN | 4 张同 id | 按 from_seat 映射 | 无 |
| **ANKAN** | 4 张同 id | 无 | **第 0 / 第 3 张**（D1 流派） |
| **ADDED_KAN** | 原 pon 3 张 + 加 1 张 | 原 pon 旋转位置 + **加牌叠该位置上方** | 无 |

**水平累积**：`x = i * TILE_W`（旋转牌占 TILE_H 宽，需 layout 时调 +offset；纯算法保留 `x_offset` 字段供渲染算）

**多组 meld 顺序**：`seat.melds[0]` 在最右，新加的在最左（标准日麻"副露往左推"）

### 3.5 Tile 渲染复用

走 `discard_river.gd` 同套：

- `TextureExtractor` autoload 拿 atlas 切片
- `CardTileBack.tile_id_to_atlas_key(tile_id)` 转字符串 key
- 32×48 TextureRect 子节点
- 旋转：单 tile `rotation_degrees = 90`，pivot 调整避免位移
- 盖牌：用现有 `card_tile_back.gd` 背面纹理

### 3.6 数据流

```
玩家点 chi 按钮
  → PlayableBattleController.apply_chi
  → seat.melds.append(...)
  → BC._emit(&"TILE_CALLED", claimant)
  → four_player_table 监听 TILE_CALLED
  → meld_areas[claimant].set_melds(seat.melds, claimant)
  → MeldArea._rebuild() 清空 children + 重建
```

### 3.7 弃用 / 兼容

`seat_panel.gd._label_melds` 内文字"副露: [m×N]"弃用。保留 `set_meld_count(n)` 函数（设 Label 隐藏 / 0），方便 rollback：

```gdscript
func set_meld_count(n: int) -> void:
    _meld_count = n
    if _label_melds != null:
        _label_melds.visible = false  # 弃用文字显示，留接口
```

## 4. Tests

### 4.1 核心算法（GUT 单测，`tests/ui/four_player_table/test_meld_layout.gd`）

| 测 | 验证 |
|---|---|
| `test_chi_rotated_at_left` | CHI 来自上家 → 第 0 张 rotated |
| `test_pon_from_kamicha_rotated_at_left` | PON 来自上家 → 第 0 张 rotated |
| `test_pon_from_toimen_rotated_at_middle` | PON 来自对家 → 第 1 张 rotated |
| `test_pon_from_shimocha_rotated_at_right` | PON 来自下家 → 第 2 张 rotated |
| `test_minkan_4_tiles_rotated_per_source` | MINKAN 4 张 + 旋转位置同 PON 规则 |
| `test_ankan_face_down_outer_two` | ANKAN 第 0 / 第 3 张 face_down |
| `test_added_kan_stacked_above_pon_rotated` | ADDED_KAN 在原 pon 旋转牌上方叠 |
| `test_no_face_down_for_visible_melds` | CHI / PON / MINKAN / ADDED_KAN 不应有 face_down |

10-15 测覆盖；位置约 100 行。

### 4.2 Scene smoke（F6 手测）

`tests/scenes/four_player_table/meld_area_demo.tscn` + `.gd`：

- 4 边各放一个 MeldArea
- 喂模拟 melds 数据：上家 PON、对家 MINKAN、下家 CHI、自家 ANKAN + ADDED_KAN
- 肉眼看 layout 对（旋转 / 叠加 / 盖牌位置）

不进 GUT autorun（Control 渲染需 SceneTree）。

### 4.3 BC ↔ MeldArea 集成（手测）

加真玩家 F5 跑一局，故意上家切第 X 牌让玩家可 pon → 点 pon → 看自家 MeldArea 出现 PON（中间张旋转，因玩家是 PON claimant，from_seat = 上家）。

不进自动测，靠玩家手测 + 后续 PR 加 RecordingFromEvents.

## 5. 出范围（明确不做）

- **AI 主动 chi/pon**：现 AI 仍 advance_to_next_seat 跳过鸣牌；本 spec 视觉仍工作（AI 大多无 melds），但若 AI 触发 ankan 也走同代码路径
- **玩家 chi companion 选择 UI**：v1 自动取首组合法 companion；本 spec 不改
- **红 dora 标识**：`Tile.is_red_dora` 已存在，但副露内红五的渲染样式留 v2
- **副露动画**：v1 直接 rebuild children；牌从弃牌河"飞"到副露区的补间动画留 v2
- **副露在桌面 hover tooltip**：留 v2（现 TileStamp 已有 hover 模式可借鉴）

## 6. 风险 / 反弹

| 风险 | 缓解 |
|---|---|
| 旋转 90° tile 改宽度让水平 layout 偏移 | 纯算法 Slot 含 `x_offset`，渲染时按 slot.x_offset 摆位 |
| 4 桌边 rotation 0/-90/180/+90 与子 tile rotation 90° 复合 | 与 discard_river 同模式（已 work），借现有桌面坐标系 |
| 玩家 chi 后 seat.hand 减 2 张但 four_player_table 监听 TILE_CALLED 滞后 | 监听 BC.events 已有路径（discard_river 也走该机制） |
| seat_panel `Melds` Label 弃用导致 GUT 旧测断言文本失败 | 检查 `tests/scenes/four_player_table/` 现有测；如有 `set_meld_count` 文字断言改成 visibility 检查 |

## 7. 关键决策记录（brainstorming）

| 决策 | 选项 | 选择 | 理由 |
|---|---|---|---|
| 副露牌摆放位置 | A 嵌 seat_panel / **B 桌面 4 边** / C 仅玩家 | **B** | 标准日麻视觉；用户明确选择 |
| Ankan 渲染流派 | **D1 首尾盖** / D2 全盖 / D3 全正面 | **D1** | 最常见日麻教程做法；用户明确选择 |
| AI 主动 chi/pon | 本 spec 实现 / 推迟 | **推迟** | 当前 AI 不调 claim；视觉先 work，AI 改造单 PR |
| Chi companion 选择 UI | 本 spec 实现 / 推迟 | **推迟** | v1 自动取首组够 smoke 跑通 |

## 8. 出 plan 后 PR 划分（writing-plans 阶段细化）

预期 2-3 PR：
1. `feat(ui/m12): MeldArea 算法层 + GUT 单测` — 纯 `meld_layout` 函数 + tests
2. `feat(ui/m12): MeldArea Node2D 渲染 + scene smoke` — 接 TextureExtractor + 4 桌边布局
3. `feat(ui/m12): four_player_table 监听 TILE_CALLED 触发 MeldArea 刷新 + seat_panel Melds Label 弃用`

具体顺序留 writing-plans 决定。

## 9. 下一步

→ writing-plans skill 出具体实施 plan（按 PR 拆分 + 每 PR 文件 / 函数级改动）。
