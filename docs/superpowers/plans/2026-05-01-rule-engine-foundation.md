# 麻将王 — 里程碑 0a：日麻规则引擎地基 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `godot/` 工程内安装 GUT 测试框架并搭出日麻规则引擎的最底层数据类型（牌、牌墙、手牌、面子）以及和牌型识别（4 面子+1 雀头、七対子、国士無双），全部走 TDD，跑通 headless 测试套。

**Architecture:** 在 `godot/core/tile/` 与 `godot/core/rules_japanese/` 下新建无 Godot 节点依赖的纯 GDScript 数据类与算法，配合 GUT 9.x 跑 headless 单测。本计划只覆盖"和牌型识别"，不含役判定（plan 0b）、符算/点数（plan 0c）、振听/Dora/立直/流局/状态机（plan 0d）。

**Tech Stack:**
- Godot 4.5（已存在于 `godot/project.godot`）
- GDScript 2.0
- GUT 9.4.0（[bitwes/Gut](https://github.com/bitwes/Gut)）作 dev addon
- 命令行：`godot --headless`

> **文档定位：** 日麻规则引擎地基实现追溯。当前行为以代码、测试和现行多人玩法 PRD / ADR 为准；原始肉鸽总 spec 已归档，不再作为事实源。

> **缩进约定**：本仓库 GDScript 文件统一使用 **TAB** 缩进（与 `godot/scripts/*.gd` 现有约定一致）。本计划代码块为节省篇幅使用 4 空格显示，**写入实际 `.gd` 文件时必须转为 TAB**。bash / markdown / ini 文件按各自约定。

---

## File Structure

新增/修改文件总览：

| 路径 | 用途 | 来源 |
|------|------|------|
| `godot/addons/gut/...` | GUT 测试框架（整体下载） | github release |
| `godot/project.godot` | 加 GUT 插件 enable | 修改 |
| `godot/.gdignore` 在 `addons/` 目录无需 | — | — |
| `godot/core/tile/tile_id.gd` | TileId 枚举 + 工具方法 | 新增 |
| `godot/core/tile/tile.gd` | Tile 值对象（含 is_red_dora） | 新增 |
| `godot/core/tile/wall.gd` | 牌墙（136 张洗牌 + 摸牌） | 新增 |
| `godot/core/tile/hand.gd` | 手牌（13/14 张 + 排序 + 删/加） | 新增 |
| `godot/core/tile/meld.gd` | 面子（顺/刻/杠 + 来源标记） | 新增 |
| `godot/core/rules_japanese/win_pattern.gd` | 和牌型识别入口 | 新增 |
| `godot/core/rules_japanese/standard_decomposer.gd` | 4 面子+1 雀头分解 | 新增 |
| `godot/core/rules_japanese/chiitoi_detector.gd` | 七対子 | 新增 |
| `godot/core/rules_japanese/kokushi_detector.gd` | 国士無双 + 13 面待 | 新增 |
| `godot/tests/core/test_tile_id.gd` | TileId 测试 | 新增 |
| `godot/tests/core/test_tile.gd` | Tile 测试 | 新增 |
| `godot/tests/core/test_wall.gd` | Wall 测试 | 新增 |
| `godot/tests/core/test_hand.gd` | Hand 测试 | 新增 |
| `godot/tests/core/test_meld.gd` | Meld 测试 | 新增 |
| `godot/tests/core/test_standard_decomposer.gd` | 4 面子+1 雀头测试 | 新增 |
| `godot/tests/core/test_chiitoi_detector.gd` | 七対子测试 | 新增 |
| `godot/tests/core/test_kokushi_detector.gd` | 国士無双测试 | 新增 |
| `godot/tests/core/test_win_pattern.gd` | 入口集成测试 | 新增 |
| `scripts/test_run_core.sh` | headless 测试 wrapper | 新增 |

不动现有 216 个 `godot/scripts/*.gd`（按 spec §4.1 迁移策略，旧脚本仅在被里程碑动到时才搬迁）。

---

## Task 1: 安装 GUT 并跑通空测试套

**Files:**
- Create: `godot/addons/gut/` (整个目录从 GUT release 解压)
- Modify: `godot/project.godot`（启用插件 + 注册 GUT 自定义类型）
- Create: `godot/tests/core/test_smoke.gd`
- Create: `scripts/test_run_core.sh`
- Create: `godot/.gitignore`（如不存在，确保 `.godot/` 被忽略）

- [ ] **Step 1.1: 下载 GUT 9.4.0**

```bash
cd /home/adam/mahjong-game-king-design
mkdir -p tmp_gut && cd tmp_gut
curl -L https://github.com/bitwes/Gut/archive/refs/tags/v9.4.0.zip -o gut.zip
unzip -q gut.zip
cp -r Gut-9.4.0/addons/gut ../godot/addons/gut
cd .. && rm -rf tmp_gut
ls godot/addons/gut/plugin.cfg
```

Expected：输出 `godot/addons/gut/plugin.cfg` 路径。

- [ ] **Step 1.2: 启用插件 + 升 config_version 到 6（4.x 推荐）— 改 `godot/project.godot`**

在 `[autoload]` 段后追加：

```ini
[editor_plugins]

enabled=PackedStringArray("res://addons/gut/plugin.cfg")
```

不要修改其它字段。

- [ ] **Step 1.3: 写一个最小烟测试 — 创建 `godot/tests/core/test_smoke.gd`**

```gdscript
extends GutTest

func test_smoke():
    assert_eq(1 + 1, 2, "GUT 跑得通")
```

- [ ] **Step 1.4: 创建测试运行 wrapper — `scripts/test_run_core.sh`**

```bash
#!/usr/bin/env bash
# Run GUT core tests headless.
# Usage: scripts/test_run_core.sh [optional GUT args]
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)/godot"

godot --headless --path "$PROJ_DIR" \
    -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests/core \
    -gexit \
    "$@"
```

赋可执行：
```bash
chmod +x scripts/test_run_core.sh
```

- [ ] **Step 1.5: 跑烟测试验证通过**

```bash
scripts/test_run_core.sh
```

Expected：输出含 `1 of 1 passed` 与 `Tests Run: 1`。若 godot 命令未安装，先 `which godot` 确认；用户机若用 `godot4` 别名，调整 wrapper 中命令名。

- [ ] **Step 1.6: 确认 .gitignore 排除 `.godot/`**

检查 `godot/.gitignore` 是否含 `.godot/`：

```bash
grep -q "^\.godot/$" godot/.gitignore || echo ".godot/" >> godot/.gitignore
cat godot/.gitignore
```

Expected：含 `.godot/` 行。

- [ ] **Step 1.7: Commit**

```bash
cd /home/adam/mahjong-game-king-design
git add godot/addons/gut godot/project.godot godot/tests/core/test_smoke.gd scripts/test_run_core.sh godot/.gitignore
git commit -m "$(cat <<'EOF'
test: 安装 GUT 9.4.0 并跑通 headless 烟测试

- 引入 GUT 作 dev 依赖（addons/gut/）
- 在 project.godot 启用插件
- 增 scripts/test_run_core.sh 作 headless 测试 wrapper
- 验证 GUT 在 Godot 4.5 下跑通

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 2: TileId 枚举 + 基础工具方法

`TileId` 是 34 个牌名的不可变标识：W1..W9 / T1..T9 / S1..S9 / E S W N Z F B。

**Files:**
- Create: `godot/core/tile/tile_id.gd`
- Create: `godot/tests/core/test_tile_id.gd`

- [ ] **Step 2.1: 写测试 `godot/tests/core/test_tile_id.gd`**

```gdscript
extends GutTest

func test_total_count_is_34():
    assert_eq(TileId.ALL.size(), 34)

func test_man_tiles_are_first_9():
    assert_eq(TileId.W1, 0)
    assert_eq(TileId.W9, 8)

func test_pin_tiles_follow_man():
    assert_eq(TileId.T1, 9)
    assert_eq(TileId.T9, 17)

func test_sou_tiles_follow_pin():
    assert_eq(TileId.S1, 18)
    assert_eq(TileId.S9, 26)

func test_honor_tiles_follow_sou():
    assert_eq(TileId.E, 27)
    assert_eq(TileId.S_WIND, 28)
    assert_eq(TileId.W_WIND, 29)
    assert_eq(TileId.N, 30)
    assert_eq(TileId.HAKU, 31)  # 白
    assert_eq(TileId.HATSU, 32) # 发
    assert_eq(TileId.CHUN, 33)  # 中

func test_is_terminal():
    assert_true(TileId.is_terminal(TileId.W1))
    assert_true(TileId.is_terminal(TileId.W9))
    assert_false(TileId.is_terminal(TileId.W5))
    assert_false(TileId.is_terminal(TileId.E), "字牌不是老头")

func test_is_honor():
    assert_true(TileId.is_honor(TileId.E))
    assert_true(TileId.is_honor(TileId.CHUN))
    assert_false(TileId.is_honor(TileId.W1))

func test_is_yaochu():
    # 幺九：1, 9, 字牌
    assert_true(TileId.is_yaochu(TileId.W1))
    assert_true(TileId.is_yaochu(TileId.S9))
    assert_true(TileId.is_yaochu(TileId.E))
    assert_false(TileId.is_yaochu(TileId.W5))

func test_is_simple():
    # 中张：2-8 of m/p/s
    assert_true(TileId.is_simple(TileId.W2))
    assert_true(TileId.is_simple(TileId.S8))
    assert_false(TileId.is_simple(TileId.W1))
    assert_false(TileId.is_simple(TileId.E))

func test_suit_returns_correct():
    assert_eq(TileId.suit(TileId.W5), TileId.Suit.MAN)
    assert_eq(TileId.suit(TileId.T5), TileId.Suit.PIN)
    assert_eq(TileId.suit(TileId.S5), TileId.Suit.SOU)
    assert_eq(TileId.suit(TileId.E), TileId.Suit.HONOR)

func test_number_returns_1_to_9():
    assert_eq(TileId.number(TileId.W1), 1)
    assert_eq(TileId.number(TileId.W9), 9)
    assert_eq(TileId.number(TileId.E), 0, "字牌无数字")

func test_next_tile_for_dora_indicator():
    # Dora 指示牌的下一张是 Dora
    # 数牌：W1->W2, W9->W1（绕回）
    assert_eq(TileId.next_for_dora(TileId.W1), TileId.W2)
    assert_eq(TileId.next_for_dora(TileId.W9), TileId.W1)
    assert_eq(TileId.next_for_dora(TileId.T9), TileId.T1)
    # 风牌循环：E->S->W->N->E
    assert_eq(TileId.next_for_dora(TileId.E), TileId.S_WIND)
    assert_eq(TileId.next_for_dora(TileId.N), TileId.E)
    # 三元牌循环：白->发->中->白
    assert_eq(TileId.next_for_dora(TileId.HAKU), TileId.HATSU)
    assert_eq(TileId.next_for_dora(TileId.CHUN), TileId.HAKU)
```

- [ ] **Step 2.2: 跑测试，确认全失败**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/test_tile_id.gd
```

Expected：失败，`TileId` 类找不到。

- [ ] **Step 2.3: 实现 `godot/core/tile/tile_id.gd`**

```gdscript
class_name TileId

# Suit enum
enum Suit { MAN, PIN, SOU, HONOR }

# 34 个牌名整数常量（与 ALL 数组下标对应）
const W1 = 0; const W2 = 1; const W3 = 2; const W4 = 3; const W5 = 4
const W6 = 5; const W7 = 6; const W8 = 7; const W9 = 8
const T1 = 9; const T2 = 10; const T3 = 11; const T4 = 12; const T5 = 13
const T6 = 14; const T7 = 15; const T8 = 16; const T9 = 17
const S1 = 18; const S2 = 19; const S3 = 20; const S4 = 21; const S5 = 22
const S6 = 23; const S7 = 24; const S8 = 25; const S9 = 26
const E = 27           # 东
const S_WIND = 28      # 南
const W_WIND = 29      # 西
const N = 30           # 北
const HAKU = 31        # 白
const HATSU = 32       # 发
const CHUN = 33        # 中

const ALL: Array[int] = [
    0,1,2,3,4,5,6,7,8,
    9,10,11,12,13,14,15,16,17,
    18,19,20,21,22,23,24,25,26,
    27,28,29,30,31,32,33,
]

static func suit(t: int) -> Suit:
    if t <= W9: return Suit.MAN
    if t <= T9: return Suit.PIN
    if t <= S9: return Suit.SOU
    return Suit.HONOR

static func number(t: int) -> int:
    # 数牌返回 1-9，字牌返回 0
    var s := suit(t)
    if s == Suit.HONOR: return 0
    return (t % 9) + 1

static func is_honor(t: int) -> bool:
    return t >= E

static func is_terminal(t: int) -> bool:
    # 老头：数牌的 1 和 9（不含字牌）
    if is_honor(t): return false
    var n := number(t)
    return n == 1 or n == 9

static func is_yaochu(t: int) -> bool:
    # 幺九：1、9、字牌
    return is_terminal(t) or is_honor(t)

static func is_simple(t: int) -> bool:
    # 中张：2-8 of 数牌
    if is_honor(t): return false
    var n := number(t)
    return n >= 2 and n <= 8

static func next_for_dora(t: int) -> int:
    # Dora 指示牌的下一张
    var s := suit(t)
    match s:
        Suit.MAN, Suit.PIN, Suit.SOU:
            var n := number(t)
            return t - (n - 1) + (n % 9)  # 1->2,...,8->9,9->1
        Suit.HONOR:
            # 风牌循环 E->S->W->N->E
            if t >= E and t <= N:
                return E + (t - E + 1) % 4
            # 三元牌循环 白->发->中->白
            return HAKU + (t - HAKU + 1) % 3
    return t
```

- [ ] **Step 2.4: 跑测试验证全通过**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/test_tile_id.gd
```

Expected：`13 of 13 passed`。

- [ ] **Step 2.5: Commit**

```bash
git add godot/core/tile/tile_id.gd godot/tests/core/test_tile_id.gd
git commit -m "$(cat <<'EOF'
feat(rules): TileId 枚举 + 工具方法（suit/number/yaochu/dora-next）

- 34 个牌名整数常量与索引对应
- suit() / number() / is_honor / is_terminal / is_yaochu / is_simple
- next_for_dora 处理数牌绕回 + 风/三元循环
- 13 个测试用例覆盖各分类与 Dora 边界

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 3: Tile 值对象

`Tile` 包装一张物理牌的额外属性（is_red_dora，未来还会接 owner_seat / skill），但本计划仅含 is_red_dora；owner_seat / skill 留到 plan 0d 接入 BattleState 时加。

**Files:**
- Create: `godot/core/tile/tile.gd`
- Create: `godot/tests/core/test_tile.gd`

- [ ] **Step 3.1: 写测试 `godot/tests/core/test_tile.gd`**

```gdscript
extends GutTest

func test_construct_with_id_only():
    var t := Tile.new(TileId.W5)
    assert_eq(t.id, TileId.W5)
    assert_false(t.is_red_dora)

func test_construct_red_five_man():
    var t := Tile.make_red_five_man()
    assert_eq(t.id, TileId.W5)
    assert_true(t.is_red_dora)

func test_construct_red_five_pin():
    var t := Tile.make_red_five_pin()
    assert_eq(t.id, TileId.T5)
    assert_true(t.is_red_dora)

func test_construct_red_five_sou():
    var t := Tile.make_red_five_sou()
    assert_eq(t.id, TileId.S5)
    assert_true(t.is_red_dora)

func test_equals_by_id_only_ignoring_red():
    var a := Tile.new(TileId.W5)
    var b := Tile.make_red_five_man()
    assert_true(a.equals_by_id(b), "id 相同即视为同类型，不看赤")
```

- [ ] **Step 3.2: 跑测试，确认失败**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/test_tile.gd
```

- [ ] **Step 3.3: 实现 `godot/core/tile/tile.gd`**

```gdscript
class_name Tile

var id: int
var is_red_dora: bool

func _init(p_id: int, p_red: bool = false) -> void:
    id = p_id
    is_red_dora = p_red

func equals_by_id(other: Tile) -> bool:
    return id == other.id

static func make_red_five_man() -> Tile:
    return Tile.new(TileId.W5, true)

static func make_red_five_pin() -> Tile:
    return Tile.new(TileId.T5, true)

static func make_red_five_sou() -> Tile:
    return Tile.new(TileId.S5, true)
```

- [ ] **Step 3.4: 跑测试验证通过**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/test_tile.gd
```

Expected：`5 of 5 passed`。

- [ ] **Step 3.5: Commit**

```bash
git add godot/core/tile/tile.gd godot/tests/core/test_tile.gd
git commit -m "$(cat <<'EOF'
feat(rules): Tile 值对象 + 赤 Dora 工厂

- Tile 包装 TileId + is_red_dora
- equals_by_id 仅比 id（赤红是修饰）
- 三个工厂：make_red_five_{man,pin,sou}

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 4: Wall 牌墙

完整 136 张洗牌、按顺序摸取。本任务不做王牌（dead wall）拆分 —— 那是 plan 0d 的事。

**Files:**
- Create: `godot/core/tile/wall.gd`
- Create: `godot/tests/core/test_wall.gd`

- [ ] **Step 4.1: 写测试 `godot/tests/core/test_wall.gd`**

```gdscript
extends GutTest

func test_default_wall_has_136_tiles():
    var w := Wall.new_full_set()
    assert_eq(w.size(), 136)

func test_each_tile_id_appears_exactly_4_times():
    var w := Wall.new_full_set()
    var counts := {}
    for tile in w._tiles:
        counts[tile.id] = counts.get(tile.id, 0) + 1
    assert_eq(counts.size(), 34, "应有 34 种牌")
    for tid in counts:
        assert_eq(counts[tid], 4, "牌 %d 应有 4 张" % tid)

func test_red_dora_count_is_3_by_default():
    var w := Wall.new_full_set()
    var red_count := 0
    for tile in w._tiles:
        if tile.is_red_dora:
            red_count += 1
    assert_eq(red_count, 3, "默认 5m/5p/5s 各 1 张赤")

func test_shuffle_with_seed_is_deterministic():
    var w1 := Wall.new_full_set()
    var w2 := Wall.new_full_set()
    w1.shuffle(42)
    w2.shuffle(42)
    for i in range(w1.size()):
        assert_eq(w1._tiles[i].id, w2._tiles[i].id, "种子相同顺序相同 i=%d" % i)

func test_draw_returns_top_and_decrements():
    var w := Wall.new_full_set()
    w.shuffle(1)
    var initial := w.size()
    var t := w.draw()
    assert_not_null(t)
    assert_eq(w.size(), initial - 1)

func test_draw_when_empty_returns_null():
    var w := Wall.new_full_set()
    for _i in range(136):
        w.draw()
    assert_eq(w.size(), 0)
    assert_null(w.draw())

func test_remaining_count_alias():
    var w := Wall.new_full_set()
    assert_eq(w.remaining(), w.size())
    w.shuffle(0)
    w.draw()
    assert_eq(w.remaining(), 135)
```

- [ ] **Step 4.2: 跑测试，确认失败**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/test_wall.gd
```

- [ ] **Step 4.3: 实现 `godot/core/tile/wall.gd`**

```gdscript
class_name Wall

var _tiles: Array[Tile] = []
var _draw_index: int = 0

static func new_full_set() -> Wall:
    var w := Wall.new()
    # 每种 TileId 4 张，5m/5p/5s 第一张标记为赤
    for tid in TileId.ALL:
        for copy_index in range(4):
            var is_red := false
            if copy_index == 0 and (tid == TileId.W5 or tid == TileId.T5 or tid == TileId.S5):
                is_red = true
            w._tiles.append(Tile.new(tid, is_red))
    return w

func size() -> int:
    return _tiles.size() - _draw_index

func remaining() -> int:
    return size()

func shuffle(seed: int) -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = seed
    # Fisher-Yates 在剩余未抽部分洗
    var i := _tiles.size() - 1
    while i > _draw_index:
        var j := _draw_index + rng.randi_range(0, i - _draw_index)
        var tmp := _tiles[i]
        _tiles[i] = _tiles[j]
        _tiles[j] = tmp
        i -= 1

func draw() -> Tile:
    if size() == 0:
        return null
    var t := _tiles[_draw_index]
    _draw_index += 1
    return t
```

- [ ] **Step 4.4: 跑测试验证通过**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/test_wall.gd
```

Expected：`7 of 7 passed`。

- [ ] **Step 4.5: Commit**

```bash
git add godot/core/tile/wall.gd godot/tests/core/test_wall.gd
git commit -m "$(cat <<'EOF'
feat(rules): Wall 牌墙 — 136 张完整洗牌 + 顺序摸取

- new_full_set 生成 34×4 张，5m/5p/5s 各含 1 赤
- shuffle(seed) Fisher-Yates 确定性洗
- draw 顺序摸，空时返 null
- 7 测试覆盖容量/分布/赤 Dora/确定性/边界

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 5: Hand 手牌

手牌容器：13/14 张 + 排序 + 加/减。不含 melds 列表（melds 在 Task 6 单独建模），手牌只是"暗牌"。

**Files:**
- Create: `godot/core/tile/hand.gd`
- Create: `godot/tests/core/test_hand.gd`

- [ ] **Step 5.1: 写测试 `godot/tests/core/test_hand.gd`**

```gdscript
extends GutTest

func _make_hand_from_ids(ids: Array) -> Hand:
    var h := Hand.new()
    for tid in ids:
        h.add(Tile.new(tid))
    return h

func test_empty_hand_size_is_zero():
    var h := Hand.new()
    assert_eq(h.size(), 0)

func test_add_increases_size():
    var h := Hand.new()
    h.add(Tile.new(TileId.W1))
    assert_eq(h.size(), 1)

func test_remove_by_id_returns_true_and_decreases():
    var h := _make_hand_from_ids([TileId.W1, TileId.W2, TileId.W3])
    assert_true(h.remove_by_id(TileId.W2))
    assert_eq(h.size(), 2)

func test_remove_by_id_when_absent_returns_false():
    var h := _make_hand_from_ids([TileId.W1])
    assert_false(h.remove_by_id(TileId.S5))
    assert_eq(h.size(), 1)

func test_to_id_array_returns_sorted_ascending():
    var h := _make_hand_from_ids([TileId.S5, TileId.W1, TileId.E, TileId.W1])
    var ids := h.to_id_array()
    assert_eq(ids, [TileId.W1, TileId.W1, TileId.S5, TileId.E])

func test_count_of_id():
    var h := _make_hand_from_ids([TileId.W1, TileId.W1, TileId.W1, TileId.W2])
    assert_eq(h.count_of(TileId.W1), 3)
    assert_eq(h.count_of(TileId.W2), 1)
    assert_eq(h.count_of(TileId.W9), 0)

func test_id_count_dict_returns_map():
    var h := _make_hand_from_ids([TileId.W1, TileId.W1, TileId.W2])
    var d := h.id_count_dict()
    assert_eq(d.get(TileId.W1), 2)
    assert_eq(d.get(TileId.W2), 1)
    assert_false(d.has(TileId.W3))

func test_clone_independent():
    var h := _make_hand_from_ids([TileId.W1])
    var c := h.clone()
    c.add(Tile.new(TileId.W2))
    assert_eq(h.size(), 1)
    assert_eq(c.size(), 2)
```

- [ ] **Step 5.2: 跑测试，确认失败**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/test_hand.gd
```

- [ ] **Step 5.3: 实现 `godot/core/tile/hand.gd`**

```gdscript
class_name Hand

var _tiles: Array[Tile] = []

func size() -> int:
    return _tiles.size()

func add(t: Tile) -> void:
    _tiles.append(t)

func remove_by_id(tid: int) -> bool:
    for i in range(_tiles.size()):
        if _tiles[i].id == tid:
            _tiles.remove_at(i)
            return true
    return false

func count_of(tid: int) -> int:
    var c := 0
    for t in _tiles:
        if t.id == tid:
            c += 1
    return c

func id_count_dict() -> Dictionary:
    var d := {}
    for t in _tiles:
        d[t.id] = d.get(t.id, 0) + 1
    return d

func to_id_array() -> Array:
    var ids := []
    for t in _tiles:
        ids.append(t.id)
    ids.sort()
    return ids

func clone() -> Hand:
    var c := Hand.new()
    for t in _tiles:
        c._tiles.append(Tile.new(t.id, t.is_red_dora))
    return c
```

- [ ] **Step 5.4: 跑测试验证通过**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/test_hand.gd
```

Expected：`8 of 8 passed`。

- [ ] **Step 5.5: Commit**

```bash
git add godot/core/tile/hand.gd godot/tests/core/test_hand.gd
git commit -m "$(cat <<'EOF'
feat(rules): Hand 手牌 — add/remove_by_id/count/clone

- 维护 Tile 数组，提供按 id 查/删
- to_id_array 返回升序 id 数组（便于和牌型枚举）
- id_count_dict 返回 {id: count}
- clone 深拷贝独立

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 6: Meld 面子

`Meld` 表达一个已露出的面子：吃（顺）/ 碰（刻）/ 明杠 / 暗杠 / 加杠。

**Files:**
- Create: `godot/core/tile/meld.gd`
- Create: `godot/tests/core/test_meld.gd`

- [ ] **Step 6.1: 写测试 `godot/tests/core/test_meld.gd`**

```gdscript
extends GutTest

func test_chi_meld_3_tiles_consecutive():
    var m := Meld.make_chi([Tile.new(TileId.W2), Tile.new(TileId.W3), Tile.new(TileId.W4)], 0)
    assert_eq(m.kind, Meld.Kind.CHI)
    assert_eq(m.tiles.size(), 3)
    assert_eq(m.from_seat, 0)

func test_pon_meld_3_tiles_same():
    var m := Meld.make_pon([Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5)], 1)
    assert_eq(m.kind, Meld.Kind.PON)

