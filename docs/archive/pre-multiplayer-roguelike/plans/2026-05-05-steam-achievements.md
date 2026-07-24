# Steam 成就清单 brainstorm（2026-05-05）

> **类型**：Steam 平台特性 brainstorm doc。补充 [`steam-readiness`](2026-05-05-steam-readiness.md)（PR #120）的 D4 项 — 成就列表设计。**纯设计，不动代码**。
>
> 上游链接：[`godotsteam-spike`](2026-05-05-godotsteam-spike.md)（PR #130）— 集成 API 用 `Steam.setAchievement(name)` + `Steam.storeStats()`

## TL;DR

- **目标 30-40 个成就** — Steam 平均范围（Slay the Spire 47 / Hades 49 / Balatro 33）
- **5 大类**：进度（章节 / Boss）/ 玩法深度（yaku / 役满）/ 起始包 / 速通 / 彩蛋
- 每个成就附 `id` / `display_name` / `description` / `钩子位置`（哪个 BattleEvent / 哪条代码触发）
- v1.0 上线只放 base 30 个；预留 v1.1 patch 加 5-10 个（保 long-tail engagement）

## 一、设计原则

按 GDC / Steam dev 经验：

1. **简单成就占多数**（玩 1 小时拿 ~10 个） — 让玩家有持续 dopamine hit；典型完成率 70-90%
2. **中等成就分布合理**（10-30% 完成率） — "击败 Boss 1" / "通关章节 1"
3. **稀有成就 5-8 个**（< 5% 完成率） — 速通 / 高难 / 彩蛋；社区炫耀点
4. **避免"运气向"成就** — 玩家觉得"撞到了"反而不爽；本游戏 sim seed 决定性反而适合（同 seed 重 run 可复现）
5. **避免成就阻断玩法** — 不要"必须不立直通关"这种逼迫玩法变形的，除非有专门高难模式
6. **隐藏成就少用** — 仅彩蛋类用 hidden=true；明面成就让玩家有奔头
7. **图标统一风格** — 32×32 / 64×64 PNG；可后期外包美术统一做

## 二、成就清单（v1.0：30 个）

### A 进度类（10 个） — 占 30-50% 完成率主体

| ID | display_name | description | 钩子 |
|---|---|---|---|
| `first_run_clear` | 麻将王初战 | 首次通关任意章节 1 | `RunState` 章节通关事件 |
| `chapter_1_done` | 风的庇护 | 通关章节 1 | 同上 |
| `chapter_2_done` | 山的考验 | 通关章节 2 | 同上 |
| `chapter_3_done` | 海的尽头 | 通关章节 3（含 Boss）— 完整通关 | 同上 |
| `boss_1_kill` | 击败 Boss 1 | 击败 boss1（玄武 / 守护神）| `BattleEvent.BOSS_DEFEATED` |
| `boss_2_kill` | 击败 Boss 2 | 击败 boss2（朱雀 / 暴雨者）| 同上 |
| `boss_3_kill` | 击败 Boss 3 | 击败 boss3 关门将（kanmon）| 同上 |
| `first_riichi` | 初次立直 | 首次玩家声明立直 | `BattleEvent.RIICHI_DECLARED` 玩家 seat=0 |
| `first_tsumo` | 初次自摸 | 首次玩家自摸和牌 | `WIN_DECLARED_PRE` 玩家 + tsumo |
| `first_ron` | 初次荣胡 | 首次玩家荣胡 | `WIN_DECLARED_PRE` 玩家 + ron |

### B 玩法深度（8 个） — yaku / 役满收集

| ID | display_name | description | 钩子 |
|---|---|---|---|
| `pinfu_master` | 平和宗师 | 累计完成 50 次平和 | `WIN_DECLARED_PRE` + yaku 含 pinfu |
| `tanyao_master` | 断幺九通 | 累计完成 50 次断幺九 | 同上 |
| `riichi_50` | 立直百战 | 累计 50 次立直胡牌 | RIICHI + 后续 win |
| `dora_count_5` | 五重宝路 | 单次胡牌 dora ≥ 5 | yaku.dora_count ≥ 5 |
| `mangan_first` | 满贯首达 | 首次满贯（5 番）| total_han ≥ 5 |
| `haneman_first` | 跳满首达 | 首次跳满（6 番）| total_han ≥ 6 |
| `baiman_first` | 倍满首达 | 首次倍满（8 番）| total_han ≥ 8 |
| `yakuman_first` | **役满登极** | 首次役满（13 番 / 国士 / 大三元 etc）| `is_yakuman == true` |

