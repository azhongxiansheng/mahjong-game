# 气势系统（Voice Momentum）设计规范

- 日期：2026-05-25
- 状态：v1 foundation

## 1. 概述

玩家在对局中说话或输入文字 → AI 分析文本属性 → 生成"气势值" → 气势影响技能效果倍率。

## 2. 属性模型

5 种属性：
| 属性 | 对应牌/技能类型 | 台词风格 |
|------|---------------|---------|
| 霸气 (DOMINATION) | 万子、增番系 | 自信、霸道的宣言 |
| 冷静 (CALM) | 筒子、防守系 | 分析、算计的台词 |
| 狡猾 (CUNNING) | 索子、振听/阻胡系 | 阴险、挑衅的台词 |
| 热血 (PASSION) | 立直、一发 | 中二、燃烧的台词 |
| 神秘 (MYSTIC) | 字牌、役满 | 深沉、超自然的台词 |

## 3. 气势值计算

momentum = base_attribute_score * character_affinity * context_bonus

- base_attribute_score: AI 分析输入文本的属性得分 (0.0 - 1.0)
- character_affinity: 角色对该属性的亲和度 (0.5 - 2.0)
- context_bonus: 场况加成 (被追分时热血+50%、领先时冷静+50% 等)

## 4. 气势影响

- momentum 0.0-0.3: 无效果
- momentum 0.3-0.6: 技能效果 +25%
- momentum 0.6-0.8: 技能效果 +50%
- momentum 0.8-1.0: 技能效果 +100%, 视觉特效加强

气势影响 SkillCtx.han_deltas 的乘数,而非摸牌顺序(保证日麻公平性)。

## 5. 输入方式

- 语音输入: Whisper STT → 文本 (v2)
- 文字输入: 直接打字 (v1)
- 预设台词: 按钮快速发送 (v1)

## 6. AI 分析

v1: 关键词匹配 + 简单情感分析
v2: LLM 分析 (Claude/GPT)