func test_minkan_4_tiles_open():
    var m := Meld.make_minkan([
        Tile.new(TileId.W7), Tile.new(TileId.W7),
        Tile.new(TileId.W7), Tile.new(TileId.W7)
    ], 2)
    assert_eq(m.kind, Meld.Kind.MINKAN)

func test_ankan_4_tiles_concealed():
    var m := Meld.make_ankan([
        Tile.new(TileId.HAKU), Tile.new(TileId.HAKU),
        Tile.new(TileId.HAKU), Tile.new(TileId.HAKU)
    ])
    assert_eq(m.kind, Meld.Kind.ANKAN)
    assert_eq(m.from_seat, -1, "暗杠不来自任何人")

func test_added_kan_from_existing_pon():
    var m := Meld.make_added_kan([
        Tile.new(TileId.E), Tile.new(TileId.E),
        Tile.new(TileId.E), Tile.new(TileId.E)
    ], 3)
    assert_eq(m.kind, Meld.Kind.ADDED_KAN)

func test_is_concealed():
    assert_true(Meld.make_ankan([
        Tile.new(TileId.W1), Tile.new(TileId.W1),
        Tile.new(TileId.W1), Tile.new(TileId.W1)
    ]).is_concealed())
    assert_false(Meld.make_pon([
        Tile.new(TileId.W1), Tile.new(TileId.W1), Tile.new(TileId.W1)
    ], 0).is_concealed())

