# 麻将王 — 里程碑 0b：日麻役判定 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 plan 0a 提供的 `WinPattern` 结果 + 局面 `GameContext` 之上，识别 30+ 个标准日麻役（含役満），返回带番数的 `YakuList`，并处理上位役覆盖下位役的互斥规则。

**Architecture:** `core/rules_japanese/yaku/` 子包；每个役一个独立 GDScript 静态函数 `detect(WinContext) -> YakuEntry?`，由统一入口 `YakuEvaluator.evaluate(win_pattern_result, game_context)` 收集成 `YakuList`。算法参考 [`MahjongRepository/mahjong`](https://github.com/MahjongRepository/mahjong) Python 实现（MIT），仅借鉴判定逻辑，不直接搬代码。每个役 TDD 独立判定 + 独立测试。

**Tech Stack:**
- Godot 4.5 + GDScript 2.0
- GUT 9.4.0（plan 0a 已装）
- 复用 plan 0a 的 `TileId / Tile / Hand / Meld / WinPattern / StandardDecomposer / ChiitoiDetector / KokushiDetector`

**Spec 锚点：** `docs/superpowers/specs/2026-05-01-mahjong-king-design.md` §3.2 日麻术语 / §13 里程碑 0 / §15 最高优先级风险（规则正确性）

> **缩进约定**：所有 `.gd` 文件用 **TAB** 缩进。本文档代码块用空格显示，写入文件必须转 TAB。每个 `.gd` 必须配 `.gd.uid`（git add 时一起加）。

---

## 覆盖役一览

按番数 + 类别分组，共 **38 个**役（满足 spec "30+" 要求）：

**State-driven (9)**：立直 / 一発 / 双立直 / 门前清自摸和 / 海底捞月 / 河底捞鱼 / 岭上开花 / 抢杠 / 天和地和（役満）

**Yakuhai (5)**：白 / 发 / 中 / 场风 / 自风（统一在一个 detector）

**Pattern 1 番 (4)**：平和 / 一杯口 / 断幺九 / 七対子（虽 2 番但单独判定）

**Pattern 2 番 (8)**：三色同顺 / 一气通贯 / 混全带幺九 / 対々和 / 三暗刻 / 三色同刻 / 三杠子 / 小三元

**Pattern 3 番 (3)**：二杯口 / 纯全带幺九 / 混一色

**Pattern 6 番 (1)**：清一色

**Yakuman (12)**：国士無双 / 国士13面 / 大三元 / 四暗刻 / 四暗刻単騎 / 字一色 / 绿一色 / 清老头 / 四杠子 / 小四喜 / 大四喜 / 九蓮宝燈 / 纯正九蓮宝燈

副露降番规则：三色同顺 / 一気通貫 / 混全带幺九 / 纯全带幺九 / 混一色 / 清一色 副露后各 -1 番。

互斥（上位覆盖）：
- 二杯口 ⊃ 一杯口（不叠加）
- 纯全带幺九 ⊃ 混全带幺九
- 清一色 ⊃ 混一色
- 大三元 ⊃ 小三元 + 役牌(三元)×2
- 四暗刻 ⊃ 対々和 + 三暗刻
- 字一色 ⊃ 混一色 + 役牌
- 大四喜 ⊃ 小四喜 + 役牌(场风/自风)
- 役満 与 普通役 不混算（役満时只统计役満番数）

---

## File Structure

```
godot/core/rules_japanese/yaku/
├── yaku_id.gd           # 所有役 enum + 显示名 + base_han + is_yakuman 表
├── yaku_entry.gd        # 值对象 {id, han, is_yakuman, name_zh}
├── yaku_list.gd         # 收集器 + 总番数计算 + 役満优先逻辑
├── game_context.gd      # bakaze / jikaze / riichi / ippatsu / tsumo / last_tile flags / first turn
├── win_context.gd       # WinPattern 结果 + GameContext + 辅助方法
├── menzen_helper.gd     # 是否门清（有暗杠仍门清）
├── yaku_evaluator.gd    # 入口：evaluate(...) -> YakuList
│
├── state/
│   ├── riichi.gd                # 立直
│   ├── ippatsu.gd               # 一発
│   ├── double_riichi.gd         # W立直
│   ├── menzen_tsumo.gd          # 门前清自摸和
│   ├── haitei.gd                # 海底捞月
│   ├── houtei.gd                # 河底捞鱼
│   ├── rinshan.gd               # 岭上开花
│   └── chankan.gd               # 抢杠
│
├── pattern/
│   ├── yakuhai.gd               # 白发中 + 场风 + 自风（一个文件统一处理）
│   ├── pinfu.gd                 # 平和
│   ├── iipeikou.gd              # 一杯口
│   ├── tanyao.gd                # 断幺九
│   ├── sanshoku_doujun.gd       # 三色同顺
│   ├── ittsu.gd                 # 一气通贯
│   ├── honchanta.gd             # 混全带幺九
│   ├── chiitoitsu.gd            # 七対子（包装 ChiitoiDetector，固定 2 番）
│   ├── toitoi.gd                # 対々和
│   ├── sanankou.gd              # 三暗刻
│   ├── sanshoku_doukou.gd       # 三色同刻
│   ├── sankantsu.gd             # 三杠子
│   ├── shousangen.gd            # 小三元
│   ├── ryanpeikou.gd            # 二杯口
│   ├── junchan.gd               # 纯全带幺九
│   ├── honitsu.gd               # 混一色
│   └── chinitsu.gd              # 清一色
│
└── yakuman/
    ├── kokushi.gd               # 国士無双 + 13面待
    ├── daisangen.gd             # 大三元
    ├── suuankou.gd              # 四暗刻 + 単騎
    ├── tsuuiisou.gd             # 字一色
    ├── ryuuiisou.gd             # 绿一色
    ├── chinroutou.gd            # 清老头
    ├── suukantsu.gd             # 四杠子
    ├── shousuushi.gd            # 小四喜
    ├── daisuushi.gd             # 大四喜（double yakuman）
    ├── chuuren.gd               # 九蓮宝燈 + 纯正九蓮（double yakuman）
    ├── tenhou.gd                # 天和（庄家配牌即胡）
    └── chiihou.gd               # 地和（闲家第一摸即胡）
```

测试镜像 `godot/tests/core/yaku/`，以及最终集成测试 `godot/tests/core/test_yaku_evaluator.gd`。

---

## Task 1: 框架数据类型 + Context

建立所有役判定共用的数据类型与上下文。本任务无算法逻辑，只是搭骨架。

**Files:**
- Create: `godot/core/rules_japanese/yaku/yaku_id.gd`
- Create: `godot/core/rules_japanese/yaku/yaku_entry.gd`
- Create: `godot/core/rules_japanese/yaku/yaku_list.gd`
- Create: `godot/core/rules_japanese/yaku/game_context.gd`
- Create: `godot/core/rules_japanese/yaku/menzen_helper.gd`
- Create: `godot/core/rules_japanese/yaku/win_context.gd`
- Create: `godot/tests/core/yaku/test_yaku_id.gd`
- Create: `godot/tests/core/yaku/test_yaku_list.gd`
- Create: `godot/tests/core/yaku/test_game_context.gd`
- Create: `godot/tests/core/yaku/test_menzen_helper.gd`
- Create: `godot/tests/core/yaku/test_win_context.gd`

- [ ] **Step 1.1: 写 `test_yaku_id.gd`**

```gdscript
extends GutTest

func test_id_count_is_38():
	assert_eq(YakuId.ALL.size(), 38, "覆盖 38 个役")

func test_riichi_metadata():
	var meta := YakuId.metadata(YakuId.RIICHI)
	assert_eq(meta.name_zh, "立直")
	assert_eq(meta.base_han_closed, 1)
	assert_eq(meta.base_han_open, 0)  # 立直要求门清
	assert_false(meta.is_yakuman)

func test_chinitsu_open_minus_one():
	var meta := YakuId.metadata(YakuId.CHINITSU)
	assert_eq(meta.base_han_closed, 6)
	assert_eq(meta.base_han_open, 5)

func test_kokushi_is_yakuman():
	var meta := YakuId.metadata(YakuId.KOKUSHI)
	assert_true(meta.is_yakuman)
	assert_eq(meta.yakuman_multiplier, 1)

func test_daisuushi_double_yakuman():
	var meta := YakuId.metadata(YakuId.DAISUUSHI)
	assert_true(meta.is_yakuman)
	assert_eq(meta.yakuman_multiplier, 2)
```

- [ ] **Step 1.2: 跑测试，确认失败（YakuId 不存在）**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/yaku/test_yaku_id.gd
```

- [ ] **Step 1.3: 实现 `godot/core/rules_japanese/yaku/yaku_id.gd`**

```gdscript
class_name YakuId

# State-driven
const RIICHI = 0
const IPPATSU = 1
const DOUBLE_RIICHI = 2
const MENZEN_TSUMO = 3
const HAITEI = 4
const HOUTEI = 5
const RINSHAN = 6
const CHANKAN = 7

# Yakuhai (统一 id；具体哪种由 detect 时附加 sub-tag)
const YAKUHAI_HAKU = 8
const YAKUHAI_HATSU = 9
const YAKUHAI_CHUN = 10
const YAKUHAI_BAKAZE = 11
const YAKUHAI_JIKAZE = 12

# 1 han pattern
const PINFU = 13
const IIPEIKOU = 14
const TANYAO = 15

# 2 han pattern
const SANSHOKU_DOUJUN = 16
const ITTSU = 17
const HONCHANTA = 18
const CHIITOITSU = 19
const TOITOI = 20
const SANANKOU = 21
const SANSHOKU_DOUKOU = 22
const SANKANTSU = 23
const SHOUSANGEN = 24

# 3 han pattern
const RYANPEIKOU = 25
const JUNCHAN = 26
const HONITSU = 27

# 6 han
const CHINITSU = 28

# Yakuman
const KOKUSHI = 29
const KOKUSHI_13 = 30           # 国士13面，double
const DAISANGEN = 31
const SUUANKOU = 32
const SUUANKOU_TANKI = 33       # 四暗刻単騎，double
const TSUUIISOU = 34
const RYUUIISOU = 35
const CHINROUTOU = 36
const SUUKANTSU = 37
const SHOUSUUSHI = 38
const DAISUUSHI = 39            # 大四喜，double
const CHUUREN = 40
const JUNSEI_CHUUREN = 41       # 纯正九蓮，double
const TENHOU = 42
const CHIIHOU = 43

const ALL: Array[int] = [
	0,1,2,3,4,5,6,7,
	8,9,10,11,12,
	13,14,15,
	16,17,18,19,20,21,22,23,24,
	25,26,27,
	28,
	# yakuman 占独立编号
	29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,
]
# 注：上面 ALL 仅含 38 个普通+役満索引（编号空隙是预留）。
# 实际数量校验通过排除 yakuman variants 共 5 个（KOKUSHI_13/SUUANKOU_TANKI/DAISUUSHI/JUNSEI_CHUUREN 是上位变体）
# 但 ALL 仍列全部以便迭代查询。

# 元数据：每个 id -> {name_zh, base_han_closed, base_han_open, is_yakuman, yakuman_multiplier}
static func metadata(yid: int) -> Dictionary:
	match yid:
		RIICHI: return {"name_zh": "立直", "base_han_closed": 1, "base_han_open": 0, "is_yakuman": false, "yakuman_multiplier": 0}
		IPPATSU: return {"name_zh": "一発", "base_han_closed": 1, "base_han_open": 0, "is_yakuman": false, "yakuman_multiplier": 0}
		DOUBLE_RIICHI: return {"name_zh": "W立直", "base_han_closed": 2, "base_han_open": 0, "is_yakuman": false, "yakuman_multiplier": 0}
		MENZEN_TSUMO: return {"name_zh": "门前清自摸和", "base_han_closed": 1, "base_han_open": 0, "is_yakuman": false, "yakuman_multiplier": 0}
		HAITEI: return {"name_zh": "海底捞月", "base_han_closed": 1, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		HOUTEI: return {"name_zh": "河底捞鱼", "base_han_closed": 1, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		RINSHAN: return {"name_zh": "岭上开花", "base_han_closed": 1, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		CHANKAN: return {"name_zh": "抢杠", "base_han_closed": 1, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		YAKUHAI_HAKU: return {"name_zh": "役牌·白", "base_han_closed": 1, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		YAKUHAI_HATSU: return {"name_zh": "役牌·发", "base_han_closed": 1, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		YAKUHAI_CHUN: return {"name_zh": "役牌·中", "base_han_closed": 1, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		YAKUHAI_BAKAZE: return {"name_zh": "场风牌", "base_han_closed": 1, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		YAKUHAI_JIKAZE: return {"name_zh": "自风牌", "base_han_closed": 1, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		PINFU: return {"name_zh": "平和", "base_han_closed": 1, "base_han_open": 0, "is_yakuman": false, "yakuman_multiplier": 0}
		IIPEIKOU: return {"name_zh": "一杯口", "base_han_closed": 1, "base_han_open": 0, "is_yakuman": false, "yakuman_multiplier": 0}
		TANYAO: return {"name_zh": "断幺九", "base_han_closed": 1, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		SANSHOKU_DOUJUN: return {"name_zh": "三色同顺", "base_han_closed": 2, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		ITTSU: return {"name_zh": "一気通貫", "base_han_closed": 2, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		HONCHANTA: return {"name_zh": "混全带幺九", "base_han_closed": 2, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		CHIITOITSU: return {"name_zh": "七対子", "base_han_closed": 2, "base_han_open": 0, "is_yakuman": false, "yakuman_multiplier": 0}
		TOITOI: return {"name_zh": "対々和", "base_han_closed": 2, "base_han_open": 2, "is_yakuman": false, "yakuman_multiplier": 0}
		SANANKOU: return {"name_zh": "三暗刻", "base_han_closed": 2, "base_han_open": 2, "is_yakuman": false, "yakuman_multiplier": 0}
		SANSHOKU_DOUKOU: return {"name_zh": "三色同刻", "base_han_closed": 2, "base_han_open": 2, "is_yakuman": false, "yakuman_multiplier": 0}
		SANKANTSU: return {"name_zh": "三杠子", "base_han_closed": 2, "base_han_open": 2, "is_yakuman": false, "yakuman_multiplier": 0}
		SHOUSANGEN: return {"name_zh": "小三元", "base_han_closed": 2, "base_han_open": 2, "is_yakuman": false, "yakuman_multiplier": 0}
		RYANPEIKOU: return {"name_zh": "二杯口", "base_han_closed": 3, "base_han_open": 0, "is_yakuman": false, "yakuman_multiplier": 0}
		JUNCHAN: return {"name_zh": "纯全带幺九", "base_han_closed": 3, "base_han_open": 2, "is_yakuman": false, "yakuman_multiplier": 0}
		HONITSU: return {"name_zh": "混一色", "base_han_closed": 3, "base_han_open": 2, "is_yakuman": false, "yakuman_multiplier": 0}
		CHINITSU: return {"name_zh": "清一色", "base_han_closed": 6, "base_han_open": 5, "is_yakuman": false, "yakuman_multiplier": 0}
		KOKUSHI: return {"name_zh": "国士無双", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
		KOKUSHI_13: return {"name_zh": "国士無双13面", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 2}
		DAISANGEN: return {"name_zh": "大三元", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
		SUUANKOU: return {"name_zh": "四暗刻", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
		SUUANKOU_TANKI: return {"name_zh": "四暗刻単騎", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 2}
		TSUUIISOU: return {"name_zh": "字一色", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
		RYUUIISOU: return {"name_zh": "绿一色", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
		CHINROUTOU: return {"name_zh": "清老头", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
		SUUKANTSU: return {"name_zh": "四杠子", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
		SHOUSUUSHI: return {"name_zh": "小四喜", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
		DAISUUSHI: return {"name_zh": "大四喜", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 2}
		CHUUREN: return {"name_zh": "九蓮宝燈", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
		JUNSEI_CHUUREN: return {"name_zh": "纯正九蓮宝燈", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 2}
		TENHOU: return {"name_zh": "天和", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
		CHIIHOU: return {"name_zh": "地和", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
	return {"name_zh": "?", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": false, "yakuman_multiplier": 0}
```

> 关于 `ALL.size()`：上面 const 定义到 43 但 `ALL` 数组列了 38 个 +5 个 yakuman variant = 43 项。本测试 assert 38 是非役満数。改 ALL 为只列 38 个非 variant，并新增 `ALL_VARIANTS`。

修正 ALL 的定义为：

```gdscript
# 38 个'基础'役（不含 yakuman 上位变体；变体由 detector 附加）
const ALL: Array[int] = [
	0,1,2,3,4,5,6,7,                # state 8
	8,9,10,11,12,                    # yakuhai 5
	13,14,15,                        # 1han pattern 3
	16,17,18,19,20,21,22,23,24,      # 2han pattern 9
	25,26,27,                        # 3han pattern 3
	28,                              # 6han 1
	29,31,32,34,35,36,37,38,40,42,43, # yakuman 11（不含 KOKUSHI_13/SUUANKOU_TANKI/DAISUUSHI/JUNSEI_CHUUREN/CHIIHOU... 等等）
]
# 38 = 8 + 5 + 3 + 9 + 3 + 1 + ?
```

> **修正**：上面计数有误。重新数：state 9（含 tenhou/chiihou 两个役満）+ yakuhai 5 + 1han 3 + 2han 9（含 chiitoi）+ 3han 3 + 6han 1 + yakuman 8（含 daisuushi/junsei chuuren/suuankou tanki/kokushi 13 是变体不计）= **38**。

最终 ALL 改为：

```gdscript
const ALL: Array[int] = [
	# state 9
	RIICHI, IPPATSU, DOUBLE_RIICHI, MENZEN_TSUMO, HAITEI, HOUTEI, RINSHAN, CHANKAN, TENHOU,
	CHIIHOU,
	# yakuhai 5
	YAKUHAI_HAKU, YAKUHAI_HATSU, YAKUHAI_CHUN, YAKUHAI_BAKAZE, YAKUHAI_JIKAZE,
	# 1 han 3
	PINFU, IIPEIKOU, TANYAO,
	# 2 han 9
	SANSHOKU_DOUJUN, ITTSU, HONCHANTA, CHIITOITSU, TOITOI, SANANKOU, SANSHOKU_DOUKOU, SANKANTSU, SHOUSANGEN,
	# 3 han 3
	RYANPEIKOU, JUNCHAN, HONITSU,
	# 6 han 1
	CHINITSU,
	# yakuman 7（不含变体）
	KOKUSHI, DAISANGEN, SUUANKOU, TSUUIISOU, RYUUIISOU, CHINROUTOU, SUUKANTSU, SHOUSUUSHI, CHUUREN,
]

const ALL_VARIANTS: Array[int] = [
	KOKUSHI_13, SUUANKOU_TANKI, DAISUUSHI, JUNSEI_CHUUREN,
]
```

> 数一下：state 10（含 chiihou）+ yakuhai 5 + 1han 3 + 2han 9 + 3han 3 + 6han 1 + yakuman 9 = **40**。

将测试 step 1.1 的 `assert_eq(YakuId.ALL.size(), 38, "...")` 改为 `assert_eq(YakuId.ALL.size(), 40, "覆盖 40 个基础役（不含变体）")` —— spec 说 30+，40 满足。**写 yaku_id.gd 时按此调整。**

- [ ] **Step 1.4: 跑测试验证通过**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/yaku/test_yaku_id.gd
```

Expected: `5/5 passed`。

- [ ] **Step 1.5: 写 `test_yaku_entry.gd`**

```gdscript
extends GutTest

func test_construct_normal_yaku():
	var e := YakuEntry.new(YakuId.RIICHI, 1, false, 0)
	assert_eq(e.yaku_id, YakuId.RIICHI)
	assert_eq(e.han, 1)
	assert_false(e.is_yakuman)

func test_construct_yakuman():
	var e := YakuEntry.new(YakuId.DAISANGEN, 0, true, 1)
	assert_true(e.is_yakuman)
	assert_eq(e.yakuman_multiplier, 1)

func test_construct_double_yakuman():
	var e := YakuEntry.new(YakuId.DAISUUSHI, 0, true, 2)
	assert_eq(e.yakuman_multiplier, 2)

func test_name_zh_lookup():
	var e := YakuEntry.new(YakuId.PINFU, 1, false, 0)
	assert_eq(e.name_zh(), "平和")
```

- [ ] **Step 1.6: 实现 `godot/core/rules_japanese/yaku/yaku_entry.gd`**

```gdscript
class_name YakuEntry

var yaku_id: int
var han: int               # 普通役番数；役満时为 0
var is_yakuman: bool
var yakuman_multiplier: int  # 役満倍数（1=单倍, 2=double）

func _init(p_id: int, p_han: int, p_is_yakuman: bool, p_yakuman_multiplier: int) -> void:
	yaku_id = p_id
	han = p_han
	is_yakuman = p_is_yakuman
	yakuman_multiplier = p_yakuman_multiplier

func name_zh() -> String:
	return YakuId.metadata(yaku_id).name_zh
```

- [ ] **Step 1.7: 跑 yaku_entry 测试验证通过**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/yaku/test_yaku_entry.gd
```

Expected: `4/4 passed`。

- [ ] **Step 1.8: 写 `test_yaku_list.gd`**

```gdscript
extends GutTest

func test_empty_list():
	var l := YakuList.new()
	assert_eq(l.size(), 0)
	assert_eq(l.total_han(), 0)
	assert_false(l.is_yakuman())

func test_add_one_normal():
	var l := YakuList.new()
	l.add(YakuEntry.new(YakuId.RIICHI, 1, false, 0))
	assert_eq(l.size(), 1)
	assert_eq(l.total_han(), 1)

func test_add_two_normal_sums_han():
	var l := YakuList.new()
	l.add(YakuEntry.new(YakuId.RIICHI, 1, false, 0))
	l.add(YakuEntry.new(YakuId.PINFU, 1, false, 0))
	assert_eq(l.total_han(), 2)

func test_yakuman_excludes_normal():
	# 一旦含役満：忽略所有普通役，total_han 不计算
	var l := YakuList.new()
	l.add(YakuEntry.new(YakuId.RIICHI, 1, false, 0))
	l.add(YakuEntry.new(YakuId.DAISANGEN, 0, true, 1))
	assert_true(l.is_yakuman())
	assert_eq(l.yakuman_total_multiplier(), 1)

func test_double_yakuman_stacks():
	var l := YakuList.new()
	l.add(YakuEntry.new(YakuId.DAISUUSHI, 0, true, 2))
	l.add(YakuEntry.new(YakuId.SUUANKOU_TANKI, 0, true, 2))
	assert_eq(l.yakuman_total_multiplier(), 4)
```

- [ ] **Step 1.9: 实现 `godot/core/rules_japanese/yaku/yaku_list.gd`**

```gdscript
class_name YakuList

var entries: Array[YakuEntry] = []

func size() -> int:
	return entries.size()

func add(entry: YakuEntry) -> void:
	entries.append(entry)

func is_yakuman() -> bool:
	for e in entries:
		if e.is_yakuman:
			return true
	return false

# 普通役番数（仅在非役満时调用）
func total_han() -> int:
	if is_yakuman():
		return 0
	var sum := 0
	for e in entries:
		sum += e.han
	return sum

# 役満累计倍数
func yakuman_total_multiplier() -> int:
	var total := 0
	for e in entries:
		if e.is_yakuman:
			total += e.yakuman_multiplier
	return total

# 调试用
func id_list() -> Array:
	var ids := []
	for e in entries:
		ids.append(e.yaku_id)
	return ids
```

- [ ] **Step 1.10: 跑 yaku_list 测试验证通过**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/yaku/test_yaku_list.gd
```

Expected: `5/5 passed`。

- [ ] **Step 1.11: 写 `test_game_context.gd`**

```gdscript
extends GutTest

func test_default_context_is_no_riichi_no_tsumo():
	var c := GameContext.new()
	assert_false(c.is_riichi)
	assert_false(c.is_tsumo)
	assert_false(c.is_ippatsu)

func test_set_basic_flags():
	var c := GameContext.new()
	c.bakaze = TileId.E
	c.jikaze = TileId.S_WIND
	c.is_riichi = true
	c.is_tsumo = true
	assert_eq(c.bakaze, TileId.E)
	assert_eq(c.jikaze, TileId.S_WIND)
	assert_true(c.is_riichi)
	assert_true(c.is_tsumo)

func test_dora_count_field():
	var c := GameContext.new()
	c.dora_count = 3
	assert_eq(c.dora_count, 3)
```

- [ ] **Step 1.12: 实现 `godot/core/rules_japanese/yaku/game_context.gd`**

```gdscript
class_name GameContext

# 场次信息
var bakaze: int = TileId.E              # 场风（东风战恒为 E）
var jikaze: int = TileId.E              # 自风（按 seat 决定）

# 立直状态
var is_riichi: bool = false
var is_double_riichi: bool = false
var is_ippatsu: bool = false            # 立直后一发窗口

# 和牌时机
var is_tsumo: bool = false              # 自摸 vs 荣胡
var is_haitei: bool = false             # 海底（牌墙最后一张自摸）
var is_houtei: bool = false             # 河底（最后一张弃牌荣胡）
var is_rinshan: bool = false            # 岭上开花（杠后自摸）
var is_chankan: bool = false            # 抢杠

# 第一巡（用于 W立直 / 天和 / 地和）
var is_first_turn_no_call: bool = false # 第 1 巡内无人鸣牌
var is_dealer_first_hand: bool = false  # 庄家初配牌即胡（天和）
var is_non_dealer_first_draw: bool = false  # 闲家第一摸即胡（地和）

# Dora 计数（仅符算用，yaku 判定不依赖；但七対子等可能需要）
var dora_count: int = 0
```

- [ ] **Step 1.13: 跑 game_context 测试**

Expected: `3/3 passed`。

- [ ] **Step 1.14: 写 `test_menzen_helper.gd`**

```gdscript
extends GutTest

func test_no_melds_is_menzen():
	assert_true(MenzenHelper.is_menzen([] as Array[Meld]))

func test_with_chi_not_menzen():
	var chi := Meld.make_chi([
		Tile.new(TileId.W2), Tile.new(TileId.W3), Tile.new(TileId.W4)
	], 0)
	assert_false(MenzenHelper.is_menzen([chi] as Array[Meld]))

func test_with_pon_not_menzen():
	var pon := Meld.make_pon([
		Tile.new(TileId.E), Tile.new(TileId.E), Tile.new(TileId.E)
	], 0)
	assert_false(MenzenHelper.is_menzen([pon] as Array[Meld]))

func test_only_ankan_still_menzen():
	# 暗杠不破门清
	var ankan := Meld.make_ankan([
		Tile.new(TileId.W1), Tile.new(TileId.W1), Tile.new(TileId.W1), Tile.new(TileId.W1)
	])
	assert_true(MenzenHelper.is_menzen([ankan] as Array[Meld]))

func test_minkan_breaks_menzen():
	var minkan := Meld.make_minkan([
		Tile.new(TileId.W1), Tile.new(TileId.W1), Tile.new(TileId.W1), Tile.new(TileId.W1)
	], 0)
	assert_false(MenzenHelper.is_menzen([minkan] as Array[Meld]))
```

- [ ] **Step 1.15: 实现 `godot/core/rules_japanese/yaku/menzen_helper.gd`**

```gdscript
class_name MenzenHelper

# 门清：除了暗杠之外没有其他副露
static func is_menzen(melds: Array[Meld]) -> bool:
	for m in melds:
		if m.kind != Meld.Kind.ANKAN:
			return false
	return true
```

- [ ] **Step 1.16: 跑 menzen_helper 测试**

Expected: `5/5 passed`。

- [ ] **Step 1.17: 写 `test_win_context.gd`**

```gdscript
extends GutTest

func _make_hand(ids: Array) -> Hand:
	var h := Hand.new()
	for tid in ids:
		h.add(Tile.new(tid))
	return h

func test_construct_with_winning_hand():
	# 234m 567p 678s 234s 11p 和 1p
	var hand := _make_hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1,
	])
	var winning := Tile.new(TileId.T1)
	var ctx := GameContext.new()
	var wp_result := WinPattern.detect(hand, [] as Array[Meld], winning)
	var wc := WinContext.new(hand, [] as Array[Meld], winning, wp_result, ctx)
	assert_true(wc.win_result.is_winning)
	assert_true(wc.is_menzen())
	assert_eq(wc.winning_tile.id, TileId.T1)

func test_is_menzen_with_meld():
	var hand := _make_hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.T1,
	])
	var pon := Meld.make_pon([
		Tile.new(TileId.E), Tile.new(TileId.E), Tile.new(TileId.E)
	], 0)
	var winning := Tile.new(TileId.T1)
	var ctx := GameContext.new()
	var wp_result := WinPattern.detect(hand, [pon] as Array[Meld], winning)
	var wc := WinContext.new(hand, [pon] as Array[Meld], winning, wp_result, ctx)
	assert_false(wc.is_menzen())
```

- [ ] **Step 1.18: 实现 `godot/core/rules_japanese/yaku/win_context.gd`**

```gdscript
class_name WinContext

var hand: Hand                          # 暗牌
var melds: Array[Meld]                  # 副露
var winning_tile: Tile                  # 和牌张
var win_result: Dictionary              # WinPattern.detect 的返回值
var game_context: GameContext

func _init(p_hand: Hand, p_melds: Array[Meld], p_winning: Tile, p_win_result: Dictionary, p_ctx: GameContext) -> void:
	hand = p_hand
	melds = p_melds
	winning_tile = p_winning
	win_result = p_win_result
	game_context = p_ctx

func is_menzen() -> bool:
	return MenzenHelper.is_menzen(melds)

# 全局所有牌的 id 数组（含和牌张 + 副露中的牌）
func all_tile_ids() -> Array:
	var ids: Array = hand.to_id_array()
	ids.append(winning_tile.id)
	for m in melds:
		for tid in m.to_id_array():
			ids.append(tid)
	ids.sort()
	return ids
```

- [ ] **Step 1.19: 跑 win_context 测试**

Expected: `2/2 passed`。

- [ ] **Step 1.20: Commit**

```bash
git add godot/core/rules_japanese/yaku/yaku_id.gd \
        godot/core/rules_japanese/yaku/yaku_id.gd.uid \
        godot/core/rules_japanese/yaku/yaku_entry.gd \
        godot/core/rules_japanese/yaku/yaku_entry.gd.uid \
        godot/core/rules_japanese/yaku/yaku_list.gd \
        godot/core/rules_japanese/yaku/yaku_list.gd.uid \
        godot/core/rules_japanese/yaku/game_context.gd \
        godot/core/rules_japanese/yaku/game_context.gd.uid \
        godot/core/rules_japanese/yaku/menzen_helper.gd \
        godot/core/rules_japanese/yaku/menzen_helper.gd.uid \
        godot/core/rules_japanese/yaku/win_context.gd \
        godot/core/rules_japanese/yaku/win_context.gd.uid \
        godot/tests/core/yaku/
git commit -m "$(cat <<'EOF'
feat(yaku): 役判定框架 — YakuId/Entry/List/Context

- YakuId 枚举 + 元数据（40 个基础役 + 4 个役満上位变体）
- YakuEntry 值对象 / YakuList 收集器（役満优先）
- GameContext / WinContext / MenzenHelper
- 19 个测试覆盖框架基本行为

为后续每个役独立 detector 准备好上下文与累加器。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 2: YakuEvaluator 骨架 + 立直 + 门前清自摸

证明框架能跑通：写一个能注册 detector 的入口，先接两个最简单的 state 役。

**Files:**
- Create: `godot/core/rules_japanese/yaku/yaku_evaluator.gd`
- Create: `godot/core/rules_japanese/yaku/state/riichi.gd`
- Create: `godot/core/rules_japanese/yaku/state/menzen_tsumo.gd`
- Create: `godot/tests/core/yaku/test_riichi.gd`
- Create: `godot/tests/core/yaku/test_menzen_tsumo.gd`
- Create: `godot/tests/core/yaku/test_yaku_evaluator.gd`

- [ ] **Step 2.1: 写 `test_riichi.gd`**

```gdscript
extends GutTest

func _make_winning_context(is_riichi: bool, is_double: bool = false) -> WinContext:
	var hand := Hand.new()
	for tid in [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1,
	]:
		hand.add(Tile.new(tid))
	var winning := Tile.new(TileId.T1)
	var ctx := GameContext.new()
	ctx.is_riichi = is_riichi
	ctx.is_double_riichi = is_double
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	return WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)

func test_riichi_when_declared_returns_entry():
	var wc := _make_winning_context(true)
	var e := Riichi.detect(wc)
	assert_not_null(e)
	assert_eq(e.yaku_id, YakuId.RIICHI)
	assert_eq(e.han, 1)

func test_riichi_when_not_declared_returns_null():
	var wc := _make_winning_context(false)
	var e := Riichi.detect(wc)
	assert_null(e)

func test_riichi_does_not_fire_when_double_riichi():
	# W立直时 RIICHI 不出（DOUBLE_RIICHI 替代）
	var wc := _make_winning_context(true, true)
	var e := Riichi.detect(wc)
	assert_null(e, "W立直时不再单独算 RIICHI")
```

- [ ] **Step 2.2: 跑测试，确认失败**

```bash
scripts/test_run_core.sh -gtest=res://tests/core/yaku/test_riichi.gd
```

- [ ] **Step 2.3: 实现 `godot/core/rules_japanese/yaku/state/riichi.gd`**

```gdscript
class_name Riichi

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.game_context.is_riichi:
		return null
	if wc.game_context.is_double_riichi:
		return null  # W立直时 RIICHI 不重复
	if not wc.is_menzen():
		return null  # 立直要求门清（理论上 game_context 不会矛盾，但防御）
	return YakuEntry.new(YakuId.RIICHI, 1, false, 0)
```

- [ ] **Step 2.4: 跑测试验证通过**

Expected: `3/3 passed`。

- [ ] **Step 2.5: 写 `test_menzen_tsumo.gd`**

```gdscript
extends GutTest

func _make_wc(is_tsumo: bool, melds: Array[Meld] = [] as Array[Meld]) -> WinContext:
	var hand := Hand.new()
	for tid in [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1,
	]:
		hand.add(Tile.new(tid))
	var winning := Tile.new(TileId.T1)
	var ctx := GameContext.new()
	ctx.is_tsumo = is_tsumo
	var wp := WinPattern.detect(hand, melds, winning)
	return WinContext.new(hand, melds, winning, wp, ctx)

func test_menzen_tsumo_when_menzen_and_tsumo():
	var wc := _make_wc(true)
	var e := MenzenTsumo.detect(wc)
	assert_not_null(e)
	assert_eq(e.yaku_id, YakuId.MENZEN_TSUMO)

func test_not_when_ron():
	var wc := _make_wc(false)
	var e := MenzenTsumo.detect(wc)
	assert_null(e)

func test_not_when_open():
	var hand := Hand.new()
	for tid in [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.T1,
	]:
		hand.add(Tile.new(tid))
	var pon := Meld.make_pon([
		Tile.new(TileId.E), Tile.new(TileId.E), Tile.new(TileId.E)
	], 0)
	var winning := Tile.new(TileId.T1)
	var ctx := GameContext.new()
	ctx.is_tsumo = true
	var wp := WinPattern.detect(hand, [pon] as Array[Meld], winning)
	var wc := WinContext.new(hand, [pon] as Array[Meld], winning, wp, ctx)
	var e := MenzenTsumo.detect(wc)
	assert_null(e, "副露后不算门前清自摸和")
```

- [ ] **Step 2.6: 实现 `godot/core/rules_japanese/yaku/state/menzen_tsumo.gd`**

```gdscript
class_name MenzenTsumo

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.game_context.is_tsumo:
		return null
	if not wc.is_menzen():
		return null
	return YakuEntry.new(YakuId.MENZEN_TSUMO, 1, false, 0)
```

- [ ] **Step 2.7: 跑 menzen_tsumo 测试**

Expected: `3/3 passed`。

- [ ] **Step 2.8: 写 `test_yaku_evaluator.gd`（最小集成测试）**

```gdscript
extends GutTest

func _make_basic_winning_hand() -> WinContext:
	var hand := Hand.new()
	for tid in [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1,
	]:
		hand.add(Tile.new(tid))
	var winning := Tile.new(TileId.T1)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	return WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)

func test_evaluator_returns_empty_for_no_yaku():
	var wc := _make_basic_winning_hand()
	# 无立直、无自摸 → 应返回空 YakuList
	var l := YakuEvaluator.evaluate(wc)
	assert_eq(l.size(), 0, "无任何役应返回空列表")

func test_evaluator_picks_up_riichi():
	var wc := _make_basic_winning_hand()
	wc.game_context.is_riichi = true
	var l := YakuEvaluator.evaluate(wc)
	var ids := l.id_list()
	assert_true(ids.has(YakuId.RIICHI))

func test_evaluator_picks_up_riichi_and_tsumo_together():
	var wc := _make_basic_winning_hand()
	wc.game_context.is_riichi = true
	wc.game_context.is_tsumo = true
	var l := YakuEvaluator.evaluate(wc)
	var ids := l.id_list()
	assert_true(ids.has(YakuId.RIICHI))
	assert_true(ids.has(YakuId.MENZEN_TSUMO))
	assert_eq(l.total_han(), 2)
```

- [ ] **Step 2.9: 实现 `godot/core/rules_japanese/yaku/yaku_evaluator.gd` 骨架**

```gdscript
class_name YakuEvaluator

# 入口：传入 WinContext，返回 YakuList。
# 当前只接 RIICHI 和 MENZEN_TSUMO 两个 detector。后续 task 逐步追加。
static func evaluate(wc: WinContext) -> YakuList:
	var list := YakuList.new()
	if not wc.win_result.is_winning:
		return list  # 未和牌直接空

	var detectors := [
		Riichi,
		MenzenTsumo,
	]
	for d in detectors:
		var entry := d.detect(wc)
		if entry != null:
			list.add(entry)
	return list
```

- [ ] **Step 2.10: 跑 evaluator 测试**

Expected: `3/3 passed`。

- [ ] **Step 2.11: 跑全套测试，确认 plan 0a 测试无回归**

```bash
scripts/test_run_core.sh 2>&1 | tail -10
```

Expected: 至少 75 个测试通过（plan 0a 63 + 本任务新增 12+）。

- [ ] **Step 2.12: Commit**

```bash
git add godot/core/rules_japanese/yaku/yaku_evaluator.gd \
        godot/core/rules_japanese/yaku/yaku_evaluator.gd.uid \
        godot/core/rules_japanese/yaku/state/riichi.gd \
        godot/core/rules_japanese/yaku/state/riichi.gd.uid \
        godot/core/rules_japanese/yaku/state/menzen_tsumo.gd \
        godot/core/rules_japanese/yaku/state/menzen_tsumo.gd.uid \
        godot/tests/core/yaku/test_riichi.gd \
        godot/tests/core/yaku/test_riichi.gd.uid \
        godot/tests/core/yaku/test_menzen_tsumo.gd \
        godot/tests/core/yaku/test_menzen_tsumo.gd.uid \
        godot/tests/core/yaku/test_yaku_evaluator.gd \
        godot/tests/core/yaku/test_yaku_evaluator.gd.uid
git commit -m "$(cat <<'EOF'
feat(yaku): YakuEvaluator 骨架 + 立直 + 门前清自摸和

- 立直：state-driven，要求门清；W立直时不重复
- 门前清自摸和：自摸 + 门清
- YakuEvaluator 入口注册两个 detector 验证管线
- 9 测试覆盖各分支

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 3: 剩余 state-driven 役

补齐：一発 / W立直 / 海底捞月 / 河底捞鱼 / 岭上开花 / 抢杠。每个独立 detector + 测试，最后一并注册到 YakuEvaluator。

**Files:**
- Create: `godot/core/rules_japanese/yaku/state/{ippatsu,double_riichi,haitei,houtei,rinshan,chankan}.gd` + `.uid`
- Create: `godot/tests/core/yaku/test_{ippatsu,double_riichi,haitei,houtei,rinshan,chankan}.gd` + `.uid`
- Modify: `godot/core/rules_japanese/yaku/yaku_evaluator.gd` (加入 6 个新 detector 到 list)

每个 detector 形态高度相似 —— 6 个一组写完一次 commit。

- [ ] **Step 3.1: 实现 6 个 state detector + 测试**

每个 .gd 文件结构如下，仅检查 `game_context` 中对应 flag。注意 W立直 与 RIICHI 互斥（之前已处理），其余各自独立。

`ippatsu.gd`：
```gdscript
class_name Ippatsu

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.game_context.is_ippatsu:
		return null
	if not wc.is_menzen():
		return null
	return YakuEntry.new(YakuId.IPPATSU, 1, false, 0)
```

`double_riichi.gd`：
```gdscript
class_name DoubleRiichi

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.game_context.is_double_riichi:
		return null
	if not wc.is_menzen():
		return null
	return YakuEntry.new(YakuId.DOUBLE_RIICHI, 2, false, 0)
```

`haitei.gd`、`houtei.gd`、`rinshan.gd`、`chankan.gd` 同理 —— 检查对应 flag，返回 1 番。`haitei` 要求 `is_tsumo=true`；`houtei` 要求 `is_tsumo=false`；`rinshan` 要求 `is_tsumo=true`（杠后摸的是岭上）；`chankan` 要求 `is_tsumo=false`（抢杠是荣胡）。

```gdscript
# haitei.gd
class_name Haitei
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.game_context.is_haitei:
		return null
	if not wc.game_context.is_tsumo:
		return null
	return YakuEntry.new(YakuId.HAITEI, 1, false, 0)

# houtei.gd
class_name Houtei
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.game_context.is_houtei:
		return null
	if wc.game_context.is_tsumo:
		return null
	return YakuEntry.new(YakuId.HOUTEI, 1, false, 0)

# rinshan.gd
class_name Rinshan
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.game_context.is_rinshan:
		return null
	if not wc.game_context.is_tsumo:
		return null
	return YakuEntry.new(YakuId.RINSHAN, 1, false, 0)

# chankan.gd
class_name Chankan
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.game_context.is_chankan:
		return null
	if wc.game_context.is_tsumo:
		return null
	return YakuEntry.new(YakuId.CHANKAN, 1, false, 0)
```

- [ ] **Step 3.2: 写 6 个对应测试，每个 detector 至少 2 个测试（flag true → entry，flag false → null，互斥/前置条件 → null）**

测试模板（以 ippatsu 为例，其他类比）：

```gdscript
# test_ippatsu.gd
extends GutTest

func _make_wc(is_ippatsu: bool, is_menzen: bool = true) -> WinContext:
	var hand := Hand.new()
	for tid in [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1,
	]:
		hand.add(Tile.new(tid))
	var melds: Array[Meld] = [] as Array[Meld]
	if not is_menzen:
		# 改成副露形态（暂略；测 menzen 路径用 melds=[]）
		pass
	var winning := Tile.new(TileId.T1)
	var ctx := GameContext.new()
	ctx.is_ippatsu = is_ippatsu
	var wp := WinPattern.detect(hand, melds, winning)
	return WinContext.new(hand, melds, winning, wp, ctx)

func test_ippatsu_when_flag_set():
	var e := Ippatsu.detect(_make_wc(true))
	assert_not_null(e)
	assert_eq(e.yaku_id, YakuId.IPPATSU)

func test_no_ippatsu_when_flag_clear():
	assert_null(Ippatsu.detect(_make_wc(false)))
```

按此模式为 double_riichi / haitei / houtei / rinshan / chankan 各写 2-3 测试。注意：
- haitei + tsumo=true → entry；haitei + tsumo=false → null
- houtei + tsumo=false → entry；houtei + tsumo=true → null
- rinshan + tsumo=true → entry
- chankan + tsumo=false → entry

- [ ] **Step 3.3: 修改 `yaku_evaluator.gd` 注册 6 个新 detector**

```gdscript
var detectors := [
	Riichi,
	DoubleRiichi,
	Ippatsu,
	MenzenTsumo,
	Haitei,
	Houtei,
	Rinshan,
	Chankan,
]
```

- [ ] **Step 3.4: 跑全套测试**

```bash
scripts/test_run_core.sh 2>&1 | tail -10
```

Expected: 累计 >= 90 测试，全过。

- [ ] **Step 3.5: Commit**

```bash
git add godot/core/rules_japanese/yaku/state/ \
        godot/tests/core/yaku/test_{ippatsu,double_riichi,haitei,houtei,rinshan,chankan}.gd* \
        godot/core/rules_japanese/yaku/yaku_evaluator.gd
git commit -m "$(cat <<'EOF'
feat(yaku): 剩余 state 役 — 一発 / W立直 / 海底 / 河底 / 岭上 / 抢杠

- 6 个 detector，每个仅检查 GameContext 对应 flag
- 与 tsumo/ron 时机正确互斥
- YakuEvaluator 注册全部 8 个 state detector
- 6 测试文件 + ~12 测试用例

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 4: Yakuhai（白发中 + 场风 + 自风）

5 个役统一在一个 detector 文件，因为判定逻辑一样：扫所有面子，三元牌刻子 → 对应 yakuhai；场风/自风刻子 → bakaze/jikaze。

**Files:**
- Create: `godot/core/rules_japanese/yaku/pattern/yakuhai.gd` + `.uid`
- Create: `godot/tests/core/yaku/test_yakuhai.gd` + `.uid`
- Modify: `yaku_evaluator.gd` 注册 Yakuhai

- [ ] **Step 4.1: 写 `test_yakuhai.gd`**

```gdscript
extends GutTest

func _hand_with_haku_pon(other_hand_ids: Array) -> WinContext:
	var hand := Hand.new()
	for tid in other_hand_ids:
		hand.add(Tile.new(tid))
	var haku_pon := Meld.make_pon([
		Tile.new(TileId.HAKU), Tile.new(TileId.HAKU), Tile.new(TileId.HAKU)
	], 0)
	var winning := Tile.new(other_hand_ids[other_hand_ids.size() - 1])  # 假设最后一张是和牌
	# 实际测试用更稳定的构造，这里简化
	var ctx := GameContext.new()
	ctx.bakaze = TileId.E
	ctx.jikaze = TileId.S_WIND
	var wp := WinPattern.detect(hand, [haku_pon] as Array[Meld], winning)
	return WinContext.new(hand, [haku_pon] as Array[Meld], winning, wp, ctx)

func test_haku_pon_in_meld_returns_haku():
	# 234m 567p 678s 11s + 副露 白白白 = 14 张
	var hand := Hand.new()
	for tid in [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S1,
	]:
		hand.add(Tile.new(tid))
	var haku_pon := Meld.make_pon([
		Tile.new(TileId.HAKU), Tile.new(TileId.HAKU), Tile.new(TileId.HAKU)
	], 0)
	var winning := Tile.new(TileId.S1)
	var ctx := GameContext.new()
	ctx.bakaze = TileId.E
	ctx.jikaze = TileId.S_WIND
	var wp := WinPattern.detect(hand, [haku_pon] as Array[Meld], winning)
	var wc := WinContext.new(hand, [haku_pon] as Array[Meld], winning, wp, ctx)
	var entries := Yakuhai.detect_all(wc)
	var ids: Array = []
	for e in entries:
		ids.append(e.yaku_id)
	assert_true(ids.has(YakuId.YAKUHAI_HAKU))
	assert_false(ids.has(YakuId.YAKUHAI_HATSU))
	assert_false(ids.has(YakuId.YAKUHAI_CHUN))

func test_haku_in_concealed_hand():
	# 234m 567p 678s 白白白 11s
	var hand := Hand.new()
	for tid in [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.HAKU, TileId.HAKU, TileId.HAKU,
		TileId.S1,
	]:
		hand.add(Tile.new(tid))
	var winning := Tile.new(TileId.S1)
	var ctx := GameContext.new()
	ctx.bakaze = TileId.E
	ctx.jikaze = TileId.S_WIND
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	var wc := WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)
	var entries := Yakuhai.detect_all(wc)
	var ids: Array = []
	for e in entries:
		ids.append(e.yaku_id)
	assert_true(ids.has(YakuId.YAKUHAI_HAKU))

func test_bakaze_east_with_east_pon():
	# 场风东，东刻子
	var hand := Hand.new()
	for tid in [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S1,
	]:
		hand.add(Tile.new(tid))
	var east_pon := Meld.make_pon([
		Tile.new(TileId.E), Tile.new(TileId.E), Tile.new(TileId.E)
	], 0)
	var winning := Tile.new(TileId.S1)
	var ctx := GameContext.new()
	ctx.bakaze = TileId.E
	ctx.jikaze = TileId.S_WIND  # 自风南
	var wp := WinPattern.detect(hand, [east_pon] as Array[Meld], winning)
	var wc := WinContext.new(hand, [east_pon] as Array[Meld], winning, wp, ctx)
	var entries := Yakuhai.detect_all(wc)
	var ids: Array = []
	for e in entries:
		ids.append(e.yaku_id)
	assert_true(ids.has(YakuId.YAKUHAI_BAKAZE))
	assert_false(ids.has(YakuId.YAKUHAI_JIKAZE), "自风是南，东刻不算自风")

func test_jikaze_south_with_south_pon():
	var hand := Hand.new()
	for tid in [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S1,
	]:
		hand.add(Tile.new(tid))
	var south_pon := Meld.make_pon([
		Tile.new(TileId.S_WIND), Tile.new(TileId.S_WIND), Tile.new(TileId.S_WIND)
	], 0)
	var winning := Tile.new(TileId.S1)
	var ctx := GameContext.new()
	ctx.bakaze = TileId.E
	ctx.jikaze = TileId.S_WIND
	var wp := WinPattern.detect(hand, [south_pon] as Array[Meld], winning)
	var wc := WinContext.new(hand, [south_pon] as Array[Meld], winning, wp, ctx)
	var entries := Yakuhai.detect_all(wc)
	var ids: Array = []
	for e in entries:
		ids.append(e.yaku_id)
	assert_true(ids.has(YakuId.YAKUHAI_JIKAZE))
	assert_false(ids.has(YakuId.YAKUHAI_BAKAZE), "场风东，南刻不算场风")

func test_double_east_when_jikaze_eq_bakaze():
	# 自风 == 场风（东 1 局庄家）
	var hand := Hand.new()
	for tid in [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S1,
	]:
		hand.add(Tile.new(tid))
	var east_pon := Meld.make_pon([
		Tile.new(TileId.E), Tile.new(TileId.E), Tile.new(TileId.E)
	], 0)
	var winning := Tile.new(TileId.S1)
	var ctx := GameContext.new()
	ctx.bakaze = TileId.E
	ctx.jikaze = TileId.E  # 庄家东 1 局
	var wp := WinPattern.detect(hand, [east_pon] as Array[Meld], winning)
	var wc := WinContext.new(hand, [east_pon] as Array[Meld], winning, wp, ctx)
	var entries := Yakuhai.detect_all(wc)
	var ids: Array = []
	for e in entries:
		ids.append(e.yaku_id)
	assert_true(ids.has(YakuId.YAKUHAI_BAKAZE))
	assert_true(ids.has(YakuId.YAKUHAI_JIKAZE), "庄家东 1 局，东刻同时是场风+自风（计 2 番）")

func test_no_yakuhai_for_pair_only():
	# 雀头是白，不算役牌
	var hand := Hand.new()
	for tid in [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.HAKU,
	]:
		hand.add(Tile.new(tid))
	var winning := Tile.new(TileId.HAKU)
	var ctx := GameContext.new()
	ctx.bakaze = TileId.E
	ctx.jikaze = TileId.S_WIND
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	var wc := WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)
	var entries := Yakuhai.detect_all(wc)
	assert_eq(entries.size(), 0, "雀头不算役牌")
```

- [ ] **Step 4.2: 跑测试，确认全失败（Yakuhai 不存在）**

- [ ] **Step 4.3: 实现 `pattern/yakuhai.gd`**

```gdscript
class_name Yakuhai

# detect_all 返回 0..N 个 YakuEntry（一手可同时含多个役牌：白+发+东 等）
static func detect_all(wc: WinContext) -> Array:
	var result: Array = []
	if not wc.win_result.is_winning:
		return result

	# 七対子 / 国士不参与役牌（型不同）
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return result

	# 收集所有"刻子/杠子"的 tile_id（手牌内 + 副露内）
	var triplet_ids: Array = []
	# 副露
	for m in wc.melds:
		match m.kind:
			Meld.Kind.PON, Meld.Kind.MINKAN, Meld.Kind.ANKAN, Meld.Kind.ADDED_KAN:
				triplet_ids.append(m.tiles[0].id)
	# 暗牌内的刻子（从 standard_decompositions 第一个分解读取）
	if wc.win_result.standard_decompositions.size() > 0:
		var d = wc.win_result.standard_decompositions[0]
		for meld_ids in d.melds:
			# meld_ids 形如 [id, id, id]：刻子时 3 个相同
			if meld_ids[0] == meld_ids[1] and meld_ids[1] == meld_ids[2]:
				triplet_ids.append(meld_ids[0])

	for tid in triplet_ids:
		match tid:
			TileId.HAKU:
				result.append(YakuEntry.new(YakuId.YAKUHAI_HAKU, 1, false, 0))
			TileId.HATSU:
				result.append(YakuEntry.new(YakuId.YAKUHAI_HATSU, 1, false, 0))
			TileId.CHUN:
				result.append(YakuEntry.new(YakuId.YAKUHAI_CHUN, 1, false, 0))
			TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N:
				if tid == wc.game_context.bakaze:
					result.append(YakuEntry.new(YakuId.YAKUHAI_BAKAZE, 1, false, 0))
				if tid == wc.game_context.jikaze:
					result.append(YakuEntry.new(YakuId.YAKUHAI_JIKAZE, 1, false, 0))
	return result
```

- [ ] **Step 4.4: 跑测试验证通过**

Expected: `7/7 passed`。

- [ ] **Step 4.5: 修改 yaku_evaluator.gd 注册 Yakuhai**

`Yakuhai` 是返回 Array 的特殊 detector。在 evaluator 里特殊处理：

```gdscript
static func evaluate(wc: WinContext) -> YakuList:
	var list := YakuList.new()
	if not wc.win_result.is_winning:
		return list
	# Single-entry detectors
	var single_detectors := [Riichi, DoubleRiichi, Ippatsu, MenzenTsumo, Haitei, Houtei, Rinshan, Chankan]
	for d in single_detectors:
		var e := d.detect(wc)
		if e != null:
			list.add(e)
	# Multi-entry detectors（返回 Array）
	for e in Yakuhai.detect_all(wc):
		list.add(e)
	return list
```

- [ ] **Step 4.6: 跑全套**

Expected: 累计 >= 100 测试。

- [ ] **Step 4.7: Commit**

```bash
git add godot/core/rules_japanese/yaku/pattern/yakuhai.gd \
        godot/core/rules_japanese/yaku/pattern/yakuhai.gd.uid \
        godot/tests/core/yaku/test_yakuhai.gd \
        godot/tests/core/yaku/test_yakuhai.gd.uid \
        godot/core/rules_japanese/yaku/yaku_evaluator.gd
git commit -m "$(cat <<'EOF'
feat(yaku): 役牌 — 白发中 + 场风 + 自风

- 扫描所有刻子/杠子（含副露），匹配 5 种役牌
- 庄家东 1 局东刻可同时算 BAKAZE + JIKAZE（2 番）
- 七対子/国士不参与役牌
- 雀头不算（必须刻子）
- 7 测试覆盖各组合

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 5: 平和（Pinfu）

最复杂的 1 番役。要求：(1) 门清；(2) 4 个面子全是顺子；(3) 雀头非役牌（非场风/自风/三元）；(4) 待ち是两面待ち（不是边/嵌/单骑/双碰）。

**Files:**
- Create: `godot/core/rules_japanese/yaku/pattern/pinfu.gd` + `.uid`
- Create: `godot/tests/core/yaku/test_pinfu.gd` + `.uid`
- Modify: `yaku_evaluator.gd`

- [ ] **Step 5.1: 写 `test_pinfu.gd`**

```gdscript
extends GutTest

func _make_wc(hand_ids: Array, winning_id: int, melds: Array[Meld] = [] as Array[Meld], jikaze: int = TileId.S_WIND, is_tsumo: bool = false) -> WinContext:
	var hand := Hand.new()
	for tid in hand_ids:
		hand.add(Tile.new(tid))
	var winning := Tile.new(winning_id)
	var ctx := GameContext.new()
	ctx.bakaze = TileId.E
	ctx.jikaze = jikaze
	ctx.is_tsumo = is_tsumo
	var wp := WinPattern.detect(hand, melds, winning)
	return WinContext.new(hand, melds, winning, wp, ctx)

func test_pinfu_pure_pinfu_pattern():
	# 234m 567p 678s 234s 11p，待 1p 两面（实际是单骑1p... 修改：12345p 等）
	# 标准 pinfu：234m 234p 567p 678s 67s+待5s/8s 两面，11s 雀头
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7,
		TileId.S1, TileId.S1,
	]
	var winning := TileId.S5  # 待 5s/8s 两面，摸到 5s 形成 567s
	# Hmm wait — 67s + 5s = 567s，但 hand 里是 67s 不带 5s，so 67s+5s 两面
	# 总暗 13 张：234m+234p+567p+67s+11s = 3+3+3+2+2 = 13 ✓
	# 加和牌 5s -> 4 面子 + 1 雀头 ✓
	var wc := _make_wc(hand_ids, winning)
	var e := Pinfu.detect(wc)
	assert_not_null(e, "标准平和应识别")
	assert_eq(e.han, 1)

func test_pinfu_fails_with_pon():
	# 有刻子 → 平和不成立
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.W5, TileId.W5, TileId.W5,  # 刻子
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7,
		TileId.S1, TileId.S1,
	]
	var wc := _make_wc(hand_ids, TileId.S5)
	assert_null(Pinfu.detect(wc))

func test_pinfu_fails_with_yakuhai_pair():
	# 雀头是白 → 平和不成立
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7,
		TileId.HAKU, TileId.HAKU,
	]
	var wc := _make_wc(hand_ids, TileId.S5)
	assert_null(Pinfu.detect(wc))

func test_pinfu_fails_with_jikaze_pair():
	# 雀头是自风（南）→ 平和不成立
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7,
		TileId.S_WIND, TileId.S_WIND,
	]
	var wc := _make_wc(hand_ids, TileId.S5, [] as Array[Meld], TileId.S_WIND)
	assert_null(Pinfu.detect(wc))

func test_pinfu_fails_when_open():
	# 副露不算门清，平和不成立
	var hand_ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S6, TileId.S7,
		TileId.S1, TileId.S1,
	]
	var chi := Meld.make_chi([
		Tile.new(TileId.T5), Tile.new(TileId.T6), Tile.new(TileId.T7)
	], 0)
	var wc := _make_wc(hand_ids, TileId.S5, [chi] as Array[Meld])
	assert_null(Pinfu.detect(wc))

func test_pinfu_fails_with_kanchan_wait():
	# 嵌张 5s（67s 改 68s 等 7s 嵌）→ 平和不成立
	# 实际：234m 234p 567p 68s 567s 11s 摸 7s 嵌
	# 暗 13: 234m+234p+567p+68s+567s+11s = 3+3+3+2+3+2 = 16... 错；调整
	# 234m+234p+78s+11p 11s ... 复杂；用 m1+m3 嵌 m2 演示
	var hand_ids := [
		TileId.W1, TileId.W3,                       # 嵌 m2 (要摸 m2)
		TileId.T2, TileId.T3, TileId.T4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S1, TileId.S1,
	]
	var wc := _make_wc(hand_ids, TileId.W2)
	assert_null(Pinfu.detect(wc), "嵌张待ち不算平和")
```

> 注：上面"两面待ち"的判定需要算法判断 winning_tile 是不是 顺子的两端之一且不是边张（123 等 3、789 等 7 是边张）。

- [ ] **Step 5.2: 实现 `pattern/pinfu.gd`**

```gdscript
class_name Pinfu

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	if not wc.is_menzen():
		return null
	if wc.melds.size() > 0:
		# 副露已包含暗杠时门清；上面 is_menzen 已过滤；保护：暗杠破坏面子全顺子
		for m in wc.melds:
			if m.is_kan():
				return null  # 杠子不是顺子
	# 检查每个 standard_decomposition
	for d in wc.win_result.standard_decompositions:
		if _check_decomposition(wc, d):
			return YakuEntry.new(YakuId.PINFU, 1, false, 0)
	return null

static func _check_decomposition(wc: WinContext, decomp: Dictionary) -> bool:
	# (1) 4 面子全是顺子
	for meld_ids in decomp.melds:
		if meld_ids[0] == meld_ids[1]:  # 刻子
			return false
	# (2) 雀头非役牌
	var pair_id: int = decomp.pair
	if _is_yakuhai_pair(pair_id, wc.game_context):
		return false
	# (3) 待ち是两面待ち
	if not _is_ryanmen_wait(decomp, wc.winning_tile.id):
		return false
	return true

static func _is_yakuhai_pair(pair_id: int, ctx: GameContext) -> bool:
	# 役牌：三元（白发中）+ 场风 + 自风
	if pair_id == TileId.HAKU or pair_id == TileId.HATSU or pair_id == TileId.CHUN:
		return true
	if pair_id == ctx.bakaze:
		return true
	if pair_id == ctx.jikaze:
		return true
	return false

# 两面待ち：和牌张是某个顺子的两端，且不是边张待ち（123 待 3 / 789 待 7）
static func _is_ryanmen_wait(decomp: Dictionary, winning_id: int) -> bool:
	for meld_ids in decomp.melds:
		# 顺子检测
		if meld_ids[0] != meld_ids[1] and meld_ids[1] - meld_ids[0] == 1 and meld_ids[2] - meld_ids[1] == 1:
			# winning 是这个顺子的成员？
			if meld_ids[0] == winning_id:
				# 和牌张在小端：是 a-b-c 的 a，要求 c 不是 9（因为 a=7 时 b=8 c=9 是边张待ち的镜像；实际这是 a 端两面）
				# 两面待ち要求：a > 1（即不是 12_3 的 3 单边）AND a < 7（即不是 7_8_9 的 7 单边？不，7-8-9 待 7 是单边）
				# 重新想：a-b-c 顺子，winning 在 a 端：原手是 b-c 等待 a 或 a+3。这是两面前提条件 a >= 2 AND c <= 8（即 a+2 <= 8 也即 a <= 6）
				# 当 a = 1：b=2 c=3，原手是 2-3 等 1 或 4 → 实际是 1-2-3 以 1 端待ち：但 2-3 也可待 4 形成 234，所以这是两面（1 端不算单边因为 4 那边可以）
				# Actually edge wait (penchan) 是 12 待 3 或 89 待 7 —— 即两端的对侧已封死
				# 1-2-3 winning=1：原手 2-3，等的是 1 或 4。1 那端是 a-b-c 的 a 端，原手 b-c 朝向左等 1 也朝向右等 4 → 两面（不算 penchan）
				# 12 待 3 (penchan)：原手 1-2，等的是 3。但题目假定 winning 已经形成顺子 a-b-c，所以 winning=3 时 a=1 b=2 c=3，winning 是 c 端
				# 所以判定：winning 在 c 端 AND a == 1 → penchan
				# winning 在 a 端 AND c == 9 → penchan
				# 否则（含中间 嵌张 也得判）→
				if meld_ids[2] == 9 + (meld_ids[0] - 1):  # not strictly accurate
					pass
				# 简化重写见下
				return _classify_wait_in_sequence(meld_ids, winning_id) == "ryanmen"
			elif meld_ids[2] == winning_id:
				return _classify_wait_in_sequence(meld_ids, winning_id) == "ryanmen"
			elif meld_ids[1] == winning_id:
				return false  # 嵌张待ち
	return false  # 没找到 winning_tile 在哪个顺子里 / 雀头单骑 / 双碰

static func _classify_wait_in_sequence(meld_ids: Array, winning_id: int) -> String:
	# meld_ids = [a, a+1, a+2]，winning_id 是 a / a+1 / a+2 之一
	# 返回 "ryanmen" / "kanchan" / "penchan"
	if winning_id == meld_ids[1]:
		return "kanchan"  # 嵌张
	# 中端确定后，剩两端
	var num: int = TileId.number(winning_id)
	if winning_id == meld_ids[0]:
		# winning 在 a 端：原手 b-c 等 a 或 a+3
		# penchan 当且仅当 a+3 不存在 → 即 a+3 跨过 9 → c == 9
		if TileId.number(meld_ids[2]) == 9:
			return "penchan"
		return "ryanmen"
	if winning_id == meld_ids[2]:
		# winning 在 c 端：原手 a-b 等 c 或 a-1
		if num == 3 and TileId.number(meld_ids[0]) == 1:
			return "penchan"
		return "ryanmen"
	return ""
```

> 上述 _is_ryanmen_wait 第一版有冗余逻辑，正式实现时建议简化为：先找 winning 落在哪个顺子（可能多个匹配），任一匹配返回 ryanmen 即合格。**写实现时按 _classify_wait_in_sequence 重写整个逻辑。** 雀头单骑 / 双碰待 不属于顺子内待ち，故返 false。

- [ ] **Step 5.3: 跑 pinfu 测试**

Expected: `6/6 passed`。

- [ ] **Step 5.4: 修改 evaluator 注册 Pinfu**

```gdscript
var single_detectors := [..., Pinfu]  # 加在合适位置
```

- [ ] **Step 5.5: 跑全套 + Commit**

```bash
scripts/test_run_core.sh 2>&1 | tail -8
git add godot/core/rules_japanese/yaku/pattern/pinfu.gd \
        godot/core/rules_japanese/yaku/pattern/pinfu.gd.uid \
        godot/tests/core/yaku/test_pinfu.gd \
        godot/tests/core/yaku/test_pinfu.gd.uid \
        godot/core/rules_japanese/yaku/yaku_evaluator.gd
git commit -m "feat(yaku): 平和 — 门清+4顺子+非役牌雀头+两面待ち

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

## Task 6: 一杯口 / 二杯口 / 断幺九

3 个 1-3 番役，分两步：先做 一杯口 + 断幺九；再做 二杯口（与一杯口互斥）。

**Files:**
- Create: `pattern/iipeikou.gd` + `.uid` + 测试
- Create: `pattern/ryanpeikou.gd` + `.uid` + 测试
- Create: `pattern/tanyao.gd` + `.uid` + 测试

- [ ] **Step 6.1: 实现并 TDD `pattern/iipeikou.gd`**

```gdscript
class_name Iipeikou

# 一杯口：门清 + 标准型 + 至少 1 对完全相同的顺子
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	if not wc.is_menzen():
		return null
	for d in wc.win_result.standard_decompositions:
		var pairs := _count_identical_sequence_pairs(d)
		if pairs == 1:  # 恰好 1 对（2 对是二杯口）
			return YakuEntry.new(YakuId.IIPEIKOU, 1, false, 0)
	return null

static func _count_identical_sequence_pairs(decomp: Dictionary) -> int:
	# 收集顺子 id 数组的 sorted-tuple 作 key
	var seq_keys: Dictionary = {}
	for meld_ids in decomp.melds:
		if meld_ids[0] != meld_ids[1] and meld_ids[2] - meld_ids[0] == 2:
			# 顺子
			var key := str(meld_ids[0]) + "-" + str(meld_ids[1]) + "-" + str(meld_ids[2])
			seq_keys[key] = seq_keys.get(key, 0) + 1
	var pairs := 0
	for k in seq_keys:
		if seq_keys[k] >= 2:
			pairs += int(seq_keys[k] / 2)
	return pairs
```

测试：标准 iipeikou hand（如 234m 234m 567p 678s 11s 待 5s）→ entry；副露 → null；二杯口型 → null（让 ryanpeikou 出）。

- [ ] **Step 6.2: 实现并 TDD `pattern/ryanpeikou.gd`**

```gdscript
class_name Ryanpeikou

# 二杯口：门清 + 2 对完全相同的顺子
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	if not wc.is_menzen():
		return null
	for d in wc.win_result.standard_decompositions:
		var pairs := Iipeikou._count_identical_sequence_pairs(d)
		if pairs >= 2:
			return YakuEntry.new(YakuId.RYANPEIKOU, 3, false, 0)
	return null
```

测试：二杯口型（如 234m 234m 678p 678p 11s 待 1s）→ entry；一杯口型 → null。

- [ ] **Step 6.3: 实现并 TDD `pattern/tanyao.gd`**

```gdscript
class_name Tanyao

# 断幺九：所有牌都是 2-8 数牌（无幺九，无字牌）
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	for tid in wc.all_tile_ids():
		if not TileId.is_simple(tid):
			return null
	return YakuEntry.new(YakuId.TANYAO, 1, false, 0)
```

测试：全 2-8 数牌 → entry；含 1m → null；含字牌 → null；副露中含 1m → null。

- [ ] **Step 6.4: 注册到 evaluator + Commit**

```gdscript
var single_detectors := [..., Iipeikou, Ryanpeikou, Tanyao]
```

```bash
git add godot/core/rules_japanese/yaku/pattern/{iipeikou,ryanpeikou,tanyao}.gd* \
        godot/tests/core/yaku/test_{iipeikou,ryanpeikou,tanyao}.gd* \
        godot/core/rules_japanese/yaku/yaku_evaluator.gd
git commit -m "feat(yaku): 一杯口 / 二杯口 / 断幺九

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push
```

---

## Task 7: 三色同顺 + 一気通貫

**Files:** `pattern/{sanshoku_doujun,ittsu}.gd` + 测试

- [ ] **Step 7.1: `sanshoku_doujun.gd`**

```gdscript
class_name SanshokuDoujun

# 三色同顺：万/筒/索 三色各有一个相同数字开头的顺子（如 234m + 234p + 234s）
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	# 收集所有顺子（暗 + 明）
	var seqs := _collect_all_sequences(wc)
	# 按起始数字分组：哪些起始数字在三花色都有顺子
	var by_start: Dictionary = {}  # number -> set of suits
	for s in seqs:
		var num: int = TileId.number(s[0])
		var suit: int = TileId.suit(s[0])
		if not by_start.has(num):
			by_start[num] = {}
		by_start[num][suit] = true
	for num in by_start:
		var suits: Dictionary = by_start[num]
		if suits.has(TileId.Suit.MAN) and suits.has(TileId.Suit.PIN) and suits.has(TileId.Suit.SOU):
			var han := 2 if wc.is_menzen() else 1
			return YakuEntry.new(YakuId.SANSHOKU_DOUJUN, han, false, 0)
	return null

static func _collect_all_sequences(wc: WinContext) -> Array:
	var result: Array = []
	# 副露
	for m in wc.melds:
		if m.kind == Meld.Kind.CHI:
			result.append([m.tiles[0].id, m.tiles[1].id, m.tiles[2].id])
	# 暗
	if wc.win_result.standard_decompositions.size() > 0:
		var d = wc.win_result.standard_decompositions[0]
		for meld_ids in d.melds:
			if meld_ids[0] != meld_ids[1] and meld_ids[2] - meld_ids[0] == 2:
				result.append(meld_ids)
	return result
```

测试：234m+234p+234s + 11s 雀 → entry han=2；只有 234m+234p → null；副露后 → han=1。

- [ ] **Step 7.2: `ittsu.gd`**

```gdscript
class_name Ittsu

# 一气通贯：同一花色的 123 + 456 + 789（同色全套数字）
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	# 按花色收集顺子起始数字
	var by_suit: Dictionary = {}  # suit -> set of start_numbers
	for s in SanshokuDoujun._collect_all_sequences(wc):
		var suit: int = TileId.suit(s[0])
		var num: int = TileId.number(s[0])
		if TileId.is_honor(s[0]):
			continue
		if not by_suit.has(suit):
			by_suit[suit] = {}
		by_suit[suit][num] = true
	for suit in by_suit:
		var nums: Dictionary = by_suit[suit]
		if nums.has(1) and nums.has(4) and nums.has(7):
			var han := 2 if wc.is_menzen() else 1
			return YakuEntry.new(YakuId.ITTSU, han, false, 0)
	return null
```

测试：123m+456m+789m+其他面子 → entry；123m+456m（缺 789）→ null。

- [ ] **Step 7.3: 注册 + Commit**

---

## Task 8: 対々和 / 三暗刻 / 三色同刻 / 三杠子 / 小三元

5 个刻子向 2 番役，集中处理。

**Files:** `pattern/{toitoi,sanankou,sanshoku_doukou,sankantsu,shousangen}.gd` + 测试

- [ ] **Step 8.1: `toitoi.gd`** — 4 面子全是刻子（含杠）

```gdscript
class_name Toitoi

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	# 副露顺子立即排除
	for m in wc.melds:
		if m.kind == Meld.Kind.CHI:
			return null
	# standard_decomp 中所有面子必须是刻子
	if wc.win_result.standard_decompositions.size() == 0:
		return null
	for d in wc.win_result.standard_decompositions:
		var all_triplet := true
		for meld_ids in d.melds:
			if meld_ids[0] != meld_ids[1]:  # 顺子
				all_triplet = false
				break
		if all_triplet:
			return YakuEntry.new(YakuId.TOITOI, 2, false, 0)
	return null
```

- [ ] **Step 8.2: `sanankou.gd`** — 3 个暗刻（被荣胡的刻子算明刻不算暗刻）

```gdscript
class_name Sanankou

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	var ankou_count := 0
	# 副露中的暗杠是暗刻
	for m in wc.melds:
		if m.kind == Meld.Kind.ANKAN:
			ankou_count += 1
	# 暗牌中的刻子
	if wc.win_result.standard_decompositions.size() == 0:
		return null
	# 用任意一个 decomp（多解时取暗刻数最多的）
	var best := 0
	for d in wc.win_result.standard_decompositions:
		var count := ankou_count
		for meld_ids in d.melds:
			if meld_ids[0] == meld_ids[1] and meld_ids[1] == meld_ids[2]:
				# 刻子 — 但若是被荣胡的刻子（winning_tile 是这个刻子的成员且 is_tsumo=false），不算暗刻
				if meld_ids[0] == wc.winning_tile.id and not wc.game_context.is_tsumo:
					pass  # 明刻
				else:
					count += 1
		if count > best:
			best = count
	if best >= 3:
		return YakuEntry.new(YakuId.SANANKOU, 2, false, 0)
	return null
```

- [ ] **Step 8.3: `sanshoku_doukou.gd`** — 万/筒/索 三色同数字刻子

```gdscript
class_name SanshokuDoukou

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	# 收集所有刻子的 tile_id
	var triplets: Array = []
	for m in wc.melds:
		match m.kind:
			Meld.Kind.PON, Meld.Kind.MINKAN, Meld.Kind.ANKAN, Meld.Kind.ADDED_KAN:
				triplets.append(m.tiles[0].id)
	if wc.win_result.standard_decompositions.size() > 0:
		var d = wc.win_result.standard_decompositions[0]
		for meld_ids in d.melds:
			if meld_ids[0] == meld_ids[1] and meld_ids[1] == meld_ids[2]:
				triplets.append(meld_ids[0])
	# 按数字分组找三花色齐
	var by_num: Dictionary = {}
	for tid in triplets:
		if TileId.is_honor(tid):
			continue
		var num: int = TileId.number(tid)
		var suit: int = TileId.suit(tid)
		if not by_num.has(num):
			by_num[num] = {}
		by_num[num][suit] = true
	for num in by_num:
		var s: Dictionary = by_num[num]
		if s.has(TileId.Suit.MAN) and s.has(TileId.Suit.PIN) and s.has(TileId.Suit.SOU):
			return YakuEntry.new(YakuId.SANSHOKU_DOUKOU, 2, false, 0)
	return null
```

- [ ] **Step 8.4: `sankantsu.gd`** — 3 个杠子（任意类型）

```gdscript
class_name Sankantsu

static func detect(wc: WinContext) -> YakuEntry:
	var kan_count := 0
	for m in wc.melds:
		if m.is_kan():
			kan_count += 1
	if kan_count == 3:
		return YakuEntry.new(YakuId.SANKANTSU, 2, false, 0)
	return null
```

- [ ] **Step 8.5: `shousangen.gd`** — 三元牌 2 刻 + 1 对（白发中其中一个为雀头）

```gdscript
class_name Shousangen

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	if wc.win_result.standard_decompositions.size() == 0:
		return null
	for d in wc.win_result.standard_decompositions:
		var dragon_pon := 0
		var dragon_pair := false
		# 副露中的三元刻
		for m in wc.melds:
			if m.tiles.size() >= 3 and (m.tiles[0].id == TileId.HAKU or m.tiles[0].id == TileId.HATSU or m.tiles[0].id == TileId.CHUN):
				if m.kind != Meld.Kind.CHI:
					dragon_pon += 1
		# 暗 melds 中的三元刻
		for meld_ids in d.melds:
			if meld_ids[0] == meld_ids[1] and meld_ids[1] == meld_ids[2]:
				if meld_ids[0] == TileId.HAKU or meld_ids[0] == TileId.HATSU or meld_ids[0] == TileId.CHUN:
					dragon_pon += 1
		# 雀头三元
		if d.pair == TileId.HAKU or d.pair == TileId.HATSU or d.pair == TileId.CHUN:
			dragon_pair = true
		if dragon_pon == 2 and dragon_pair:
			return YakuEntry.new(YakuId.SHOUSANGEN, 2, false, 0)
	return null
```

- [ ] **Step 8.6: 测试 + 注册 + Commit**

每个 detector 配 3-5 测试用例。注册到 evaluator。Commit message 列 5 个役。

---

## Task 9: 混全带幺九 + 七対子

`honchanta` + `chiitoitsu`。

**Files:** `pattern/{honchanta,chiitoitsu}.gd` + 测试

- [ ] **Step 9.1: `honchanta.gd`** — 每个面子 + 雀头都含幺九（含字牌），且至少 1 个顺子（含数牌幺九的 123/789）

```gdscript
class_name Honchanta

# 混全带幺九：4 面子 + 雀头都含幺九（含字牌），且不全是幺九（区分清老头）
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	if wc.win_result.standard_decompositions.size() == 0:
		return null
	for d in wc.win_result.standard_decompositions:
		var ok := true
		var has_simple_in_some_meld := false  # 是否存在中张（顺子 234567 等）
		# 雀头
		if not TileId.is_yaochu(d.pair):
			ok = false
		# 副露
		if ok:
			for m in wc.melds:
				var ids: Array = m.to_id_array()
				if not _meld_contains_yaochu(ids):
					ok = false
					break
		# 暗 melds
		if ok:
			for meld_ids in d.melds:
				if not _meld_contains_yaochu(meld_ids):
					ok = false
					break
				# 检查是否包含简单牌（用于排除清老头/字一色 → 那两个是上位役）
				for tid in meld_ids:
					if not TileId.is_yaochu(tid):
						has_simple_in_some_meld = true
						break
		if ok and has_simple_in_some_meld:
			# 至少有一个 meld 含中张：意味着是顺子（含 123 或 789 那种）→ honchanta 成立
			# 排除全幺九（清老头/字一色）—— 由上位役覆盖
			# 但 honchanta 本身要求"每个 meld 都含幺九"，所以 如果含字牌且无中张是清老头/字一色
			# Junchan 是 honchanta 子集（不含字牌）— Junchan detect 时如果命中 也命中 honchanta
			# 互斥规则在 evaluator 中处理；这里独立判定
			var han := 2 if wc.is_menzen() else 1
			return YakuEntry.new(YakuId.HONCHANTA, han, false, 0)
	return null

static func _meld_contains_yaochu(ids: Array) -> bool:
	for tid in ids:
		if TileId.is_yaochu(tid):
			return true
	return false
```

- [ ] **Step 9.2: `chiitoitsu.gd`** — 包装 ChiitoiDetector

```gdscript
class_name Chiitoitsu

static func detect(wc: WinContext) -> YakuEntry:
	if wc.win_result.is_chiitoi:
		return YakuEntry.new(YakuId.CHIITOITSU, 2, false, 0)
	return null
```

- [ ] **Step 9.3: 测试 + 注册 + Commit**

---

## Task 10: 纯全带幺九 + 混一色 + 清一色

3 个高番役。

**Files:** `pattern/{junchan,honitsu,chinitsu}.gd` + 测试

- [ ] **Step 10.1: `junchan.gd`** — Honchanta 的更严格版（不含字牌）

```gdscript
class_name Junchan

# 纯全带幺九：每面子+雀头都含老头（数牌 1/9，无字牌）
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	if wc.win_result.standard_decompositions.size() == 0:
		return null
	# 全部 tile id 不能含字牌
	for tid in wc.all_tile_ids():
		if TileId.is_honor(tid):
			return null
	for d in wc.win_result.standard_decompositions:
		var ok := true
		if not TileId.is_terminal(d.pair):
			ok = false
		if ok:
			for m in wc.melds:
				if not _meld_contains_terminal(m.to_id_array()):
					ok = false
					break
		if ok:
			for meld_ids in d.melds:
				if not _meld_contains_terminal(meld_ids):
					ok = false
					break
		if ok:
			var han := 3 if wc.is_menzen() else 2
			return YakuEntry.new(YakuId.JUNCHAN, han, false, 0)
	return null

static func _meld_contains_terminal(ids: Array) -> bool:
	for tid in ids:
		if TileId.is_terminal(tid):
			return true
	return false
```

- [ ] **Step 10.2: `honitsu.gd`** — 1 花色数牌 + 字牌

```gdscript
class_name Honitsu

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_kokushi:
		return null
	# 收集除字牌外的所有花色
	var suits: Dictionary = {}
	for tid in wc.all_tile_ids():
		if not TileId.is_honor(tid):
			suits[TileId.suit(tid)] = true
	if suits.size() != 1:
		return null  # 0 = 全字牌（字一色）；2+ = 多色
	# 至少含 1 张字牌（不然是清一色）
	var has_honor := false
	for tid in wc.all_tile_ids():
		if TileId.is_honor(tid):
			has_honor = true
			break
	if not has_honor:
		return null
	var han := 3 if wc.is_menzen() else 2
	return YakuEntry.new(YakuId.HONITSU, han, false, 0)
```

- [ ] **Step 10.3: `chinitsu.gd`** — 1 花色数牌（无字牌）

```gdscript
class_name Chinitsu

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_kokushi:
		return null
	var suits: Dictionary = {}
	for tid in wc.all_tile_ids():
		if TileId.is_honor(tid):
			return null  # 含字牌不是清一色
		suits[TileId.suit(tid)] = true
	if suits.size() != 1:
		return null
	var han := 6 if wc.is_menzen() else 5
	return YakuEntry.new(YakuId.CHINITSU, han, false, 0)
```

- [ ] **Step 10.4: 测试 + 注册 + Commit**

---

## Task 11: 役満批 1 — 国士 / 大三元 / 字一色 / 绿一色 / 清老头

5 个役満。

**Files:** `yakuman/{kokushi,daisangen,tsuuiisou,ryuuiisou,chinroutou}.gd` + 测试

- [x] **Step 11.1: `kokushi.gd`**

```gdscript
class_name KokushiYakuman

static func detect(wc: WinContext) -> YakuEntry:
	if wc.win_result.is_kokushi:
		if wc.win_result.is_thirteen_wait:
			return YakuEntry.new(YakuId.KOKUSHI_13, 0, true, 2)
		return YakuEntry.new(YakuId.KOKUSHI, 0, true, 1)
	return null
```

- [x] **Step 11.2: `daisangen.gd`** — 三元牌全部刻子

```gdscript
class_name Daisangen

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	var dragons_as_triplet: Dictionary = {TileId.HAKU: false, TileId.HATSU: false, TileId.CHUN: false}
	for m in wc.melds:
		if m.kind != Meld.Kind.CHI and dragons_as_triplet.has(m.tiles[0].id):
			dragons_as_triplet[m.tiles[0].id] = true
	if wc.win_result.standard_decompositions.size() > 0:
		var d = wc.win_result.standard_decompositions[0]
		for meld_ids in d.melds:
			if meld_ids[0] == meld_ids[1] and meld_ids[1] == meld_ids[2]:
				if dragons_as_triplet.has(meld_ids[0]):
					dragons_as_triplet[meld_ids[0]] = true
	if dragons_as_triplet[TileId.HAKU] and dragons_as_triplet[TileId.HATSU] and dragons_as_triplet[TileId.CHUN]:
		return YakuEntry.new(YakuId.DAISANGEN, 0, true, 1)
	return null
```

- [x] **Step 11.3: `tsuuiisou.gd`** — 全字牌

```gdscript
class_name Tsuuiisou

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	for tid in wc.all_tile_ids():
		if not TileId.is_honor(tid):
			return null
	return YakuEntry.new(YakuId.TSUUIISOU, 0, true, 1)
```

- [x] **Step 11.4: `ryuuiisou.gd`** — 全绿（2 3 4 6 8 索 + 发）

```gdscript
class_name Ryuuiisou

const GREEN_TILES: Dictionary = {
	TileId.S2: true, TileId.S3: true, TileId.S4: true, TileId.S6: true, TileId.S8: true,
	TileId.HATSU: true,
}

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	for tid in wc.all_tile_ids():
		if not GREEN_TILES.has(tid):
			return null
	return YakuEntry.new(YakuId.RYUUIISOU, 0, true, 1)
```

- [x] **Step 11.5: `chinroutou.gd`** — 全是数牌 1/9（无字牌，无中张）

```gdscript
class_name Chinroutou

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	for tid in wc.all_tile_ids():
		if TileId.is_honor(tid):
			return null  # 字牌应是字一色
		if not TileId.is_terminal(tid):
			return null
	return YakuEntry.new(YakuId.CHINROUTOU, 0, true, 1)
```

- [x] **Step 11.6: 测试 + 注册 + Commit**

每个役満配 2-3 测试用例（典型样例 + 反例）。

---

## Task 12: 役満批 2 — 四暗刻（含単騎）+ 四杠子 + 小四喜 + 大四喜

**Files:** `yakuman/{suuankou,suukantsu,shousuushi,daisuushi}.gd` + 测试

- [x] **Step 12.1: `suuankou.gd`**

```gdscript
class_name Suuankou

# 四暗刻：4 个暗刻 + 1 雀头。単騎待ち时为双倍役満
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	# 副露暗杠算暗刻；其他副露排除（明刻/明杠/吃 → 不是暗刻）
	for m in wc.melds:
		if m.kind != Meld.Kind.ANKAN:
			return null
	if wc.win_result.standard_decompositions.size() == 0:
		return null
	for d in wc.win_result.standard_decompositions:
		# 4 面子全是刻子（toitoi 前提）+ 全暗
		var triplet_count := 0
		var ron_triplet_id: int = -1
		for meld_ids in d.melds:
			if meld_ids[0] != meld_ids[1]:
				return null
			triplet_count += 1
			# 检查 winning 是否在这个刻子里且是 ron（→ 这个刻子是明刻不是暗刻）
			if meld_ids[0] == wc.winning_tile.id and not wc.game_context.is_tsumo:
				ron_triplet_id = meld_ids[0]
		# 暗杠副露不影响：副露暗杠 1 个，剩 3 暗刻 = 4 暗
		# 这里逻辑：副露 N 个暗杠 + (4 - N) 个暗牌刻 = 4 暗
		if triplet_count == 4 and ron_triplet_id == -1:
			# 全暗 — 检查是否単騎
			if wc.winning_tile.id == d.pair and wc.game_context.is_tsumo:
				return YakuEntry.new(YakuId.SUUANKOU_TANKI, 0, true, 2)
			# 自摸时和雀头无关，4 暗成立
			# 荣胡时 winning 不在刻子（ron_triplet_id == -1）但可能在 雀头 → 単騎ron 也是 suuankou tanki
			# 但 suuankou 严格要求所有刻子是暗刻 — 荣胡的刻子是明刻 → 上面已 return null
			# 所以这里到达只能是自摸或単騎
			if wc.winning_tile.id == d.pair:
				return YakuEntry.new(YakuId.SUUANKOU_TANKI, 0, true, 2)
			return YakuEntry.new(YakuId.SUUANKOU, 0, true, 1)
	return null
```

- [x] **Step 12.2: `suukantsu.gd`** — 4 杠

```gdscript
class_name Suukantsu

static func detect(wc: WinContext) -> YakuEntry:
	var kan_count := 0
	for m in wc.melds:
		if m.is_kan():
			kan_count += 1
	if kan_count == 4:
		return YakuEntry.new(YakuId.SUUKANTSU, 0, true, 1)
	return null
```

- [x] **Step 12.3: `shousuushi.gd`** — 4 风牌 3 刻 + 1 对

```gdscript
class_name Shousuushi

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	if wc.win_result.standard_decompositions.size() == 0:
		return null
	const WINDS: Array = [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N]
	for d in wc.win_result.standard_decompositions:
		var wind_triplet := 0
		var wind_pair := false
		for m in wc.melds:
			if m.kind != Meld.Kind.CHI and m.tiles[0].id in WINDS:
				wind_triplet += 1
		for meld_ids in d.melds:
			if meld_ids[0] == meld_ids[1] and meld_ids[1] == meld_ids[2] and meld_ids[0] in WINDS:
				wind_triplet += 1
		if d.pair in WINDS:
			wind_pair = true
		if wind_triplet == 3 and wind_pair:
			return YakuEntry.new(YakuId.SHOUSUUSHI, 0, true, 1)
	return null
```

- [x] **Step 12.4: `daisuushi.gd`** — 4 风牌 4 刻 (双倍役満)

```gdscript
class_name Daisuushi

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	if wc.win_result.standard_decompositions.size() == 0:
		return null
	const WINDS: Array = [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N]
	for d in wc.win_result.standard_decompositions:
		var wind_triplet := 0
		for m in wc.melds:
			if m.kind != Meld.Kind.CHI and m.tiles[0].id in WINDS:
				wind_triplet += 1
		for meld_ids in d.melds:
			if meld_ids[0] == meld_ids[1] and meld_ids[1] == meld_ids[2] and meld_ids[0] in WINDS:
				wind_triplet += 1
		if wind_triplet == 4:
			return YakuEntry.new(YakuId.DAISUUSHI, 0, true, 2)
	return null
```

- [x] **Step 12.5: 测试 + 注册 + Commit**

---

## Task 13: 役満批 3 — 九蓮宝燈 + 天和 + 地和

**Files:** `yakuman/{chuuren,tenhou,chiihou}.gd` + 测试

- [x] **Step 13.1: `chuuren.gd`** — 1112345678999 + 任意一张同色

```gdscript
class_name Chuuren

# 九蓮宝燈：门清 + 1 花色 + 起手符合 1112345678999 模式
# 纯正九蓮：和牌张让起手 13 张就是 1112345678999
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if not wc.is_menzen():
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	# 必须 1 花色（数牌）
	var first_suit := -1
	for tid in wc.all_tile_ids():
		if TileId.is_honor(tid):
			return null
		var s: int = TileId.suit(tid)
		if first_suit == -1:
			first_suit = s
		elif s != first_suit:
			return null
	# 14 张 id（数）的分布检查
	var counts := {}
	for tid in wc.all_tile_ids():
		var num: int = TileId.number(tid)
		counts[num] = counts.get(num, 0) + 1
	# 1112345678999 模式：1 出现 ≥ 3，9 出现 ≥ 3，2-8 各 ≥ 1
	if counts.get(1, 0) < 3 or counts.get(9, 0) < 3:
		return null
	for n in [2, 3, 4, 5, 6, 7, 8]:
		if counts.get(n, 0) < 1:
			return null
	# 纯正：去掉和牌张后 是 1112345678999（即 1 == 3, 9 == 3, 2-8 各 1）
	var counts_without_winning := counts.duplicate()
	var win_num: int = TileId.number(wc.winning_tile.id)
	counts_without_winning[win_num] -= 1
	var is_pure := counts_without_winning.get(1, 0) == 3 and counts_without_winning.get(9, 0) == 3
	for n in [2, 3, 4, 5, 6, 7, 8]:
		if counts_without_winning.get(n, 0) != 1:
			is_pure = false
			break
	if is_pure:
		return YakuEntry.new(YakuId.JUNSEI_CHUUREN, 0, true, 2)
	return YakuEntry.new(YakuId.CHUUREN, 0, true, 1)
```

- [x] **Step 13.2: `tenhou.gd`** — 庄家初配胡

```gdscript
class_name Tenhou

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.game_context.is_dealer_first_hand:
		return null
	return YakuEntry.new(YakuId.TENHOU, 0, true, 1)
```

- [x] **Step 13.3: `chiihou.gd`** — 闲家第一摸

```gdscript
class_name Chiihou

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.game_context.is_non_dealer_first_draw:
		return null
	if not wc.game_context.is_tsumo:
		return null
	return YakuEntry.new(YakuId.CHIIHOU, 0, true, 1)
```

- [x] **Step 13.4: 测试 + 注册 + Commit**

---

## Task 14: 互斥规则 & 集成测试

YakuList 收集到的役需要应用互斥规则：上位役覆盖下位役。

**Files:**
- Modify: `godot/core/rules_japanese/yaku/yaku_list.gd`（加 apply_exclusions 方法）
- Modify: `godot/core/rules_japanese/yaku/yaku_evaluator.gd`（在最终返回前调用）
- Create: `godot/tests/core/yaku/test_yaku_evaluator_integration.gd` + `.uid`

- [x] **Step 14.1: 写测试 — 互斥规则**

```gdscript
# test_yaku_list_exclusions.gd
extends GutTest

func test_ryanpeikou_excludes_iipeikou():
	var l := YakuList.new()
	l.add(YakuEntry.new(YakuId.IIPEIKOU, 1, false, 0))
	l.add(YakuEntry.new(YakuId.RYANPEIKOU, 3, false, 0))
	l.apply_exclusions()
	assert_false(l.id_list().has(YakuId.IIPEIKOU))
	assert_true(l.id_list().has(YakuId.RYANPEIKOU))

func test_chinitsu_excludes_honitsu():
	var l := YakuList.new()
	l.add(YakuEntry.new(YakuId.HONITSU, 3, false, 0))
	l.add(YakuEntry.new(YakuId.CHINITSU, 6, false, 0))
	l.apply_exclusions()
	assert_false(l.id_list().has(YakuId.HONITSU))

func test_junchan_excludes_honchanta():
	var l := YakuList.new()
	l.add(YakuEntry.new(YakuId.HONCHANTA, 2, false, 0))
	l.add(YakuEntry.new(YakuId.JUNCHAN, 3, false, 0))
	l.apply_exclusions()
	assert_false(l.id_list().has(YakuId.HONCHANTA))

func test_daisangen_excludes_yakuhai_dragons_and_shousangen():
	var l := YakuList.new()
	l.add(YakuEntry.new(YakuId.YAKUHAI_HAKU, 1, false, 0))
	l.add(YakuEntry.new(YakuId.YAKUHAI_HATSU, 1, false, 0))
	l.add(YakuEntry.new(YakuId.YAKUHAI_CHUN, 1, false, 0))
	l.add(YakuEntry.new(YakuId.SHOUSANGEN, 2, false, 0))
	l.add(YakuEntry.new(YakuId.DAISANGEN, 0, true, 1))
	l.apply_exclusions()
	assert_true(l.is_yakuman())
	# 役満时所有普通役被忽略（list 可能仍含但 total_han = 0）
	assert_eq(l.total_han(), 0)

func test_suuankou_excludes_toitoi_and_sanankou():
	var l := YakuList.new()
	l.add(YakuEntry.new(YakuId.TOITOI, 2, false, 0))
	l.add(YakuEntry.new(YakuId.SANANKOU, 2, false, 0))
	l.add(YakuEntry.new(YakuId.SUUANKOU, 0, true, 1))
	l.apply_exclusions()
	assert_true(l.is_yakuman())
```

- [x] **Step 14.2: 实现 apply_exclusions**

```gdscript
# 在 yaku_list.gd 加：

const EXCLUSIONS: Dictionary = {
	YakuId.RYANPEIKOU: [YakuId.IIPEIKOU],
	YakuId.CHINITSU: [YakuId.HONITSU],
	YakuId.JUNCHAN: [YakuId.HONCHANTA],
	# 役満时下面的 Yakuhai 互斥由 is_yakuman() / total_han() 自然处理（普通役不计入番数）
	# 但仍可显式移除以保持 entries 列表干净
	YakuId.DAISANGEN: [YakuId.YAKUHAI_HAKU, YakuId.YAKUHAI_HATSU, YakuId.YAKUHAI_CHUN, YakuId.SHOUSANGEN],
	YakuId.DAISUUSHI: [YakuId.YAKUHAI_BAKAZE, YakuId.YAKUHAI_JIKAZE, YakuId.SHOUSUUSHI],
	YakuId.SHOUSUUSHI: [],  # 不直接覆盖 yakuhai（雀头不算役牌）
	YakuId.SUUANKOU: [YakuId.TOITOI, YakuId.SANANKOU],
	YakuId.SUUANKOU_TANKI: [YakuId.TOITOI, YakuId.SANANKOU, YakuId.SUUANKOU],
	YakuId.KOKUSHI_13: [YakuId.KOKUSHI],
	YakuId.JUNSEI_CHUUREN: [YakuId.CHUUREN],
	YakuId.TSUUIISOU: [YakuId.HONITSU, YakuId.HONCHANTA, YakuId.YAKUHAI_HAKU, YakuId.YAKUHAI_HATSU, YakuId.YAKUHAI_CHUN, YakuId.YAKUHAI_BAKAZE, YakuId.YAKUHAI_JIKAZE, YakuId.SHOUSANGEN, YakuId.SHOUSUUSHI],
	YakuId.CHINROUTOU: [YakuId.HONCHANTA, YakuId.JUNCHAN, YakuId.TOITOI],
	YakuId.RYUUIISOU: [YakuId.HONITSU, YakuId.YAKUHAI_HATSU],
}

func apply_exclusions() -> void:
	# 收集所有 active id
	var active_ids: Dictionary = {}
	for e in entries:
		active_ids[e.yaku_id] = true
	# 找触发互斥的 id，把被排除的 id 从 entries 移除
	var to_remove: Dictionary = {}
	for trigger_id in EXCLUSIONS:
		if active_ids.has(trigger_id):
			for excluded_id in EXCLUSIONS[trigger_id]:
				to_remove[excluded_id] = true
	if to_remove.is_empty():
		return
	var new_entries: Array[YakuEntry] = []
	for e in entries:
		if not to_remove.has(e.yaku_id):
			new_entries.append(e)
	entries = new_entries
```

- [x] **Step 14.3: 修改 yaku_evaluator.gd 末尾调用**

```gdscript
static func evaluate(wc: WinContext) -> YakuList:
	var list := YakuList.new()
	if not wc.win_result.is_winning:
		return list
	# ... existing detector calls ...
	list.apply_exclusions()
	return list
```

- [x] **Step 14.4: 写集成测试 — 真实牌例多役叠加**

```gdscript
# test_yaku_evaluator_integration.gd
extends GutTest

func test_riichi_pinfu_tsumo_iipeikou():
	# 234m 234m 567p 678s 11s 待 5s/8s 摸 5s
	var hand := Hand.new()
	for tid in [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7,
		TileId.S1, TileId.S1,
	]:
		hand.add(Tile.new(tid))
	var winning := Tile.new(TileId.S5)
	var ctx := GameContext.new()
	ctx.bakaze = TileId.E
	ctx.jikaze = TileId.S_WIND
	ctx.is_riichi = true
	ctx.is_tsumo = true
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	var wc := WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)
	var list := YakuEvaluator.evaluate(wc)
	var ids := list.id_list()
	assert_true(ids.has(YakuId.RIICHI), "应有立直")
	assert_true(ids.has(YakuId.MENZEN_TSUMO), "应有自摸")
	assert_true(ids.has(YakuId.PINFU), "应有平和")
	assert_true(ids.has(YakuId.IIPEIKOU), "应有一杯口")
	assert_eq(list.total_han(), 4, "立直1+自摸1+平和1+一杯口1=4 番")

func test_chinitsu_replaces_honitsu():
	# 1m-9m + 11m 雀 (满色万)
	var hand := Hand.new()
	for tid in [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.W5, TileId.W6, TileId.W7,
		TileId.W8, TileId.W9,
		TileId.W2, TileId.W3,
	]:
		hand.add(Tile.new(tid))
	var winning := Tile.new(TileId.W4)  # 234m 完成第二顺
	# Hmm 这是 tatsu 14 张：W1×3 + W2 W3 W4 + W5 W6 W7 + W8 W9 + W2 W3 + W4 = 3+3+3+2+2+1=14 ✓
	# 4 面子 + 雀：111m + 234m + 567m + 89m+? + 23m? 不行
	# 改：111m 234m 567m 234m 99m 待 9 m
	hand = Hand.new()
	for tid in [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.W5, TileId.W6, TileId.W7,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.W9,
	]:
		hand.add(Tile.new(tid))
	winning = Tile.new(TileId.W9)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	var wc := WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)
	var list := YakuEvaluator.evaluate(wc)
	var ids := list.id_list()
	assert_true(ids.has(YakuId.CHINITSU))
	assert_false(ids.has(YakuId.HONITSU), "清一色应排除混一色")

func test_daisangen_yakuman_excludes_yakuhai():
	# 大三元：白白白 发发发 中中中 234m 11s
	var hand := Hand.new()
	for tid in [
		TileId.HAKU, TileId.HAKU, TileId.HAKU,
		TileId.HATSU, TileId.HATSU, TileId.HATSU,
		TileId.CHUN, TileId.CHUN, TileId.CHUN,
		TileId.W2, TileId.W3, TileId.W4,
		TileId.S1,
	]:
		hand.add(Tile.new(tid))
	var winning := Tile.new(TileId.S1)
	var ctx := GameContext.new()
	var wp := WinPattern.detect(hand, [] as Array[Meld], winning)
	var wc := WinContext.new(hand, [] as Array[Meld], winning, wp, ctx)
	var list := YakuEvaluator.evaluate(wc)
	assert_true(list.is_yakuman())
	assert_eq(list.yakuman_total_multiplier(), 1)
```

- [x] **Step 14.5: 跑全套 + Commit**

```bash
scripts/test_run_core.sh 2>&1 | tail -10
```

Expected: 累计 >= 200 测试，全过。

```bash
git add godot/core/rules_japanese/yaku/yaku_list.gd \
        godot/core/rules_japanese/yaku/yaku_evaluator.gd \
        godot/tests/core/yaku/test_yaku_list_exclusions.gd* \
        godot/tests/core/yaku/test_yaku_evaluator_integration.gd*
git commit -m "$(cat <<'EOF'
feat(yaku): 互斥规则 + 集成测试 — plan 0b 完成

- YakuList.apply_exclusions 处理上位役覆盖下位
- 主要互斥：二杯口⊃一杯口，清一色⊃混一色，纯全⊃混全，
  大三元⊃役牌×3+小三元，大四喜⊃场风+自风+小四喜，
  四暗刻⊃対々+三暗，国士13面⊃国士，纯正九蓮⊃九蓮等
- 集成测试覆盖立直+自摸+平和+一杯口、清一色、大三元等典型多役场景
- YakuEvaluator.evaluate 末尾自动 apply

里程碑 0b（30+ 役判定）完成：38 个基础役 + 4 个役満变体全部覆盖。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

## Task 15: 收尾 + 完成标记

- [x] **Step 15.1: 跑完整测试统计**

```bash
scripts/test_run_core.sh 2>&1 | tail -15
```

Expected: ≥ 200 tests passing。

- [x] **Step 15.2: 在 plan 文件追加完成记录**

修改 `docs/superpowers/plans/2026-05-01-yaku-detection.md` 末尾追加：

```markdown
---

## 完成记录

- 完成日期：（实际填）
- 累计测试数：（实际填）
- commit 数：~14 个 task commit + N 个 fix-up
- 38 个基础役 + 4 个役満变体 全部覆盖
- 互斥规则就位
- 后续：plan 0c（符算 + 点数公式）
```

- [x] **Step 15.3: Commit + push**

```bash
git add docs/superpowers/plans/2026-05-01-yaku-detection.md
git commit -m "docs: 标记 plan 0b 完成"
git push
```

---

## 整体验收

完成本计划后应满足：

1. `scripts/test_run_core.sh` 跑通 ≥ 200 个测试，全部 PASS
2. `godot/core/rules_japanese/yaku/` 下 38 个 .gd 役判定文件 + 7 个框架文件，全部 TAB 缩进
3. `YakuEvaluator.evaluate(WinContext)` 接受 plan 0a 的 WinPattern 结果，返回带正确番数 / 役満倍数 的 YakuList
4. 互斥规则正确（二杯口排除一杯口、清一色排除混一色、役満排除普通役等）
5. 全部 commit 已 push 到 `feat/mahjong-king-design`

完成后调用 `superpowers:writing-plans` 生成 plan 0c（符算 + 点数公式 + 点棒派发）。

---

## 完成记录

- **完成日期**：2026-05-01
- **累计测试数**：209 PASS / 0 FAIL（56 scripts，553 asserts）
- **本次新增 commit**（5 个，对应 Task 11-15）：
  1. `feat(yaku): 役満批 1 — 国士 / 大三元 / 字一色 / 緑一色 / 清老頭`
  2. `feat(yaku): 役満批 2 — 四暗刻 / 四槓子 / 小四喜 / 大四喜`
  3. `feat(yaku): 役満批 3 — 九蓮宝燈 / 天和 / 地和`
  4. `feat(yaku): 互斥规则 apply_exclusions + 集成测试`
  5. `docs: 标记 plan 0b 完成 — 209 tests, 5 yakuman commits`
- **新增文件**：
  - 役満判定：`godot/core/rules_japanese/yaku/yakuman/{kokushi, daisangen, suuankou, suukantsu, shousuushi, daisuushi, tsuuiisou, ryuuiisou, chinroutou, chuuren, tenhou, chiihou}.gd`（共 12 个文件）
  - 测试：`godot/tests/core/yaku/test_{kokushi_yakuman, daisangen, suuankou, suukantsu, shousuushi, daisuushi, tsuuiisou, ryuuiisou, chinroutou, chuuren, tenhou, chiihou, yaku_list_exclusions, yaku_evaluator_integration}.gd`（共 14 个文件）
- **修改文件**：
  - `godot/core/rules_japanese/yaku/yaku_list.gd`：加 EXCLUSIONS 字典 + apply_exclusions()
  - `godot/core/rules_japanese/yaku/yaku_evaluator.gd`：注册 12 个 yakuman detector + 末尾 apply_exclusions
- **覆盖**：13 种基础役満 + 4 个双倍变体（KOKUSHI_13 / SUUANKOU_TANKI / DAISUUSHI / JUNSEI_CHUUREN）+ 13 个互斥规则 trigger
- **后续**：plan 0c（符算 + 点数公式 + 点棒派发）
