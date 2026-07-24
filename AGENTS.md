# AGENTS.md

> 本文件是 mahjong-game 的 **Agent 开发原则 / 工作流唯一权威源**。
> `CLAUDE.md` 只描述项目技术事实，并链接本文件，不再复制工作流规则。
>
> **工作流规则只改本文件；技术事实才改 `CLAUDE.md`。**
>
> 原则对齐 `~/project/lov-video/AGENTS.md` 的结构与纪律，并按本仓库现状适配
> （Godot 4.5/4.6 客户端 + GUT 9.x + 肉鸽 Run + 日麻引擎 + 根目录 Go 健康检查桩）。

## 优先级

当本文件与 `CLAUDE.md`、用户即时指令、系统默认行为冲突时：

1. **用户即时指令** —— 最高
2. **本文件** —— 高
3. 默认系统行为 —— 最低

本文件内部条款冲突时，以**更具体、约束更强**者为准。
发布、安全、版本兼容、资产文件名契约等硬约束不因本文件之外的便利说法而放松。

---

## 沟通语言

- 与用户沟通默认使用**中文**；用户明确指定其他语言时再切换。
- 代码注释、日志、commit message 优先中文（既有英文文件可保持英文）。
- **PR / Issue 的标题、正文、评论、检查说明默认中文**；除非用户明确要求其他语言。

---

## 编码四条硬纪律

### 1. 先思考，再编码

- 实现前**显式写出关键假设**；不确定的事情不得假装确定。
- 需求有多种合理解释时，**必须先列出分歧与取舍**，不能静默选择其一。
- 若存在更简单、范围更小的实现路径，先说明并优先采用。
- 关键信息不足或存在真实歧义时，**暂停并向用户确认**，不要硬猜。

### 2. 简单优先

- 只写解决当前问题所需的**最小代码或最小改动**。
- 不做未被请求的功能、抽象、配置化、「顺便支持以后」。
- 不为单次需求引入一次性之外的通用层；若 200 行能压到 50 行且不损失清晰度，优先简化。
- **不为不可能发生的场景增加防御性错误处理**。

### 3. 外科手术式修改

- 只修改完成当前任务**所必需的**文件、代码、注释与格式。
- 不顺手「优化」邻近代码；保持既有风格与结构。
- 只清理**由本次改动直接造成的**废弃 import、变量、函数、注释；已有无关死代码只报告，不擅自删除。
- 每一处修改都必须能直接追溯到当前需求；不能追溯的，默认不改。

### 4. 目标驱动执行

- 把任务改写为**可验证目标**再实施，避免「做到差不多」为止。
- 多步骤任务先给出简短计划：步骤、验证方式、成功标准。
- 能用测试验证的改动，优先先写失败用例或复现步骤，再实现通过。
- 无法合理自动化测试的微小任务也必须给出最小可执行的验证方式，**不能跳过验证**。

---

## 实现前强制闸门

### 闸门 A：意外文件处理

发现「我没有主动创建/修改」的异常文件或变更时：

| 类型 | 处理 |
|------|------|
| **影响运行/构建/测试的代码、脚本、配置、锁文件、业务资源** | **立刻暂停** → 向用户报告发现了什么 → 询问（忽略 / 删除 / 纳入 / 其他）→ **获明确指令后再继续**。绝不擅自删除或纳入。 |
| **纯文档、agent 说明、本地元数据**（如 `.DS_Store`、会话缓存、无关 `.uid` 孤儿若不确定则仍报告） | 可忽略并继续；**不擅自删除或纳入提交**。 |

典型需报告的例子：未知临时文件、非预期 diff、Godot 孤儿 `.uid`、根目录又冒出来的状态报告 markdown。

### 闸门 B：计划输出

进入实现前，先给出**可执行计划**，至少包含：

- 关键假设 / 歧义
- 改动范围（哪些文件）
- 验证方式（怎么证明改对了）
- 风险点
- 成功标准

存在多种解释或更简单方案时必须在计划中先说明取舍，不能直接静默实现。

### 闸门 C：UI / 交互确认（分档）

涉及 Godot 场景布局、UI 控件、动画方向、操作栏、牌桌/Run 壳视觉时，实现前按复杂度取得用户确认：

| 档位 | 判定 | 确认物 |
|------|------|--------|
| **简单** | 局部调整、不改整体布局、变化点 ≤5 | **ASCII 草图** + 用户确认 |
| **复杂 UI** | 新面板/弹层、布局重构、多方案 | ASCII + 方案取舍说明；有条件时用 `tools/capture_screens.gd` 做前后截图对比 |
| **复杂流程** | 跨步骤 ≥3、多模块联动、状态机/异常分支 | 计划中提供 **Mermaid** 流程或状态图 |