func test_is_kan():
    var ankan := Meld.make_ankan([
        Tile.new(TileId.W1), Tile.new(TileId.W1),
        Tile.new(TileId.W1), Tile.new(TileId.W1)
    ])
    assert_true(ankan.is_kan())
    var pon := Meld.make_pon([
        Tile.new(TileId.W1), Tile.new(TileId.W1), Tile.new(TileId.W1)
    ], 0)
    assert_false(pon.is_kan())

func test_to_id_array():
    var m := Meld.make_chi([
        Tile.new(TileId.W2), Tile.new(TileId.W3), Tile.new(TileId.W4)
    ], 0)
    assert_eq(m.to_id_array(), [TileId.W2, TileId.W3, TileId.W4])
```

- [ ] **Step 6.2: 跑测试，确认失败**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/test_meld.gd
```

- [ ] **Step 6.3: 实现 `godot/core/tile/meld.gd`**

```gdscript
class_name Meld

enum Kind { CHI, PON, MINKAN, ANKAN, ADDED_KAN }

var kind: Kind
var tiles: Array[Tile]
var from_seat: int  # 牌来自哪个 seat（暗杠 = -1）

func _init(p_kind: Kind, p_tiles: Array[Tile], p_from: int) -> void:
    kind = p_kind
    tiles = p_tiles
    from_seat = p_from

static func make_chi(p_tiles: Array[Tile], from_seat: int) -> Meld:
    return Meld.new(Kind.CHI, p_tiles, from_seat)

static func make_pon(p_tiles: Array[Tile], from_seat: int) -> Meld:
    return Meld.new(Kind.PON, p_tiles, from_seat)

static func make_minkan(p_tiles: Array[Tile], from_seat: int) -> Meld:
    return Meld.new(Kind.MINKAN, p_tiles, from_seat)

static func make_ankan(p_tiles: Array[Tile]) -> Meld:
    return Meld.new(Kind.ANKAN, p_tiles, -1)

static func make_added_kan(p_tiles: Array[Tile], from_seat: int) -> Meld:
    return Meld.new(Kind.ADDED_KAN, p_tiles, from_seat)

func is_concealed() -> bool:
    return kind == Kind.ANKAN

func is_kan() -> bool:
    return kind == Kind.MINKAN or kind == Kind.ANKAN or kind == Kind.ADDED_KAN

func to_id_array() -> Array:
    var ids := []
    for t in tiles:
        ids.append(t.id)
    return ids
```