### C 起始包通关（6 个）

| ID | display_name | description | 钩子 |
|---|---|---|---|
| `clear_with_control` | 控场之道 | 用控场起始包通关 | RunState clear + starter_id == "control" |
| `clear_with_aggro` | 火力压制 | 用火力起始包通关 | starter_id == "aggro" |
| `clear_with_fast` | 闪电速胡 | 用速胡起始包通关 | starter_id == "fast" |
| `clear_all_starters` | 三套通行 | 三套起始包都通关过 | meta_progress 检查 |
| `no_riichi_clear` | 不立直挑战 | 通关一次 Run 全程不立直 | run-level RIICHI 计数 == 0 |
| `low_hp_clear` | 一血通关 | HP=1 通关章节 3 Boss | 章节通关 + final_hp == 1 |

### D 速通 / 高难（3 个）

| ID | display_name | description | 钩子 |
|---|---|---|---|
| `speed_clear` | 风一般的男人 | 单 Run 通关用时 < 60 分钟 | wall-clock timer + clear |
| `flawless_chapter_1` | 章节 1 满血 | 章节 1 完成时 HP 仍满（4/4）| chapter_done + hp == max |
| `eight_consecutive_wins` | 八连星 | 单 Run 中连续 8 局胡牌（不流局）| 玩家连胜计数 |

### E 彩蛋 / 隐藏（3 个）

| ID | display_name | description | 钩子 | hidden |
|---|---|---|---|---|
| `kokushi_musou` | **国士无双** | 完成国士无双 13 面待 | yaku 含 kokushi_13 | false（明面）|
| `daisangen` | 大三元 | 完成大三元 | yaku 含 daisangen | false |
| `secret_chuuren` | 九莲宝灯 | 完成九莲宝灯（含纯正）| yaku 含 chuuren_poutou | true（隐藏）|

**v1.0 总数：30 个**（A 10 + B 8 + C 6 + D 3 + E 3）。

## 三、v1.1 patch 候选（5-10 个）

延后到 v1.0 上线后第 1 个 patch（保社区 long-tail engagement）：

- `boss_3_no_damage` — 章 3 Boss 战未失 HP 通关
- `all_yaku_collected` — 收集全部 38 yaku（hard mode 完成度）
- `30_run_clears` — 累计 30 次完整 Run 通关
- `speed_clear_30min` — 单 Run < 30 分钟通关（极速）
- `replay_mode_first` — 首次进入 Replay mode（M11 联机功能）
- `pvp_first_win` — Phase 2 PvP 首胜（同事 M12+ 联机功能）
- `lobby_with_friends` — 与好友建房（Steam Lobby）
- `cosmetic_collection` — 收集 5+ 牌面 cosmetic（DLC 钩子）

## 四、与 BattleEvent 钩子对接

成就 emit 不应散落各 hook，集中到 `meta/achievements.gd` autoload：

```gdscript
# 设计草稿（不实装）
extends Node

const STEAM_ACHIEVEMENTS = {
    "first_run_clear": "first_run_clear",  # internal_id → steam_api_name
    "chapter_1_done": "chapter_1_done",
    # ...
}

func _ready() -> void:
    SkillScheduler.battle_event.connect(_on_battle_event)
    RunState.run_completed.connect(_on_run_completed)
    # ...

func _on_battle_event(event: BattleEvent) -> void:
    match event.kind:
        BattleEventKind.RIICHI_DECLARED:
            if event.seat == 0:
                _emit("first_riichi")
        BattleEventKind.WIN_DECLARED_PRE:
            if event.seat == 0:
                if event.is_tsumo: _emit("first_tsumo")
                else: _emit("first_ron")
                _check_yaku_achievements(event.yaku_list)
                _check_han_achievements(event.total_han)

func _emit(internal_id: String) -> void:
    if SteamBridge.is_running():
        SteamBridge.set_achievement(STEAM_ACHIEVEMENTS[internal_id])
        SteamBridge.store_stats()
    # 本地 stub achievement system 也记一份（dev mode）
```