同时涉及多种屏幕形态（横竖屏等）时分别给草图。

### 闸门 D：需求与实现一致性

- 实现与既有约束/设计冲突时，优先暂停并请用户确认，不自行偏离。
- 默认最小必要改动，不为单次需求引入抽象层、配置项或前瞻性扩展。

---

## TDD 与验证规范（强制）

### TDD 顺序

默认对**功能开发 / 缺陷修复**采用 TDD（Red → Green → Refactor），除非用户明确允许跳过：

1. **Red**：先写测试并运行到失败；
2. **Green**：再写最小实现使测试通过；
3. **Refactor**：最后重构并保持测试持续通过。

**禁止先写业务实现再补测试**；发现偏离立即停止回到 Red。

文档更新、纯发布执行、纯配置搬运、无法合理自动化的微小改动可采用更轻量验证，但**必须先说明理由**并执行最小可验证检查。

### 真实测试约束

- 测试核心行为基于**真实逻辑与真实资产加载路径**（GUT + 仓库内资源）。
- mock 仅用于隔离不可控外部副作用（第三方网络、不存在的 WebSocket 服等），**不得用 mock 顶替被测对象的核心规则逻辑**（胡牌、符算、TurnEngine、鸣牌等）。
- 任何「已完成 / 已修复 / 测试通过」的结论必须附**可执行验证方式与结果**。

### 本仓库验证门禁

```bash
# 1) class_name / 纹理缓存（改 class 或资产后必跑）
godot --headless --path godot --import

# 2) GUT 全量（应 0 fail / 0 parse error；当前约 250+ 脚本 / 1800+ 用例）
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests -ginclude_subdirs -gexit

# 3) 局部（开发中）
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests/<module> -gselect=<test_name> -gexit

# 4) UI 截图（非 headless；输出 /tmp/shot_*.png）
godot --path godot -s tools/capture_screens.gd
```

| 改动类型 | 验证 |
|----------|------|
| `core/` / `battle/` / 规则 / AI | GUT 相关目录 + 全量回归优先 |
| `ui/` 布局与交互 | GUT UI 测 + 手测主路径；复杂改动 `capture_screens` |
| 资产 PNG / 新 `class_name` | `--import` + 相关 GUT + 启动主场景目视 |
| 纯文档 / agent 说明 | `git diff --check` + 人工通读 |
| 网络 / WebSocket 客户端 | **必须声明「未端到端验证」**（本仓无对战服） |
| Go 桩 `main.go` | 如修改则先写 `_test.go`；**默认不扩张职责** |

生产代码新增测试一律放 `godot/tests/<module>/test_*.gd`（GUT）。
`godot/scripts/test_*.gd` / 部分 `scenes/test_*.tscn` 是遗留 scene 手测，不新增生产逻辑到该路径。
`godot/tests/scenes/**/*.tscn` 供编辑器 F6 手测。

### 声称完成的最低标准

- 提交/PR 必须包含：与本次改动相关的测试或验证步骤 + **命令与结果摘要**。
- UI 改动尽量附截图路径或前后对比说明。

---

## 第三方接口对接顺序（强制）

对接 Godot 引擎 API、外部 HTTP/WS、资产生成 gateway、SDK、OS API 前：

1. **先查阅并记录官方资料 / 仓库内已有正确用法**，不得凭印象开发。训练数据可能与 Godot 4.5/4.6 不一致，**怀疑印象，验证文档**。
2. 写业务实现前用**最小请求/最小场景测通**，确认参数、返回、错误与限制。
3. 测通后**先按真实行为写/更新测试**，再进入业务实现。
4. 无法在本地实际调用时，先说明原因、记录替代验证方式，**经用户确认后再继续**。

---

## Codex App + Grok CLI 单 Issue 闭环（强制）

> 适用于用户明确选择由 Grok CLI 开发的任务。每个 GitHub Issue 使用一个 Codex App 任务；
> 同一个 Codex 任务负责需求对齐、驱动 Grok、独立 Review、验证、返工、Git 交付、合并和后续 Issue 分析。
> 不额外创建 Review 任务，不引入 `agentctl` 或调度器；右侧终端可直接运行 Grok，tmux 仅在用户明确需要断线恢复时使用。

### 适用边界与状态