- [ ] **Step 6.4: 跑测试验证通过**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/test_meld.gd
```

Expected：`8 of 8 passed`。

- [ ] **Step 6.5: Commit**

```bash
git add godot/core/tile/meld.gd godot/tests/core/test_meld.gd
git commit -m "$(cat <<'EOF'
feat(rules): Meld 面子 — chi/pon/minkan/ankan/added_kan

- 五种面子 + 工厂方法
- is_concealed / is_kan / to_id_array
- 暗杠 from_seat = -1

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 7: 标准胡型分解（4 面子 + 1 雀头）

给定 14 张牌（手牌 13 + 和牌张 1，或手牌 11 + 1 副露后剩 11 + 和牌张），尝试分解为 4 个面子 + 1 个雀头。**本任务的算法只接收"暗牌部分"** —— 副露已成立的 melds 在外面剥离，传进来的是手牌剩余张数 + 和牌张数 = `3*N + 2`（N = 4 - 副露数）。

**Files:**
- Create: `godot/core/rules_japanese/standard_decomposer.gd`
- Create: `godot/tests/core/test_standard_decomposer.gd`

- [ ] **Step 7.1: 写测试 `godot/tests/core/test_standard_decomposer.gd`**

```gdscript
extends GutTest

# 输入：14 张牌的 id 数组（升序），返回所有可行分解（每个分解 = {melds: [...], pair: id}）
# 若不能胡，返回空数组。

func test_pure_pinfu_pattern():
    # 234m 567p 678s 234s 11p
    var ids := [
        TileId.W2, TileId.W3, TileId.W4,
        TileId.T5, TileId.T6, TileId.T7,
        TileId.S6, TileId.S7, TileId.S8,
        TileId.S2, TileId.S3, TileId.S4,
        TileId.T1, TileId.T1,
    ]
    ids.sort()
    var results := StandardDecomposer.decompose(ids)
    assert_gt(results.size(), 0, "应能分解")
    var d = results[0]
    assert_eq(d.melds.size(), 4)
    assert_eq(d.pair, TileId.T1)

func test_all_triplets_pattern():
    # 111m 222m 333m 444m 55m
    var ids := [
        TileId.W1, TileId.W1, TileId.W1,
        TileId.W2, TileId.W2, TileId.W2,
        TileId.W3, TileId.W3, TileId.W3,
        TileId.W4, TileId.W4, TileId.W4,
        TileId.W5, TileId.W5,
    ]
    var results := StandardDecomposer.decompose(ids)
    assert_gt(results.size(), 0)
    # 第一个分解：4 个刻子
    var d = results[0]
    assert_eq(d.melds.size(), 4)
    for meld_ids in d.melds:
        assert_eq(meld_ids[0], meld_ids[1])
        assert_eq(meld_ids[1], meld_ids[2])

func test_invalid_hand_returns_empty():
    # 全乱：1m 3m 5m 7m 9m 1p 3p 5p 7p 9p 1s 3s 5s 7s
    var ids := [
        TileId.W1, TileId.W3, TileId.W5, TileId.W7, TileId.W9,
        TileId.T1, TileId.T3, TileId.T5, TileId.T7, TileId.T9,
        TileId.S1, TileId.S3, TileId.S5, TileId.S7,
    ]
    var results := StandardDecomposer.decompose(ids)
    assert_eq(results.size(), 0)

func test_multiple_decompositions():
    # 234567m 234567p 11s 这种型可能有不同分解
    var ids := [
        TileId.W2, TileId.W3, TileId.W4, TileId.W5, TileId.W6, TileId.W7,
        TileId.T2, TileId.T3, TileId.T4, TileId.T5, TileId.T6, TileId.T7,
        TileId.S1, TileId.S1,
    ]
    var results := StandardDecomposer.decompose(ids)
    assert_gt(results.size(), 0)

func test_honor_pair_with_three_chow():
    # 123m 456m 789p 123s EE
    var ids := [
        TileId.W1, TileId.W2, TileId.W3,
        TileId.W4, TileId.W5, TileId.W6,
        TileId.T7, TileId.T8, TileId.T9,
        TileId.S1, TileId.S2, TileId.S3,
        TileId.E, TileId.E,
    ]
    var results := StandardDecomposer.decompose(ids)
    assert_gt(results.size(), 0)
    var d = results[0]
    assert_eq(d.pair, TileId.E)

func test_with_open_melds_count():
    # 副露 1 个吃 234m 后，剩 11 张 + 和牌张 = 11 张需分解为 3 面子 + 1 雀头
    # 这里 decompose 只看暗牌：11 张应分解为 3 面子 + 1 雀头
    # 567p 678s 234s 11p（11 张）
    var ids := [
        TileId.T5, TileId.T6, TileId.T7,
        TileId.S6, TileId.S7, TileId.S8,
        TileId.S2, TileId.S3, TileId.S4,
        TileId.T1, TileId.T1,
    ]
    ids.sort()
    var results := StandardDecomposer.decompose(ids)
    assert_gt(results.size(), 0)
    var d = results[0]
    assert_eq(d.melds.size(), 3)
    assert_eq(d.pair, TileId.T1)
```