**好处**：成就逻辑集中可测；不污染 hook；future Steam Workshop 模式可同样用。

## 五、Stats（持久化数值统计）

Steam 不只成就，还可记 Stats（数字累计，玩家 profile 显示）：

| stat_id | type | description |
|---|---|---|
| `total_runs` | int | 总 Run 数 |
| `total_clears` | int | 总通关数 |
| `total_wins` | int | 总胡牌数 |
| `total_riichi_calls` | int | 总立直次数 |
| `total_yakuman` | int | 总役满次数 |
| `fastest_clear_seconds` | int | 最快通关用时 |
| `highest_score_single_hand` | int | 单局最高分（含奖励）|

Stats 在玩家 Steam profile 自动展示；也是 future leaderboard 数据源。

## 六、本地化（i18n）

成就 display_name + description 双语（中 / 英）：

```
# 中文
first_run_clear: "麻将王初战"
description: "首次通关任意章节"

# 英文
first_run_clear: "Mahjong King Debut"
description: "Complete any chapter for the first time"
```

Steamworks 后台支持每个成就独立填多语言；不需要游戏内 i18n 系统。

**v1.0 双语必须**（Steam 国际市场需求）；后续可考虑日语 / 韩语 / 西语。

## 七、上线前 D-list

| 项 | 状态 | 责任 |
|---|---|---|
| D1 成就 30 个清单 | ✅（本文档草案） | 工程 |
| D2 Steamworks 后台定义成就 + 双语描述 | ⬜（用户操作）| 用户 |
| D3 成就图标设计（30 个 ×64×64 PNG） | ⬜（美术）| 用户 / 外包 |
| D4 `meta/achievements.gd` autoload 实装 | ⬜（4-6 hr）| 工程 |
| D5 `tests/meta/test_achievements.gd` GUT 单测 | ⬜（2 hr）| 工程 |
| D6 BattleEvent 钩子接入 | ⬜（4 hr）| 工程 |
| D7 双语 manual review（中文母语 + 英文母语都看一遍）| ⬜ | 用户 |

## 八、风险与缓解

| 风险 | 缓解 |
|---|---|
| 成就 emit 在错误事件触发（如 AI 自摸误判玩家成就）| autoload `_on_battle_event` 严格 gate `seat == 0`（玩家）|
| Steam Cloud 失败 → 成就丢 | `setAchievement` 先记本地 fallback；下次 Steam 在线时同步 |
| 成就名 collision（重命名时）| Steamworks 后台 `internal_id` 不可改；只能 deprecate；命名时谨慎 |
| 30 个成就玩家 1 小时全拿到 | 调难度分布；测 5 个真玩家看 1 小时拿几个 |
| **国士无双 / 九莲宝灯成就完成率太低（< 0.1%）→ Steam 评级影响** | Steam 不因稀有成就降游戏评级；OK 保留 |

## 九、关键开放问题

1. **成就图标**：用户自制 / 外包 / Generative AI（如 SDXL）？60×60×30 张约 $300-1500 外包
2. **成就完成率分布预设**：30 个全部"易得"还是混合？建议混合（25 易得 / 5 难）
3. **隐藏成就比例**：3 个？多了会失去"奔头" pre-engagement
4. **stats 是否 v1.0 必须**：可推迟到 v1.1（不阻塞上线）
5. **国家化**：v1.0 中英双语；日 / 韩 / 西其他语言后续

## 十、不在本 brainstorm 范围

- 成就图标实际美术制作（独立流程）
- Steam Cards / 表情 / 头像（不用 API 实装；纯 Valve 后台配置）
- Steam Workshop 成就（玩家自定义起始包 mod）— Phase 3
- Steam P2P 联机相关成就（Phase 2 联机骨架完成后另议）