- 一个 Issue 对应一个 Codex App 任务、一个任务分支和一个 worktree；同一 worktree 同时只能有一个 Grok 写入。
- 默认只运行 **1 个 Grok CLI 会话串行开发**；禁止 Grok 再派生子任务修改同一需求。
- 高歧义需求、需要产品取舍、不可逆生产操作、权限或凭证不明确时，不得先让 Grok 猜测实现。
- 需要用户选择时进入 `BLOCKED_USER_DECISION`，明确列出选项、影响和推荐项并等待答复；不得跳过。若宿主提供 goal/status 工具，按该工具自身规则设置阻塞状态，不得伪造状态。
- 推荐状态流：

```text
BLOCKED_USER_DECISION（如需）
  → GROK_PLAN_INTERACTIVE
  → USER_PLAN_CONFIRMED
  → GROK_IMPLEMENTING
  → CODEX_REVIEW
  → REWORK_REQUIRED（如有 P0/P1/P2）
  → VALIDATING
  → READY_FOR_PR
  → MERGED
  → NEXT_ISSUE_ANALYSIS
```

### 1. 当前 Codex 任务先完成前置闸门

调用 Grok 前，当前 Codex 任务必须独立完成：

1. 阅读用户原始需求、本文件、相关代码和 Git 现场；不能把需求理解本身交给 Grok。
2. 确认任务 worktree、基线分支、允许修改的文件范围、禁止项、验收命令和成功标准。
3. 写出关键假设与真实歧义；需要用户选择的内容先向用户确认。
4. 将任务整理成可核对的 prompt contract：原需求、已确认决策、非目标、TDD 要求、验证门禁、Git 权限和交付格式。

### 2. 在当前任务右侧终端交互确认 Grok Plan

使用当前 Codex App 任务的右侧终端直接启动 Grok TUI，不使用单轮 `-p/--single`，让用户能在同一窗口追问、修改并确认计划：

```bash
grok --cwd "$TASK_WORKTREE" \
  --permission-mode plan \
  --no-subagents \
  "$PLAN_PROMPT"
```

- `PLAN_PROMPT` 必须要求 Grok 只分析和给计划，不改文件、不执行 Git 写操作。
- 用户必须在 Grok TUI 中明确确认计划；确认前不得切换到开发权限。
- 当前 Codex 任务同时审查计划是否逐条覆盖原需求、Red → Green → Refactor、改动边界、真实验证和风险。
- 计划遗漏、越界或替用户做了未确认选择时，先在 TUI 中要求重写；**未通过计划审查不得进入编码**。
- Plan 模式若仍产生文件改动，视为异常变更，按“闸门 A”处理。

### 3. 确认后恢复同一 Grok 会话开发

用户确认计划后，退出 Plan TUI，再从同一 worktree 恢复最近的 Grok 会话；必须明确关闭 Plan 模式，并使用可编辑但非无条件放权的权限模式：

```bash
grok --cwd "$TASK_WORKTREE" \
  --continue \
  --permission-mode acceptEdits \
  --no-plan \
  --no-subagents
```

- 继续会话后必须明确要求按已确认计划实施，并先读 worktree 内的 `AGENTS.md`。
- 明确允许修改的路径、禁止修改的路径、先写失败测试、相关验证命令，以及不可静默决定的事项。
- 用户尚未确认进入开发阶段时，禁止 `--always-approve`、`--permission-mode bypassPermissions` 和无边界 shell 权限。
- 用户已确认 Grok Plan 并明确进入开发阶段后，当前 Codex 任务可直接使用 `--always-approve`，避免逐条批准开发命令；但仍须保留既定 worktree、允许修改路径、`--no-subagents`、禁止项、TDD/验证门禁与 Git 权限边界。`--always-approve` 不得用于跳过 Plan 确认、用户决策或扩大任务范围。
- Grok 开发阶段不得由 Codex 在后台 PTY 中启动或轮询 TUI。优先使用只返回最终交付结果的非交互调用；确需交互时，由用户在当前任务可见终端直接操作，Codex 不以内部 PTY 冒充可见终端。
- Codex 不采集 Grok 的思考过程、全屏刷新或持续过程输出；只接收最终交付摘要，并独立从完整累计 diff、真实调用链和必要复测开始验收。Grok 自述仍不能作为验收结论。
- Codex 调用 Grok 开发时，应在 prompt contract 中指定仓库外的交付文件，例如 `/tmp/mahjong-game-issue-<number>-grok-delivery.md`。Grok 只在本轮实现和自测全部结束后写入该文件，末行必须为独占标记 `GROK_DELIVERY_COMPLETE`；不得在仓库内新增进度、状态或完成报告文档。
- Codex 以“Grok 进程正常结束 + 交付文件存在 + 末行完成标记正确”判断本轮开发是否结束，不通过轮询过程输出来猜测。进程异常退出、文件缺失或标记不完整均视为未完成，应先检查 Git 现场再决定恢复会话。
- Grok 遇到需求冲突、未知业务文件、测试基础设施故障或必须由用户决定的事项时，应停止并汇报，不得自行扩大范围。