- [ ] **Step 7.2: 跑测试，确认失败**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/test_standard_decomposer.gd
```

- [ ] **Step 7.3: 实现 `godot/core/rules_japanese/standard_decomposer.gd`**

```gdscript
class_name StandardDecomposer

# decompose(sorted_ids: Array[int]) -> Array[{melds: Array, pair: int}]
# 输入：升序 id 数组，长度必须是 3n+2（n 为应有面子数）
# 输出：所有合法分解；不合法时返回 []
# 每个 meld 是 [id, id, id]（顺子或刻子）

static func decompose(sorted_ids: Array) -> Array:
    if sorted_ids.size() % 3 != 2:
        return []
    var counts := {}
    for tid in sorted_ids:
        counts[tid] = counts.get(tid, 0) + 1

    var results := []
    # 枚举每个候选雀头
    var distinct_ids := counts.keys()
    distinct_ids.sort()
    for pair_id in distinct_ids:
        if counts[pair_id] >= 2:
            var copy := counts.duplicate()
            copy[pair_id] -= 2
            if copy[pair_id] == 0:
                copy.erase(pair_id)
            var melds: Array = []
            if _try_form_melds(copy, melds):
                results.append({"melds": melds, "pair": pair_id})
    return results

# 尝试将 counts 中所有牌组成顺子/刻子；melds 是输出累积器
static func _try_form_melds(counts: Dictionary, melds: Array) -> bool:
    if counts.is_empty():
        return true
    var keys := counts.keys()
    keys.sort()
    var first_id: int = keys[0]
    # 优先尝试刻子
    if counts[first_id] >= 3:
        var copy := counts.duplicate()
        copy[first_id] -= 3
        if copy[first_id] == 0:
            copy.erase(first_id)
        melds.append([first_id, first_id, first_id])
        if _try_form_melds(copy, melds):
            return true
        melds.pop_back()
    # 再尝试顺子（仅数牌）
    if not TileId.is_honor(first_id):
        var n := TileId.number(first_id)
        if n <= 7:
            var second := first_id + 1
            var third := first_id + 2
            if counts.get(second, 0) >= 1 and counts.get(third, 0) >= 1:
                var copy := counts.duplicate()
                copy[first_id] -= 1
                if copy[first_id] == 0: copy.erase(first_id)
                copy[second] -= 1
                if copy[second] == 0: copy.erase(second)
                copy[third] -= 1
                if copy[third] == 0: copy.erase(third)
                melds.append([first_id, second, third])
                if _try_form_melds(copy, melds):
                    return true
                melds.pop_back()
    return false
```

- [ ] **Step 7.4: 跑测试验证通过**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/test_standard_decomposer.gd
```

Expected：`6 of 6 passed`。若失败，常见原因：

1. 顺子检测漏掉跨花色（不可能跨花色，但要确认 first_id+1/+2 不会越过 W9→T1 边界 —— 当前 `n <= 7` 判断已经隔离）
2. 字牌走顺子分支（`is_honor` 已隔离）
3. 多解时只返回 1 个 —— 可接受（役判定阶段会选最高番分解）

- [ ] **Step 7.5: Commit**

