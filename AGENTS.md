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

### 5. 上下文与输出纪律

- 完整执行 Review 与验证，但不要把海量过程输出重复灌入对话上下文；保留需求、决策、真实调用链、关键 diff、失败证据、最终摘要和 Git/远端状态即可。
- 同一任务中已经完整读取且未发生变更的 `AGENTS.md`、Skill 或长篇规范，不得重复完整读取；后续只用 `rg -n` 定位并读取相关小范围。文件确有变更或上下文压缩后关键规则无法可靠恢复时，才重新读取必要内容。
- 超过 500 行或 20 KB 的源码、fixture、JSON、Issue/PR 正文先用 `wc` 确认体积，再用 `rg -n` 定位符号或关键词并分段读取；禁止无目的整文件展开。正式 Review 仍须覆盖全部变更文件，但可按 diff hunk 和调用链分段完成，不能以节省上下文为由漏审。
- 全量 GUT、import、构建等高输出命令必须将 stdout/stderr 重定向到仓库外 `/tmp` 日志；命令结束后只提取最终 totals、失败/错误、退出码与本次新增 warning。**禁止用 `cat`、无范围 `sed` 或工具调用一次性读取整份日志**；仓库既有 warning 不重复展开完整堆栈。
- 完整累计 diff 必须在正式 Review 节点至少独立审查一次；同一轮不得为状态确认重复展开完整 diff。返工后先读变更清单、受影响文件和新增 hunk，再按风险复核累计关键路径，不重复输出未变化的大段 diff。
- GitHub Issue、Epic、PR 和 CI 查询优先请求标题、状态、依赖、正文、关键评论、head/base SHA、mergeability 等必要字段；不得默认拉取全部 timeline、review、checks 或大段日志。只有当前结论需要时再增量查询对应字段。
- 审计 `/tmp` 长日志时，先用 `wc -l/-c` 确认体积，再用 `rg` / 有界 `tail` 提取与当前结论直接相关的证据。仅在发现失败且摘要不足以定位时，才按命中行号读取小范围上下文；不得因此隐藏失败、跳过门禁或把“输出被截断”误报为通过。

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
> 同一个 Codex 任务负责需求对齐、驱动 Grok、独立 Review、验证、返工、Git 交付、合并，以及合并后直接启动已解锁的后续 Issue。
> 不额外创建 Review 任务，不引入 `agentctl` 或调度器；Grok 统一通过可见 macOS Terminal + attached tmux inline TUI 运行，不使用 Codex 右侧终端或后台 PTY。同一 Issue 始终保留并复用一个 tmux session 和其中的 Grok TUI，最终验收通过后才关闭。

### 适用边界与状态

- 一个 Issue 对应一个 Codex App 任务、一个任务分支和一个 worktree；同一 worktree 同时只能有一个 Grok 写入。
- **每个 Issue 内**默认只运行 1 个 Grok CLI 会话串行开发；不同 Issue 可在各自独立 Codex App 任务、分支、worktree 和 Grok TUI 中并行，禁止 Grok 再派生子任务修改同一需求。
- 高歧义需求、需要产品取舍、不可逆生产操作、权限或凭证不明确时，不得先让 Grok 猜测实现。
- 需要用户选择时进入 `BLOCKED_USER_DECISION`，明确列出选项、影响和推荐项并等待答复；不得跳过。若宿主提供 goal/status 工具，按该工具自身规则设置阻塞状态，不得伪造状态。
- 推荐状态流：

```text
BLOCKED_USER_DECISION（前置闸门如需）
  → GROK_PLAN_AND_IMPLEMENT
  → WAITING_GROK_STATUS
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

### 2. 在可见 Terminal + tmux 一次启动 Plan 与开发

当前 Codex 任务完成前置闸门并处理完必须由用户决定的歧义后，使用可见 macOS Terminal + attached tmux 启动 Grok inline TUI。一次调用中要求 Grok 先给出可滚动中文计划、自检覆盖范围，再按该计划直接开发；不使用 Codex 右侧终端或单轮 `-p/--single`：

```bash
grok --cwd "$TASK_WORKTREE" \
  --minimal \
  --no-alt-screen \
  --permission-mode plan \
  --no-subagents \
  --always-approve \
  --rules "全程使用简体中文与用户交互；命令、代码、标识符和原始错误可保留英文，但必须用中文解释。" \
  "$PLAN_AND_IMPLEMENT_PROMPT"