### 4. Grok 的固定交付格式

Grok 完成一轮后必须汇报：

1. 修改文件列表与每个文件的目的；
2. 关键实现及其与原需求的对应关系；
3. Red / Green / Refactor 各阶段执行的命令和结果摘要；
4. 未验证项、已知风险、网络端到端缺口；
5. 当前 `git status`、commit / push / PR 状态（若获授权执行）。

上述内容写入指定的仓库外交付文件；最后一行写入 `GROK_DELIVERY_COMPLETE`。Codex 读取该文件仅用于确认完成并定位证据，不能用它替代完整 diff Review、业务实现 Review 或独立复测。

Grok 自述仅用于定位证据，**不能作为验收结论**。

### 5. 当前 Codex 任务必须独立从 diff 开始 Review

Grok 交付后，当前 Codex 任务必须亲自运行并阅读结果：

```bash
git status --short --branch
git diff --stat
git diff --check
git diff
# Grok 已提交时，改用实际基线：
git diff "$BASE_REF"...HEAD
```

审查至少覆盖：

- 对照用户原需求与批准计划逐条核对，不能只看“代码能跑”；
- **必须 Review 业务实现本身**：从真实生产入口沿调用链核对状态构造、规则门控、命令消费、事件发布/回放和最终用户可见行为，确认每条验收标准在实际业务路径生效；只新增 helper、DTO、占位对象或只用测试直接调用 helper，均不能证明业务已经实现。
- 核对业务边界与非目标：既不能遗漏关键副作用、异常分支和跨模块契约，也不能借机提前实现后续 Issue；测试全绿不能替代业务语义审查。
- 逐个读取所有变更文件，确认没有隐藏的范围扩张、未确认决策、临时代码或意外文件；
- 检查测试是否真正覆盖核心行为，mock 是否越过真实逻辑，Red 证据是否合理；
- 按风险由当前 Codex 任务**独立复跑** focused 测试、模块测试、全量 GUT、import、UI 截图或其他必要门禁；
- Grok 声称的测试、提交、推送、PR 与远端状态都要重新核实。

问题严重度统一为：P0 阻断/数据安全，P1 主要功能或架构错误，P2 正确性、契约或关键覆盖缺口，P3 非阻断改进。**P0、P1、P2 必须全部关闭后才可进入提交/PR 交付；P3 可记录后续。**

### 6. 返回同一 Grok 会话返工并复验

- 打回 Grok 时给出具体证据：文件与行、违反的需求/规则、失败命令与期望结果；禁止只说“质量不好”。
- 修复继续从原 worktree 使用 `--continue + acceptEdits + --no-plan + --no-subagents` 恢复同一会话，只处理已确认范围和本轮问题，不另开第二个写入会话，不借机扩需求。
- 每轮修复后，当前 Codex 任务重新审查**完整累计 diff**并复跑受影响验证；不能只看最后一个补丁或只相信 Grok 的复测结果。
- 循环直到 P0–P2 清零且所有成功标准有独立证据；否则状态保持 `REWORK_REQUIRED` 或真实阻塞状态。

### 7. Git、合并与下一批 Issue

- 默认由当前 Codex 任务在验收通过后执行 commit、push、创建 PR 和合并；Grok 不负责最终 Git 交付。
- 当前 Codex 任务必须核对本地 `HEAD`、远端分支 SHA、PR 完整 diff/状态、可合并状态和目标分支，不能把“命令成功”当作已交付。
- 禁止把未审查改动先提交来规避 diff 审查。
- 本仓库不把 GitHub CI 作为合并门禁；`.github/workflows/core-tests.yml` 仅允许手动触发。当前 Codex 任务独立完成风险相关测试、全量 GUT（适用时）、Review PASS 且 P0–P2 清零后，方可认定验证通过。
- PR 处于可合并状态且验证通过后，由当前 Codex 任务直接合并，无需再次等待用户授权。高歧义需求、不可逆生产操作、权限或凭证不明确等情形仍按前述阻塞规则请求用户决策。
- 合并后，当前 Codex 任务必须重新 fetch 并确认最新 `origin/main`，再读取 Epic、Issue 依赖、优先级和代码现场，分析下一批可做任务。
- 只有依赖已满足且修改范围不会冲突的 Issue 才能并行；每个后续 Issue 分别创建新的 Codex App 任务、分支和 worktree，并从交互 Grok Plan 重新开始。