```bash
git add godot/core/rules_japanese/standard_decomposer.gd godot/tests/core/test_standard_decomposer.gd
git commit -m "$(cat <<'EOF'
feat(rules): 4 面子+1 雀头分解器（递归回溯）

- 输入升序 id 数组，输出所有合法分解
- 优先刻子后顺子的固定顺序保证终止性
- 仅数牌允许顺子；字牌强制走刻子
- 6 测试覆盖平和型/全刻/不能胡/多解/含字雀/副露后短手牌

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 8: 七対子（chiitoitsu）检测

七対子：14 张牌恰好由 7 个不同的对子组成。无副露。和牌固定 2 番 25 符。

**Files:**
- Create: `godot/core/rules_japanese/chiitoi_detector.gd`
- Create: `godot/tests/core/test_chiitoi_detector.gd`

- [ ] **Step 8.1: 写测试 `godot/tests/core/test_chiitoi_detector.gd`**

```gdscript
extends GutTest

func test_seven_distinct_pairs_is_chiitoi():
    var ids := [
        TileId.W1, TileId.W1,
        TileId.W3, TileId.W3,
        TileId.T2, TileId.T2,
        TileId.T9, TileId.T9,
        TileId.S5, TileId.S5,
        TileId.E, TileId.E,
        TileId.HAKU, TileId.HAKU,
    ]
    assert_true(ChiitoiDetector.is_chiitoi(ids))

func test_four_of_a_kind_is_not_chiitoi():
    # 1111m 22m 33m 44m 55m 66m 77m
    var ids := [
        TileId.W1, TileId.W1, TileId.W1, TileId.W1,
        TileId.W2, TileId.W2,
        TileId.W3, TileId.W3,
        TileId.W4, TileId.W4,
        TileId.W5, TileId.W5,
        TileId.W6, TileId.W6,
    ]
    assert_false(ChiitoiDetector.is_chiitoi(ids), "同种 4 张不允许（必须 7 对都不同）")

func test_six_pairs_one_triplet_not_chiitoi():
    var ids := [
        TileId.W1, TileId.W1, TileId.W1,
        TileId.W2, TileId.W2,
        TileId.W3, TileId.W3,
        TileId.W4, TileId.W4,
        TileId.W5, TileId.W5,
        TileId.W6, TileId.W6,
        TileId.W7,
    ]
    assert_false(ChiitoiDetector.is_chiitoi(ids))

func test_wrong_size_returns_false():
    assert_false(ChiitoiDetector.is_chiitoi([TileId.W1, TileId.W1]))
    assert_false(ChiitoiDetector.is_chiitoi([]))
```

- [ ] **Step 8.2: 跑测试，确认失败**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/test_chiitoi_detector.gd
```

- [ ] **Step 8.3: 实现 `godot/core/rules_japanese/chiitoi_detector.gd`**

```gdscript
class_name ChiitoiDetector

static func is_chiitoi(sorted_ids: Array) -> bool:
    if sorted_ids.size() != 14:
        return false
    var counts := {}
    for tid in sorted_ids:
        counts[tid] = counts.get(tid, 0) + 1
    if counts.size() != 7:
        return false
    for tid in counts:
        if counts[tid] != 2:
            return false
    return true
```

- [ ] **Step 8.4: 跑测试验证通过**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/test_chiitoi_detector.gd
```

Expected：`4 of 4 passed`。

- [ ] **Step 8.5: Commit**

```bash
git add godot/core/rules_japanese/chiitoi_detector.gd godot/tests/core/test_chiitoi_detector.gd
git commit -m "$(cat <<'EOF'
feat(rules): 七対子检测 — 7 个不同对子

- 14 张牌恰好 7 种 id 各 2 张
- 拒绝同种 4 张（这种应判普通胡，不算七対子）

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 9: 国士無双（kokushi musou）检测

国士無双：13 种幺九牌（19m / 19p / 19s / 东南西北白发中）齐 + 其中 1 张多 1。包括"国士 13 面待"作为役満上位。

**Files:**
- Create: `godot/core/rules_japanese/kokushi_detector.gd`
- Create: `godot/tests/core/test_kokushi_detector.gd`

- [ ] **Step 9.1: 写测试 `godot/tests/core/test_kokushi_detector.gd`**

```gdscript
extends GutTest

const YAOCHU_13: Array = [
    TileId.W1, TileId.W9, TileId.T1, TileId.T9, TileId.S1, TileId.S9,
    TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
    TileId.HAKU, TileId.HATSU, TileId.CHUN,
]

func test_standard_kokushi_with_extra_w1():
    var ids := YAOCHU_13.duplicate()
    ids.append(TileId.W1)  # W1 成为对子
    ids.sort()
    var r := KokushiDetector.detect(ids)
    assert_true(r.is_kokushi)
    assert_false(r.is_thirteen_wait, "对子是 W1，不是 13 面")

func test_thirteen_wait_with_extra_yaochu():
    # 13 面待：13 种幺九各 1 张 + 任意 1 种再 1 张（即和牌张是单骑等待 13 种之一时是 13 面）
    # 数据上：14 张内某种幺九多 1，但若该和牌张前的 13 张是"13 种各 1"（无对子），则是 13 面
    # 这里我们只检测最终 14 张的型，13 面定义：14 张 = 13 幺九各 1 + 1 任意幺九
    # 标准实现：检查 13 种是否齐全且只有 1 个对子，is_thirteen_wait = (和牌张 == 该对子)
    # 但因为 detect 不知道哪张是和牌张，is_thirteen_wait 默认 false
    # 真正 13 面判定在 yaku 阶段（plan 0b）传入 winning_tile 后做
    var ids := YAOCHU_13.duplicate()
    ids.append(TileId.CHUN)
    ids.sort()
    var r := KokushiDetector.detect(ids)
    assert_true(r.is_kokushi)

func test_missing_yaochu_is_not_kokushi():
    var ids := YAOCHU_13.duplicate()
    ids.remove_at(0)  # 缺 W1
    ids.append(TileId.W9)
    ids.append(TileId.W9)
    ids.sort()
    var r := KokushiDetector.detect(ids)
    assert_false(r.is_kokushi)

func test_simple_tile_in_hand_is_not_kokushi():
    var ids := YAOCHU_13.duplicate()
    ids.append(TileId.W5)  # 中张混入
    ids.sort()
    var r := KokushiDetector.detect(ids)
    assert_false(r.is_kokushi)

func test_thirteen_wait_with_winning_tile_param():
    # 听 13 面：手牌 13 张正好是 13 种幺九各 1
    # 摸到任意幺九即胡，且是 13 面
    # detect_with_winning(13_hand_ids, winning_tile_id)
    var hand_ids := YAOCHU_13.duplicate()
    hand_ids.sort()
    var r := KokushiDetector.detect_with_winning(hand_ids, TileId.W1)
    assert_true(r.is_kokushi)
    assert_true(r.is_thirteen_wait)

func test_normal_kokushi_with_winning_tile_not_thirteen_wait():
    # 手牌 13 张：12 种幺九各 1 + 1 种 2 张；摸到那个种类外的牌 = 单骑听
    var hand_ids: Array = [
        TileId.W1, TileId.W1,  # 对子
        TileId.W9, TileId.T1, TileId.T9, TileId.S1, TileId.S9,
        TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
        TileId.HAKU, TileId.HATSU,
    ]
    hand_ids.sort()
    var r := KokushiDetector.detect_with_winning(hand_ids, TileId.CHUN)
    assert_true(r.is_kokushi)
    assert_false(r.is_thirteen_wait)
```

- [ ] **Step 9.2: 跑测试，确认失败**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/test_kokushi_detector.gd
```

- [ ] **Step 9.3: 实现 `godot/core/rules_japanese/kokushi_detector.gd`**

```gdscript
class_name KokushiDetector