```

- 当前 Issue 启动时记录唯一精确 tmux session 名；tmux 必须开启 `mouse`，`history-limit` 至少为 50000。用户可滚轮回看，或按 `Ctrl-b`、`[` 进入 copy-mode，按 `q` 返回。
- 启动参数固定同时使用 `--permission-mode plan --always-approve`；完全授权只免除逐条工具审批，不扩大 worktree、允许路径、Git 权限和需求范围。
- `PLAN_AND_IMPLEMENT_PROMPT` 必须要求 Grok：先读取本文件；先输出中文计划并逐条自检原需求、Red → Green → Refactor、改动边界、真实验证和风险；确认无遗漏后在同一 TUI 直接开发，不退出、不调用 `--continue`、不启动第二个 Grok。
- 必须由用户决定的产品取舍、权限、安全或不可逆事项应已在前置闸门解决；开发中才发现的新阻塞不得猜测，写入仓库外状态文件并停在 TUI 等待。
- 当前 Codex 任务不得通过读取 pane 审查 Grok 的过程计划；最终仍以完整累计 diff、真实业务调用链和独立复测验收。计划自检不能替代最终 Review。

### 3. 启动后立即轮询状态与最终交付

启动前为本轮指定两个唯一仓库外路径：

```text
/tmp/<project>-issue-<number>-grok-status-round-<n>.txt
/tmp/<project>-issue-<number>-grok-delivery-round-<n>.md
```

- 状态文件只允许为单行稳定值：`GROK_PLANNING`、`GROK_IMPLEMENTING`、`GROK_BLOCKED_USER_DECISION`、`GROK_DELIVERY_COMPLETE`。Grok 在开始计划、进入实现、发现新用户决策阻塞和完成交付时原子覆盖该文件；不得写思考过程、token 或长日志。
- 交付文件格式见下一节，只有全部实现和自测结束后才写，末行必须为独占标记 `GROK_DELIVERY_COMPLETE`。
- Grok 开发阶段不得由 Codex 在后台 PTY 中启动；必须使用可见 Terminal + tmux inline TUI。用户可在弹窗直接观察和交互，Codex 不以内部 PTY 冒充可见终端。
- Codex 不采集 Grok 的思考过程、全屏刷新或持续过程输出；只接收最终交付摘要，并独立从完整累计 diff、真实调用链和必要复测开始验收。Grok 自述仍不能作为验收结论。
- Grok 启动成功后，Codex **立即**进入 `WAITING_GROK_STATUS` 并持续轮询上述状态文件与交付文件完成标记；不得先结束当前执行回合等待用户另行提醒。
- 轮询期间只读取这两个仓库外文件；不得检查中间 Git 状态、文件列表、tmux pane、pane 命令、进程或测试进度，不发送 `Ctrl-C`、`tmux send-keys` 或补充 prompt，也不因已批准范围内的新文件而打断 Grok。
- 状态缺失、`GROK_PLANNING` 或 `GROK_IMPLEMENTING` 时继续等待且不重复汇报；`GROK_BLOCKED_USER_DECISION` 时读取交付/状态中明确的问题并向用户请求决策；只有交付文件末行为 `GROK_DELIVERY_COMPLETE` 且状态为同名值时才停止轮询，保留当前 tmux session 与 TUI，进入完整 diff Review。
- 只有用户明确报告 Grok 已退出但没有完整交付时，Codex 才可一次性检查 tmux 会话和 Git 现场。
- Grok 遇到需求冲突、未知业务文件、测试基础设施故障或必须由用户决定的事项时，应停止并汇报，不得自行扩大范围。

### 4. Grok 的固定交付格式

Grok 完成一轮后必须汇报：

1. 修改文件列表与每个文件的目的；
2. 关键实现及其与原需求的对应关系；
3. Red / Green / Refactor 各阶段执行的命令和结果摘要；
4. 未验证项、已知风险、网络端到端缺口；
5. 当前 `git status`、commit / push / PR 状态（若获授权执行）。

上述内容写入指定的仓库外交付文件；最后一行写入 `GROK_DELIVERY_COMPLETE`。Codex 读取该文件仅用于确认完成并定位证据，不能用它替代完整 diff Review、业务实现 Review 或独立复测。

功能/缺陷代码每轮最终交付前，Grok 必须在该轮**最后一次代码修改后**执行一次全量 GUT，将完整输出重定向到仓库外日志，并在交付中记录完整命令、退出码、scripts/tests/asserts/fail totals 与日志路径；交付文件不得复制整份测试输出。返工使旧全量证据早于最后修改时，新一轮必须重新执行全量；纯文档任务按文档门禁豁免。

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
- 按风险由当前 Codex 任务**独立复跑** focused/模块测试、import、UI 截图或其他必要门禁。若 Grok 已在最后一次代码修改后完成全量 GUT，且交付含可核对的退出码、totals 和日志，当前 Codex 到 `VALIDATING` **不重复执行同一全量 GUT**，而是先检查日志体积，再用 `rg` / 有界 `tail` 审计失败、解析错误、totals 与新增 warning，**不得读取整份 GUT 日志**，并用风险 focused 测试独立交叉验证；只有命中异常时才围绕命中行读取必要的小范围上下文。全量证据缺失、过期或矛盾时必须打回 Grok 重跑，不能由 Codex 自己补跑后直接放行；
- Grok 声称的测试、提交、推送、PR 与远端状态都要重新核实。

问题严重度统一为：P0 阻断/数据安全，P1 主要功能或架构错误，P2 正确性、契约或关键覆盖缺口，P3 非阻断改进。**P0、P1、P2 必须全部关闭后才可进入提交/PR 交付；P3 可记录后续。**

### 6. 返回同一 Grok 会话返工并复验

- 打回 Grok 时给出具体证据：文件与行、违反的需求/规则、失败命令与期望结果；禁止只说“质量不好”。
- 修复直接在当前 Issue 唯一的可见 tmux session 与仍打开的 Grok TUI 中输入中文返工 prompt，只处理已确认范围和本轮问题，不退出/重启 Grok，不使用 `--continue`，不另开第二个 tmux session 或写入会话，不借机扩需求。标记出现前禁止补充 prompt 或干预；标记出现且 Review 确认需要返工后，将仓库外 prompt 用 `tmux load-buffer` + `tmux paste-buffer` 送入记录的精确 session/pane，再用一次 `tmux send-keys ... Enter` 提交，不得读取或捕获 pane 输出。提交后同样只等待新的交付文件完成标记。
- 每轮修复后，当前 Codex 任务重新审查**完整累计 diff**并复跑受影响验证；不能只看最后一个补丁或只相信 Grok 的复测结果。
- 循环直到 P0–P2 清零且所有成功标准有独立证据；否则状态保持 `REWORK_REQUIRED` 或真实阻塞状态。

### 7. Git、合并与下一批 Issue

- 默认由当前 Codex 任务在验收通过后执行 commit、push、创建 PR 和合并；Grok 不负责最终 Git 交付。
- 当前 Codex 任务必须核对本地 `HEAD`、远端分支 SHA、PR 完整 diff/状态、可合并状态和目标分支，不能把“命令成功”当作已交付。
- 禁止把未审查改动先提交来规避 diff 审查。
- 本仓库不把 GitHub CI 作为合并门禁；`.github/workflows/core-tests.yml` 仅允许手动触发。Grok 最后一轮全量 GUT 证据有效、当前 Codex 独立完成风险相关测试与日志审计、Review PASS 且 P0–P2 清零后，方可认定验证通过；当前 Codex 不机械重复同一全量 GUT。
- 当前 Issue 只记录并复用一个精确 tmux session 名，覆盖 Plan、开发、Review、返工与复验，并始终保留同一个 Grok TUI；每轮完成标记出现后不得关闭。只有完整 diff Review 完成、P0–P2 清零且当前 Codex 任务独立验证全部通过后，才先用 `tmux list-sessions` 只读确认名称，再执行 `tmux kill-session -t "$EXACT_SESSION"` 手工关闭，并复查该精确 session 已不存在。禁止 `tmux kill-server`、glob、前缀/模糊匹配或关闭未经记录的其他 session；全程不管理 Grok session ID。
- PR 处于可合并状态且验证通过后，由当前 Codex 任务直接合并，无需再次等待用户授权。高歧义需求、不可逆生产操作、权限或凭证不明确等情形仍按前述阻塞规则请求用户决策。
- 合并后，当前 Codex 任务必须重新 fetch 并确认最新 `origin/main`，再读取 Epic、Issue 依赖、优先级和代码现场；不得只给下一 Issue 建议，必须直接为所有已解锁且可安全并行的后续 Issue 创建并启动新的 Codex App 任务。
- 只有依赖已满足且主要写文件不会冲突的 Issue 才能并行；每个后续 Issue 分别使用新的 Codex App 任务、分支、worktree 和 Grok TUI，并从交互 Grok Plan 重新开始。暂未解锁的 Issue 保留在 Epic 中，待前置合并后由完成该前置的任务继续自动启动。

---

## Git 工作流

### Worktree First

- **业务代码**（功能 / 缺陷 / 影响运行的配置与资源）默认：`git worktree` + 任务分支，**不直接在主工作区改业务代码**。
- 若当前已在非 `main` 的任务分支或本身就是该任务 worktree → **直接继续**，不重复新建。
- 新任务默认基于最新 `main` / `origin/main`；合并目标默认是创建 worktree 时的基分支（通常 `main`），不擅自改目标。
- 分支名可用 `feat/` `fix/` `docs/` `refactor/` `chore/`，也可用 `codex/` 前缀；Conventional Commits。
- **纯文档 / 纯 agent 规范**微调：可在当前分支或 `docs/*` 小分支提交，可不强求 worktree。
- **纯打包发布**（不改仓库跟踪内容）：可在主工作区执行。若发布任务要改版本/脚本/业务文件，仍先 worktree。
- Issue 合并后必须先 fetch 并确认对应提交已进入最新 `origin/main`，再检查任务 worktree 干净、没有未推送提交、没有需保留的 stash 或异常文件；确认安全后立即用**精确路径**删除该 Issue 的本地 worktree，并清理已合并的本地任务分支。不得把“后续可能还会用”作为长期保留理由，也不得使用 glob、模糊匹配或批量命令误删其他任务 worktree；存在未提交/未推送内容时必须暂停并报告，禁止强制删除。

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
