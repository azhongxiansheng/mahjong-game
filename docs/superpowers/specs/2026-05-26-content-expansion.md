# 麻将王 — 内容扩展设计（超能力麻将深度挖掘）

- 日期：2026-05-26
- 状态：implementing

## 1. 新增角色（6 位，共计 12 角色）

基于咲-Saki-、天、哲也、凍牌的深度研究，新增 6 个角色。每个角色都有独特的被动能力、专属机制，不是简单的 "+N han"。

| ID | 名称 | 灵感原型 | 被动能力 | 机制描述 | HP | Gold | 解锁声望 |
|---|---|---|---|---|---|---|---|
| koromo | 天江衣 | Saki·衣 | 海底支配 | 牌墙最后 3 张对玩家可见；海底/河底胡牌 +3 han | 4 | 30 | 150 |
| nodoka | 原村和 | Saki·和 | デジタル | 免疫对手"流"系 debuff；听牌对手出现红色标记 | 5 | 50 | 80 |
| toki | 園城寺怜 | Saki·怜 | 一巡先見 | 每局 1 次：消耗 1000 点，预览所有人下 1 巡摸牌 | 4 | 40 | 250 |
| kuro | 松実玄 | Saki·玄 | ドラの愛 | 起手保证 ≥2 张 dora；宝牌摸到概率 +30% | 5 | 20 | 120 |
| momoko | 東横桃子 | Saki·桃子 | ステルス | 玩家弃牌 3 巡内对手不可读（安全牌判定失效）；立直宣告延迟 2 巡显示 | 4 | 30 | 180 |
| tetsuya | 哲也 | 哲也 | 玄人技 | 每章 1 次"燕返し"：重新抽取起手 13 张 | 3 | 100 | 300 |

## 2. 新增角色能力（8 个，共计 26 能力）

超越简单数值加成的机制设计：

| ID | 名称 | 灵感 | 触发 | 效果 | 稀有 |
|---|---|---|---|---|---|
| hisa_bad_wait_v1 | 悪待ちの達人 | Saki·久 | WIN_DECLARED_PRE | 非标准听（单骑/双碰/嵌张）胡牌 +2 han | EPIC |
| mako_memory_v1 | 記憶打法 | Saki·まこ | TILE_DRAWN（巡≥6） | 巡数 ≥6 后每次摸牌预览墙顶 3 张 | EPIC |
| koromo_haitei_v1 | 海底支配 | Saki·衣 | HAITEI/HOUTEI | 海底/河底胡牌 +3 han + 满贯保底 | LEGENDARY |
| toki_foresight_v1 | 未来視 | Saki·怜 | GAME_BEGIN | 每局首巡预览所有 4 人首摸牌，消耗 1000 点 | LEGENDARY |
| kuro_dora_love_v1 | ドラの愛 | Saki·玄 | GAME_BEGIN | 起手 ≥2 dora 保证 + 每次翻宝牌时额外 +1 dora | LEGENDARY |
| momoko_stealth_v1 | ステルスモード | Saki·桃子 | TILE_DISCARDED | 弃牌后 3 巡内对手 AI 无法使用该弃牌做安全牌判定 | EPIC |
| tsubame_gaeshi_v1 | 燕返し | 哲也 | GAME_BEGIN | 消耗品化：重抽起手牌（选较好的 13 张） | LEGENDARY |
| streak_escalation_v1 | 連勝加速 | Saki·照的变体 | WIN_DECLARED | 节点内连续胡牌 +1/+2/+3 han 累加（非连续重置） | EPIC |

## 3. 新增遗物（8 个，共计 12 遗物）

遗物 = 被动常驻效果（整个 Run 有效）。设计原则：每个遗物改变一个核心策略维度。

| ID | 名称 | 效果 | 稀有 |
|---|---|---|---|
| relic_red_string_v1 | 赤い糸 | 所有 5 万/5 筒/5 索 自动变赤宝牌（+1 dora/张） | EPIC |
| relic_dragon_seal_v1 | 龍印 | 三元牌（白/發/中）刻子出现时 +1 han | UNCOMMON |
| relic_wind_charm_v1 | 風鈴 | 自风牌役 +1 han | UNCOMMON |
| relic_speed_demon_v1 | 速攻の鬼 | 8 巡内胡牌 +1 han（鼓励速攻） | RARE |
| relic_patience_stone_v1 | 忍耐石 | 流局时若听牌 +2000 点（奖励防守） | UNCOMMON |
| relic_pity_breaker_v1 | 天運の欠片 | 抽卡保底阈值从 8 降到 5 | RARE |
| relic_han_crystal_v1 | 番結晶 | 立直胡牌 +1 han | UNCOMMON |
| relic_comeback_crown_v1 | 逆転の冠 | 点数最低时胡牌 +2 han | EPIC |