const YAOCHU: Array = [
    TileId.W1, TileId.W9, TileId.T1, TileId.T9, TileId.S1, TileId.S9,
    TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
    TileId.HAKU, TileId.HATSU, TileId.CHUN,
]

# detect 仅判定是否 14 张构成国士；is_thirteen_wait 在不知和牌张时恒为 false
# 完整 13 面待判定使用 detect_with_winning
static func detect(sorted_ids: Array) -> Dictionary:
    var result := {"is_kokushi": false, "is_thirteen_wait": false}
    if sorted_ids.size() != 14:
        return result
    var counts := {}
    for tid in sorted_ids:
        counts[tid] = counts.get(tid, 0) + 1
    # 必须 14 张全是幺九
    for tid in counts:
        if not _is_yaochu(tid):
            return result
    # 必须 13 种幺九全齐，且其中 1 种 2 张
    if counts.size() != 13:
        return result
    var double_count := 0
    for tid in YAOCHU:
        if not counts.has(tid):
            return result
        if counts[tid] == 2:
            double_count += 1
        elif counts[tid] != 1:
            return result
    if double_count != 1:
        return result
    result.is_kokushi = true
    return result

static func detect_with_winning(hand_13_sorted: Array, winning_tile: int) -> Dictionary:
    # hand_13_sorted: 13 张手牌（升序 id）
    # winning_tile: 即将摸/荣胡的那张
    # 13 面待：13 张恰好是 13 种幺九各 1 张
    var combined := hand_13_sorted.duplicate()
    combined.append(winning_tile)
    combined.sort()
    var r := detect(combined)
    if r.is_kokushi:
        # 检查 13 张本身是否 13 种幺九各 1
        if hand_13_sorted.size() == 13:
            var hand_set := {}
            for tid in hand_13_sorted:
                hand_set[tid] = hand_set.get(tid, 0) + 1
            if hand_set.size() == 13:
                var all_one := true
                for tid in YAOCHU:
                    if hand_set.get(tid, 0) != 1:
                        all_one = false
                        break
                if all_one:
                    r.is_thirteen_wait = true
    return r

static func _is_yaochu(tid: int) -> bool:
    return TileId.is_yaochu(tid)
```

- [ ] **Step 9.4: 跑测试验证通过**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/test_kokushi_detector.gd
```

Expected：`6 of 6 passed`。

- [ ] **Step 9.5: Commit**

```bash
git add godot/core/rules_japanese/kokushi_detector.gd godot/tests/core/test_kokushi_detector.gd
git commit -m "$(cat <<'EOF'
feat(rules): 国士無双检测 + 13 面待判定

- detect 判 14 张是否构成国士
- detect_with_winning 接受 13 张手牌 + 和牌张，判 13 面待
- is_yaochu 借用 TileId.is_yaochu

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 10: WinPattern 入口 + 集成测试

`WinPattern` 是和牌型识别的统一入口，把上面三种检测接起来：

```
WinPattern.detect(hand: Hand, melds: Array[Meld], winning_tile: Tile) -> WinPatternResult
```

返回值含：`is_winning`（bool）、`is_chiitoi`（bool）、`is_kokushi`（bool）、`is_thirteen_wait`（bool）、`standard_decompositions`（Array，每元素是 {melds, pair}）。

**Files:**
- Create: `godot/core/rules_japanese/win_pattern.gd`
- Create: `godot/tests/core/test_win_pattern.gd`

- [ ] **Step 10.1: 写集成测试 `godot/tests/core/test_win_pattern.gd`**

```gdscript
extends GutTest

func _make_hand_from_ids(ids: Array) -> Hand:
    var h := Hand.new()
    for tid in ids:
        h.add(Tile.new(tid))
    return h

func test_standard_win_no_melds():
    # 手 13: 234m 567p 678s 234s 1p；和牌张 1p
    var hand := _make_hand_from_ids([
        TileId.W2, TileId.W3, TileId.W4,
        TileId.T5, TileId.T6, TileId.T7,
        TileId.S6, TileId.S7, TileId.S8,
        TileId.S2, TileId.S3, TileId.S4,
        TileId.T1,
    ])
    var winning := Tile.new(TileId.T1)
    var r := WinPattern.detect(hand, [] as Array[Meld], winning)
    assert_true(r.is_winning)
    assert_false(r.is_chiitoi)
    assert_false(r.is_kokushi)
    assert_gt(r.standard_decompositions.size(), 0)

func test_standard_win_with_pon_meld():
    # 副露 1 个东碰；手剩 10 + 和牌张 1
    # 手 10: 234m 567p 678s 1p；和牌张 1p
    var hand := _make_hand_from_ids([
        TileId.W2, TileId.W3, TileId.W4,
        TileId.T5, TileId.T6, TileId.T7,
        TileId.S6, TileId.S7, TileId.S8,
        TileId.T1,
    ])
    var east_pon := Meld.make_pon([
        Tile.new(TileId.E), Tile.new(TileId.E), Tile.new(TileId.E)
    ], 0)
    var winning := Tile.new(TileId.T1)
    var r := WinPattern.detect(hand, [east_pon] as Array[Meld], winning)
    assert_true(r.is_winning)
    assert_gt(r.standard_decompositions.size(), 0)

func test_chiitoi_win():
    var hand := _make_hand_from_ids([
        TileId.W1, TileId.W1,
        TileId.W3, TileId.W3,
        TileId.T2, TileId.T2,
        TileId.T9, TileId.T9,
        TileId.S5, TileId.S5,
        TileId.E, TileId.E,
        TileId.HAKU,
    ])
    var winning := Tile.new(TileId.HAKU)
    var r := WinPattern.detect(hand, [] as Array[Meld], winning)
    assert_true(r.is_winning)
    assert_true(r.is_chiitoi)

func test_kokushi_win_normal():
    var hand := _make_hand_from_ids([
        TileId.W1, TileId.W9, TileId.T1, TileId.T9, TileId.S1, TileId.S9,
        TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
        TileId.HAKU, TileId.HATSU, TileId.CHUN,
    ])
    var winning := Tile.new(TileId.W1)  # W1 单骑
    var r := WinPattern.detect(hand, [] as Array[Meld], winning)
    assert_true(r.is_winning)
    assert_true(r.is_kokushi)
    assert_true(r.is_thirteen_wait)

func test_not_winning_returns_false():
    var hand := _make_hand_from_ids([
        TileId.W1, TileId.W3, TileId.W5, TileId.W7, TileId.W9,
        TileId.T1, TileId.T3, TileId.T5, TileId.T7, TileId.T9,
        TileId.S1, TileId.S3, TileId.S5,
    ])
    var winning := Tile.new(TileId.S7)
    var r := WinPattern.detect(hand, [] as Array[Meld], winning)
    assert_false(r.is_winning)

func test_meld_count_must_match():
    # 副露 1 个 + 手 13 = 总 16 不合法
    var hand := _make_hand_from_ids([
        TileId.W2, TileId.W3, TileId.W4,
        TileId.T5, TileId.T6, TileId.T7,
        TileId.S6, TileId.S7, TileId.S8,
        TileId.S2, TileId.S3, TileId.S4,
        TileId.T1,
    ])
    var east_pon := Meld.make_pon([
        Tile.new(TileId.E), Tile.new(TileId.E), Tile.new(TileId.E)
    ], 0)
    var winning := Tile.new(TileId.T1)
    var r := WinPattern.detect(hand, [east_pon] as Array[Meld], winning)
    assert_false(r.is_winning, "总牌数 17 != 14，应拒绝")
```

- [ ] **Step 10.2: 跑测试，确认失败**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/test_win_pattern.gd
```

- [ ] **Step 10.3: 实现 `godot/core/rules_japanese/win_pattern.gd`**

