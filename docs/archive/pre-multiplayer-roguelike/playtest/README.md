# 玩家测试反馈

落地 [`docs/superpowers/plans/2026-05-03-balance-iteration.md`](../superpowers/plans/2026-05-03-balance-iteration.md) **D3 玩家测试反馈漏斗**。

## 两层节奏

| 层 | 谁 | 节奏 | 每次会话 | 输出 |
|---|---|---|---|---|
| **Alpha** | 开发组内 | 每 1-2 周 | 30 分钟内、3-5 个 Run | `docs/playtest/<日期>-alpha-<N>.md` |
| **Beta** | 外部 ≤ 5 人 playtester | M7 中段后开放，每周 | 玩家自己安排 | `docs/playtest/<日期>-beta-batch-<N>.md` |

每次反馈用 [`_template.md`](_template.md) 起。

## 数据闭环

每次反馈 → 提取一条具体观察 → 假设 → 跑 simulation 验证（D4 工具） → 决策 PR（改 `BalanceConstants` 或 hook 行为） → 下一次 alpha 复跑确认体感对齐（D6 三步法）。

> Beta 反馈渠道（GitHub Discussion / Google Form / Discord）等用户拍板（plan-7 开放问题 3）。

## 文件命名

```
docs/playtest/
├── README.md                      # 本文件
├── _template.md                   # 反馈模板（每次会话复制）
├── 2026-05-15-alpha-1.md
├── 2026-05-29-alpha-2.md
├── 2026-06-12-beta-batch-1.md
└── ...
```

日期是会话进行的日期；`<N>` 是 alpha 会话累计编号 / beta 是 batch 编号。

## 不要做

- ❌ 不要把反馈直接转成代码改动 —— 每条改动必须经"假设 → 验证 → 决策"三步（plan-7 D6）
- ❌ 不要在反馈记录里写代码片段或具体数值调整 —— 那是后续 PR 的事
- ❌ 不要回填旧会话 —— 模板要求"会话当时记录"以保留主观体感的真实性