## 4. 新增消耗品（6 个，共计 12 消耗品）

| ID | 名称 | 效果 | 稀有 |
|---|---|---|---|
| consumable_tsubame_v1 | 燕返し（道具） | 重抽起手 13 张（本局 1 次） | LEGENDARY |
| consumable_wall_collapse_v1 | 牌山崩壊 | 缩短牌墙 14 张（加速流局） | RARE |
| consumable_dora_flip_v1 | 即時翻宝 | 立即翻开 1 张新 dora 指示牌 | UNCOMMON |
| consumable_seat_swap_v1 | 换位思考 | 与得分最高 AI 交换点数 | EPIC |
| consumable_furiten_bomb_v1 | 振听炸弹 | 令所有对手进入 1 巡暂时振听 | RARE |
| consumable_point_shield_v1 | 护分盾 | 本局被 ron 损失减半 | UNCOMMON |

## 5. 新增牌技能（12 个，覆盖 §8.1-8.9 薄弱区域）

重点补强 §8.2（加速系）、§8.7（振听操控）、§8.4（反向得分）。

| ID | 牌 | 分类 | 效果 | 稀有 |
|---|---|---|---|---|
| w7_flow_ride_v1 | W7 | §8.2 加速 | 连续 3 巡不鸣牌时下次摸牌从墙顶 3 张选 1 | EPIC |
| t5_double_draw_v1 | T5 | §8.2 加速 | 持此牌弃牌后下巡摸 2 选 1 | UNCOMMON |
| s7_counter_ron_v1 | S7 | §8.4 反向 | 被 ron 时反扣对手 20% 得分 | EPIC |
| w3_furiten_spread_v1 | W3 | §8.7 振听 | 弃此牌后所有对手 1 巡暂时振听 | EPIC |
| t7_ippatsu_extend_v1 | T7 | §8.6 立直 | 一发窗口延长到 2 巡 | UNCOMMON |
| s1_yakuhai_boost_v1 | S1 | §8.1 增番 | 役牌（场风/自风/三元牌）+1 han | UNCOMMON |
| w8_kan_bonus_v1 | W8 | §8.1 增番 | 杠后胡牌 +2 han（嶺上強化） | EPIC |
| t3_defense_aura_v1 | T3 | §8.3 防守 | 持此牌时对手 ron 役 -2 han（降至 0 = 取消） | EPIC |
| s5_red_dora_magnet_v1 | S5 | §8.8 Dora | 赤宝牌 5 索额外 +2 dora（每张 3 dora 而非 1） | RARE |
| e_wind_domain_v1 | E | §8.1 增番 | 场风=自风时 +3 han（东一局庄家极强） | LEGENDARY |
| n_silent_threat_v1 | N | §8.7 振听 | 持此牌时对手无法检测你的听牌状态 | EPIC |
| chun_blood_pact_v1 | CHUN | §8.4 反向 | 胡牌时额外从所有对手各抽 1000 点 | LEGENDARY |

## 6. 新增 Boss 变体（每章 2 选 1 随机，共 3 个新 Boss）

| ID | 章 | 名称 | 效果 |
|---|---|---|---|
| boss1_stealth_wall_v1 | 1 | 隐身壁 | Boss 的弃牌对玩家不可见（无法读牌） |
| boss2_dora_thief_v1 | 2 | 宝牌猎手 | 翻宝牌时 Boss 自动获得 +2 dora，玩家 -1 dora |
| boss3_yakuman_pressure_v1 | 3 | 役満圧力 | Boss 每 2 局自动获得 1 个役満雀头（增加役満概率） |

## 7. 新增卡包主题（3 个，共计 6 种卡包）

| 名称 | 内容偏向 | 稀有保底 |
|---|---|---|
| DORA_PACK | Dora 系技能牌 + 赤宝遗物 | 必出 1 张 EPIC+ dora 牌 |
| DEFENSE_PACK | 防守/振听系技能 + 护分消耗品 | 必出 1 张 EPIC+ 防守牌 |
| WILD_PACK | 全品类随机 + 高概率角色能力 | 必出 1 张角色能力 |

## 实现优先级

1. **P0 — 新角色 + 被动 hook**（最大游戏性影响）
2. **P0 — 新遗物**（改变策略维度）
3. **P1 — 新消耗品**（战斗中的选择丰富度）
4. **P1 — 新能力**（深度技能树）
5. **P2 — 新牌技能**（补全 §8 分类）
6. **P2 — Boss 变体 + 卡包**