---

## Git 工作流

### Worktree First

- **业务代码**（功能 / 缺陷 / 影响运行的配置与资源）默认：`git worktree` + 任务分支，**不直接在主工作区改业务代码**。
- 若当前已在非 `main` 的任务分支或本身就是该任务 worktree → **直接继续**，不重复新建。
- 新任务默认基于最新 `main` / `origin/main`；合并目标默认是创建 worktree 时的基分支（通常 `main`），不擅自改目标。
- 分支名可用 `feat/` `fix/` `docs/` `refactor/` `chore/`，也可用 `codex/` 前缀；Conventional Commits。
- **纯文档 / 纯 agent 规范**微调：可在当前分支或 `docs/*` 小分支提交，可不强求 worktree。
- **纯打包发布**（不改仓库跟踪内容）：可在主工作区执行。若发布任务要改版本/脚本/业务文件，仍先 worktree。
- 合并完成且不再需要时清理：`git worktree remove .worktrees/<task-name>`。

```bash
git worktree add .worktrees/<task-name> -b <branch-name> [<base-branch>]
```

### 提交、推送与 PR

- 每个 commit 应独立可构建；避免把不相关的 Godot 与 Go 改动混在一起。
- **本地一旦 `git commit`，默认尽快 `git push`**；暂不推送须用户明确说明。
- 任务结束后：若有需纳入版本的改动 → commit + push 任务分支，并**按需创建 PR**；回报 PR 链接 + 一句中文摘要。纯探索/只读无改动则跳过并说明。
- PR 描述（中文）须含：改动摘要、影响模块、验证方式与结果；涉及 UI 时附截图或手测说明。

---

## 记忆与文档固化

- 不依赖对话短期记忆；重要上下文与决策固化到 **`AGENTS.md` / `CLAUDE.md` / `docs/superpowers/`**，而非只留在对话里。
- 关键行为变更同步更新对应文档。
- 发现 `CLAUDE.md` 与代码事实不符时，**先更新文档，再继续工作**。
- **禁止新增根目录状态/进度/完成总结类 markdown**（仓库已有 200+ 历史噪音）。总结写进 commit message 或 `docs/`。

---

## 本仓库红线（行为约束）

> 详细技术事实见 `CLAUDE.md`。此处只列 agent 不得违反的约束。

1. **不信根目录 200+ 历史 markdown** —— 先看代码与 `CLAUDE.md` / `docs/superpowers/`，最后才谨慎参考根目录陈旧笔记。
2. **不扩张 `main.go`** —— 仅 Railway 健康检查桩；新后端须先与用户对齐。
3. **不新增根目录进度报告 markdown**。
4. **`class_name` 全局唯一** —— 新增前 `grep -rn 'class_name <Name>' godot/`；冲突优先改引用少的一侧。
5. **改 PNG / 新 `class_name` 后必须** `godot --headless --path godot --import` —— 否则 ctex 全黑或 Parse Error 雪崩。
6. **牌面契约**：`assets/mahjong_tiles_riichi/<key>.png` 文件名不变；**272×389**；face 用 **WHITE** modulate（dim 用遮罩）；赤宝走 **`0m/0p/0s`** 真图。
7. **纹理滤波**：`default_texture_filter=3`（LINEAR_WITH_MIPMAPS）。旧「NEAREST 像素完美」叙述已废弃。
8. **主路径**：`ui/lobby/lobby_shell.tscn` + `ui/four_player_table/`；`ui/run/run_flow` 已退出生产入口。`scenes/wechat_login_*`、`game_ui`、中式 `scripts/` / `legacy/` **勿接生产**。
9. **网络改动**须显式声明未端到端验证。
10. **资产生成**：`godot/tools/asset_gen/`；先 smoke 锁风格；staging QA 后 cp；凭证只读环境变量；`_raw_*` / `_staging*` 不入库。可用 Grok 内置 game-asset skills 补图标，仍遵守文件名与 import 纪律。
11. **插件**：已有 **GUT**、**Anima**。默认不堆社区插件；引入前对照 ROI（见 `docs/superpowers/specs/2026-05-24-godot-frameworks-evaluation.md`）。
12. **Autoload / 纹理隐式契约** —— 改 `TextureExtractor`、牌尺寸、调制规则前先查最近相关 commit。