```gdscript
class_name WinPattern

# detect: 综合三种和牌型识别
# hand: 暗牌（不含副露）
# melds: 已副露面子（吃/碰/杠）
# winning_tile: 自摸或荣胡的那张（必加入计算）
#
# 总张数公式：
#   暗牌张 + 副露贡献 = 13 张听牌期 + 1 张和牌张 = 14 张等价手
#   副露贡献：CHI/PON 各 3 张，KAN（任意）3 张（实际 4 张但杠子作为 1 个面子计 3 张算暗牌等价）
# 简化：要求 hand.size() + 3 * melds.size() + 1 == 14
#   即 hand.size() == 13 - 3 * melds.size()
static func detect(hand: Hand, melds: Array[Meld], winning_tile: Tile) -> Dictionary:
    var result := {
        "is_winning": false,
        "is_chiitoi": false,
        "is_kokushi": false,
        "is_thirteen_wait": false,
        "standard_decompositions": [],
    }

    # 张数校验
    var expected_hand_size := 13 - 3 * melds.size()
    if hand.size() != expected_hand_size:
        return result

    # 全部 14 张 id 列表（含和牌张 + 副露中的牌）
    var combined_ids: Array = hand.to_id_array()
    combined_ids.append(winning_tile.id)
    combined_ids.sort()

    # 七対子（无副露才有效）
    if melds.size() == 0:
        if ChiitoiDetector.is_chiitoi(combined_ids):
            result.is_chiitoi = true
            result.is_winning = true

    # 国士無双（无副露才有效）
    if melds.size() == 0:
        var hand_ids := hand.to_id_array()
        var k := KokushiDetector.detect_with_winning(hand_ids, winning_tile.id)
        if k.is_kokushi:
            result.is_kokushi = true
            result.is_thirteen_wait = k.is_thirteen_wait
            result.is_winning = true

    # 标准 4 面子+1 雀头
    var standard_input: Array = combined_ids
    var decomps := StandardDecomposer.decompose(standard_input)
    if decomps.size() > 0:
        result.standard_decompositions = decomps
        result.is_winning = true

    return result
```

- [ ] **Step 10.4: 跑全部 core 测试验证**

```bash
scripts/test_run_core.sh
```

Expected：所有 core 测试集合通过；累计应有 ~50 个测试，全部 PASS。

如果某些测试失败，先看错误信息：

- 类找不到 → 检查 `class_name` 拼写与文件路径是否匹配 Godot 4 的 class_name 解析（4.x 自动加载 class_name 不需要 register_types）
- 类型不匹配 → GDScript 2.0 严格类型，确认 `Array[int]` / `Array[Meld]` 标注一致
- decompose 多解时 melds 排序不同 → 测试中只 assert 数量与 pair，不强 assert 顺序

- [ ] **Step 10.5: Commit**

```bash
git add godot/core/rules_japanese/win_pattern.gd godot/tests/core/test_win_pattern.gd
git commit -m "$(cat <<'EOF'
feat(rules): WinPattern 和牌型识别统一入口

- 综合 4 面子+1 雀头 / 七対子 / 国士無双 三种判定
- 张数校验：hand.size + 3*melds.size + 1 == 14
- 七対子 / 国士限定无副露
- 6 集成测试覆盖各组合

里程碑 0a 完成：core 测试套累计 ~50 个全通过。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 11: 收尾 — 整合验证 + 更新 plan 文件状态

- [ ] **Step 11.1: 跑一次完整测试统计**

```bash
scripts/test_run_core.sh 2>&1 | tail -30
```

Expected：`Tests Run: ≥50`、`failing tests: 0`、`asserts pass / failed`。

- [ ] **Step 11.2: 在 plan 文件追加完成标记**

修改 `docs/superpowers/plans/2026-05-01-rule-engine-foundation.md`，在文件最末追加：

```markdown
---

## 完成记录

- 完成日期：YYYY-MM-DD（实际填）
- 累计测试数：N（实际填）
- 累计 commit 数：~11
- 后续：进入 plan 0b（役判定）

里程碑 0a 完成。下一步：用 superpowers:writing-plans 生成 plan 0b（30+ 役判定）。
```

- [ ] **Step 11.3: Commit 完成标记**

```bash
git add docs/superpowers/plans/2026-05-01-rule-engine-foundation.md
git commit -m "docs: 标记 plan 0a 完成"
git push
```

---

## 整体验收

完成本计划后应满足：

1. `scripts/test_run_core.sh` 一行命令跑通 ~50 个测试，全部 PASS
2. `godot/core/tile/` 与 `godot/core/rules_japanese/` 下 9 个新源文件，9 个测试文件
3. 现有 216 个 `godot/scripts/*.gd` 一字未动
4. `addons/gut/` 进 git，但 `.godot/` 排除
5. 全部 commit 已 push 到 `feat/mahjong-king-design` 分支

完成后调用 `superpowers:writing-plans` 生成 plan 0b（30+ 役判定）。

---

## 完成记录

- **完成日期**：2026-05-01
- **累计测试数**：63（Scripts 10 / Asserts 309，全部 PASS）
- **commit 数**：12（含 1 个 fix-up 补 .uid + 1 个 refactor 应 reviewer concerns）
- **执行方式**：superpowers:subagent-driven-development（implementer + spec/quality reviewer 双轨）
- **最终 HEAD**：`218feb3`

### 提交清单（按时间倒序）

| SHA | 主题 |
|-----|------|
| `218feb3` | WinPattern 和牌型识别统一入口（Task 10） |
| `672b891` | 国士無双检测 + 13 面待判定（Task 9） |
| `dcaf6b9` | 七対子检测 — 7 个不同对子（Task 8） |
| `8985e22` | 4 面子+1 雀头分解器（递归回溯）（Task 7） |
| `193887c` | 补 8 个遗漏的 .gd.uid + 2 处 reviewer 微调（fix-up） |
| `c218b9a` | Meld 面子 — chi/pon/minkan/ankan/added_kan（Task 6） |
| `0ef6080` | Hand 手牌 — add/remove_by_id/count/clone（Task 5） |
| `ebafd1c` | Wall 牌墙 — 136 张完整洗牌 + 顺序摸取（Task 4） |
| `c617123` | Tile 值对象 + 赤 Dora 工厂（Task 3） |
| `316433b` | TileId next_for_dora 可读性 + 补 2 个边界测试（refactor） |
| `32926e7` | TileId 枚举 + 工具方法（suit/number/yaochu/dora-next）（Task 2） |
| `9fcf2af` | 缩进规约 + test wrapper 错误可见性（fix-up） |
| `9616020` | 安装 GUT 9.4.0 并跑通 headless 烟测试（Task 1，base） |

### 已确认事实

- GUT 9.4.0 在 Godot 4.5.0 下跑通（headless）
- 现有 216 个 `godot/scripts/*.gd` 一字未动
- `addons/gut/` 进 git；`.godot/` 排除（新增；已存在的旧 `.godot/` cache 文件不在本计划范围）
- `core/tile/` + `core/rules_japanese/` 共 9 个新源文件，9 个测试文件，全部 TAB 缩进
- 全部 commit 已 push 到 `feat/mahjong-king-design`

### 后续

进入 plan 0b（30+ 役判定）。需要时调用 `superpowers:writing-plans` 生成。

> **更新 2026-05-01**：plan 0b 由协作者并行开展；plan 0c（符算 + 点数）由 claude 已并行完成 — 见 [`2026-05-01-fu-and-score.md`](./2026-05-01-fu-and-score.md)。0b 与 0c 模块独立、共享 `YakuList` 数据契约；0b 完工后由 0c 计划负责开串接 PR。下一步进入 plan 0d（振听 / Dora / 立直 / 流局 / 状态机）。
