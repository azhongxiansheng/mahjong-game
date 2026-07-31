# AGENTS.md

> 本文件只记录 mahjong-game 相对通用 Agent 默认行为的项目级工作流与硬约束。
>
> - `AGENTS.md`：项目策略与验收门禁；
> - `CLAUDE.md`：架构、路径、版本、资产契约等技术事实；
> - 当前会话选中的 `SKILL.md`：领域流程与工具协议；
> - 脚本和测试：确定性执行入口。
>
> 不在多处复制完整规则；发生冲突时先按上述职责定位事实源。指令优先级由运行宿主决定，本文件不得覆盖更高层指令。

## 沟通与执行边界

- 默认使用中文与用户沟通；代码注释、日志、commit、PR / Issue 也优先中文，既有英文文件可保持原风格。
- 采用能解决当前目标的最小、可追溯改动，不顺手重构、清理或扩展无关内容。
- 只有当歧义会实质改变范围、结果、安全、成本或不可逆操作时才暂停确认；其余情况采用合理假设推进，并在交付时披露关键假设。
- 非琐碎、多步骤或高风险任务在实现前给出简短计划，至少说明改动范围、验证方式、风险和成功标准；明确的微小任务可直接执行。
- 发现非己方产生且影响运行、构建、测试的代码、脚本、配置、锁文件或业务资源时，暂停并询问如何处理；纯文档、Agent 说明和本地元数据可忽略，但不得擅自删除或纳入提交。
- 使用子 Agent 或外部 worker 时，主 Agent 必须独立审查累计 diff 和真实生产调用链，并按风险复跑必要验证；不得以 worker 自述或其测试结果代替验收。
- 全量 GUT、import、构建等高输出命令把 stdout/stderr 写入仓库外 `/tmp`；只提取 totals、错误、退出码和新增 warning。正式 Review 至少完整审查一次累计 diff。

## UI 与产品确认

- 用户描述已经明确、变化局部且不改变整体布局的 UI 调整可直接实现，并用相关 UI 测试和主路径目视验证。
- 新面板、弹层、布局重构、多方案或产品取舍必须先给简短 ASCII / wireframe 与取舍说明，取得用户确认后再实现。
- 跨三个以上步骤、涉及多模块状态或异常分支的复杂流程，仅在图示能明显提升理解时提供 Mermaid 流程或状态图。
- 同时涉及横竖屏等多种屏幕形态时，分别说明布局和验证方式。

## TDD 与验证

### TDD

- 功能开发和缺陷修复默认严格执行 Red → Green → Refactor，除非用户明确允许跳过。
- Red 阶段先写测试并运行到目标失败；不得先写生产实现再补测试。
- 文档、纯发布、纯配置搬运或无法合理自动化的微小改动可使用轻量验证，但必须说明理由并执行最小可验证检查。
- 核心行为必须走真实逻辑和真实资产加载路径。mock 只隔离第三方网络或当前任务无法启动的外部服务等不可控副作用，不得替代胡牌、符算、TurnEngine、鸣牌等核心规则。

### 仓库验证入口

```bash
# 新 worktree 首测，以及修改全局 class_name 或资产后
scripts/godot_bootstrap.sh

# 开发中的 focused / 模块测试（先 bootstrap）
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests/<module> -gselect=<test_name> -gexit

# 风险触发、发布或里程碑回归才运行全量
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests -ginclude_subdirs -gexit

# 复杂 UI 截图，输出 /tmp/shot_*.png
godot --path godot -s tools/capture_screens.gd
```

| 改动类型 | 最低验证 |
|---|---|
| `core/`、`battle/`、规则、AI | 受影响 GUT 模块 + 直接依赖契约测试 |
| `ui/` 布局与交互 | GUT UI 测试 + 主路径手测；复杂改动补截图 |
| PNG、其他业务资产、新 `class_name` | bootstrap/import + 相关 GUT + 主场景目视 |
| 纯文档、Agent 说明 | `git diff --check` + 人工通读 |
| 网络、WebSocket 客户端 | 相关测试，并显式声明未完成公网四客户端端到端验证 |
| 根目录 Go 桩 `main.go` | 如获确认修改，先写 `_test.go`；不得扩张其健康检查职责 |

- 日常快速门禁使用 `scripts/test_run_core.sh`；协议、服务器、整局、UI、STT 等重型回归使用 `scripts/test_run_slow.sh`，两者不可互相冒充覆盖范围。
- Codex App worktree 可通过 `.worktreeinclude` 获得必要 Godot 导入缓存，但仍必须由 `scripts/godot_bootstrap.sh` 执行两轮 import 和第二轮错误审计。禁止提交 `.godot/`，也不得把首次 import 的退出码 0 当成缓存有效。
- 开发中只运行新增/修改用例和受影响模块；最后一次代码修改后，必须运行受影响模块及直接依赖契约测试，并执行 `git diff --check`。
- 受影响范围从真实生产调用链、共享数据结构和资源加载关系推导，不能只跑新测试自证。

满足任一条件时升级全量 GUT：

1. 修改跨模块协议/schema、事件序列化/恢复、权威基础状态机或通用规则基础设施；
2. 修改 Autoload、`project.godot`、插件/依赖、全局 `class_name` 解析链或大范围资源导入；
3. focused/模块测试出现跨目录 Parse Error、系统性失败，或无法可靠界定影响范围；
4. 用户明确要求，或准备发布/里程碑回归。

未运行全量时，PR 只能列出实际受影响测试和未覆盖风险，不得写“全量通过”。

生产测试放在 `godot/tests/<module>/test_*.gd`。不得把新生产逻辑放进遗留的 `godot/scripts/test_*.gd` 或 `scenes/test_*.tscn`；`godot/tests/scenes/**/*.tscn` 仅供编辑器 F6 手测。

任何“完成、修复、测试通过”结论必须附可执行命令和结果摘要；UI 改动补截图路径或手测说明。

## 外部接口与 Skill

- 对接 Godot 4.5/4.6 API、外部 HTTP/WS、SDK、OS API 或生成服务前，先核对当前官方资料和仓库既有正确用法，再用最小真实 smoke 固化参数、返回、错误和限制，最后按真实行为写测试。不能实测时披露原因和替代验证，不得把猜测写成事实。
- 用户点名 Skill、模型、供应商或 CLI 时优先服从；未点名时选择当前会话实际暴露、覆盖范围最小的 Skill。所需 Skill 缺失或同名副本冲突时，说明阻塞或回退方案，不凭记忆拼接流程。
- 游戏角色、场景、牌面、UI、图标、透明资产、Sprite、动画帧、Tileset 使用 `game-asset-forge` 建立资产合同和产品验收；需要模型生成时再叠加当前会话暴露的 provider Skill。
- 真实媒体生成可能计费，必须先获用户授权并做一个最小 smoke。候选、响应和中间产物放在唯一的仓库外 `/tmp/<project>-<task>-<provider>-<round>/`；用户选定前不得复制进生产目录或据此修改场景。
- HTTP 2xx、脚本 `OK`、网页预览或异步 `completed` 不等于资产合格。入库前必须读取最终文件，检查签名、规格、内容、alpha/halo、小尺寸可读性；视频还要核对元数据、代表帧和可播放成片，再执行 Godot import、场景加载和受影响测试。
- 凭证只从 Skill 规定的环境变量或受控存储读取，不进入 prompt、参数、回显、日志、文件名、元数据、仓库或交付说明。外部素材必须确认使用权，不复刻竞品角色、Logo、专有纹样、文案或像素布局。

## Grok CLI 项目覆盖规则

仅在用户明确选择 Grok CLI 开发时适用。Grok 的唯一流程事实源是 Akasha Grimoire 中的 `grok-cli-development` Skill 及其脚本；仓库内 `.agents/skills/grok-cli-development/` 的兼容副本不得作为回退。当前会话未暴露 Akasha 版本时暂停并报告，本节只规定 mahjong-game 的覆盖项。

- 一个 Issue 对应一个 Codex App 任务、任务分支、worktree、可见 Terminal 窗口和 attached tmux TUI；同一 worktree 同时只有一个 Grok writer。不同 Issue 仅在写文件不冲突时各自并行。
- 当前 Codex 任务先独立完成需求理解、Git 现场检查、允许范围、非目标、TDD 和验收合同；产品取舍、权限、凭证、安全或不可逆事项先向用户确认，不让 Grok 猜测。
- Plan、Red、Green/Refactor、返工和交付复用同一个 Grok TUI；Grok 禁止派生子 Agent，不使用后台 PTY、单轮模式、`--continue` 或第二个 Grok 会话。媒体生成也留在同一可见 TUI。
- 启动和每次输入后按 Skill 的状态/交付文件合同运行单一长 monitor；项目状态包括 `GROK_PLANNING`、`GROK_RED_READY`、`GROK_IMPLEMENTING`、`GROK_BLOCKED_USER_DECISION`、`GROK_SCOPE_DRIFT`、`GROK_ERROR`、`GROK_ABORTED`、`GROK_DELIVERY_COMPLETE`。项目把单轮等待覆盖为最长 1800 秒，由脚本每 20 秒检查；退出码 0/3/124 分别表示完成、需要动作和本轮超时。
- 安静的 planning/implementing 是正常状态，不读取 pane、不检查中间 Git 现场、不高频轮询、不发送 `Ctrl-C`，也不自动发送“按推荐执行”。
- 需要用户决策时只请求并投递一次答案；短时间状态未变化不重复输入。Grok 已退出但缺少完整交付时，只有用户明确报告后才检查 tmux 和 Git 现场。
- Grok 交付必须列出修改文件、需求映射、Red/Green/Refactor 命令与结果、最后一次修改后的受影响验证日志、未验证项、风险和 Git 状态。
- 当前 Codex 从累计 diff 和真实生产入口沿调用链独立 Review，核对状态构造、规则门控、命令消费、事件发布/回放和最终用户可见行为；测试直接调用 helper、DTO 或占位对象不能证明业务已经接线。随后审计 Grok 最后修改后的验证证据，并使用相邻 focused/契约测试交叉验证。证据缺失、过期或矛盾必须打回 Grok，P0–P2 清零前不得 Git 交付。
- 返工继续使用同一 TUI；完整返工合同写到唯一的仓库外文件，tmux 只粘贴一行读取指令并只提交一次。返工后重新审累计关键路径和受影响验证。
- 只有完整 Review 和独立验证通过后，才按精确 session 名关闭 tmux；禁止 `tmux kill-server`、glob、模糊匹配或关闭未记录的 Terminal 窗口。

## Git 与 worktree

- 业务代码、影响运行的配置和资源默认在任务 worktree 与任务分支中修改，不直接在主工作区开发；当前已经位于非 `main` 任务分支或对应 worktree 时直接继续。
- 纯文档或 Agent 规范微调可在当前分支完成；纯打包且不改跟踪内容可在主工作区执行。
- 新任务默认基于最新 `main` / `origin/main`，合并目标默认是建 worktree 时的基分支；分支默认使用 `codex/<task-name>`，已有明确命名约定时遵循项目约定。
- commit、push、创建或合并 PR、启动后续 Codex App 任务都需要用户或当前 Issue 明确授权；不得从普通“修改/修复”请求自动扩张到远端发布或后续任务。
- 每个 commit 应独立可构建，不混入无关 Godot、Go 或文档改动。PR 默认使用中文，包含摘要、影响模块、验证命令与结果；UI 改动附截图或手测说明。
- Issue 合并后，先 fetch 并确认提交进入最新 `origin/main`，再确认任务 worktree 干净、无未推送提交、需保留 stash 或异常文件；仅用精确路径删除该 worktree 和已合并本地分支。存在未提交/未推送内容时暂停报告，禁止强制删除、glob、模糊或批量清理。

## 文档与项目红线

- 工作流只改本文件；技术事实改 `CLAUDE.md`；领域流程改对应 Skill。关键行为变化同步更新任务范围内的事实源；发现范围外文档失真时先报告，不顺手扩张修改。
- 禁止新增根目录状态、进度或完成总结类 Markdown；总结写入 commit message 或活跃 `docs/`。
- `docs/archive/` 是冻结历史，不是当前事实源。除非用户明确要求历史追溯、旧决策审计或迁移核对，否则不读取或引用，不用归档内容覆盖代码、`CLAUDE.md` 或活跃 `docs/superpowers/`。
- 根目录 `main.go` 仅为 Railway 健康检查桩；新后端或职责扩张必须先与用户对齐。
- 生产主路径、牌面文件名与尺寸、纹理滤波、Autoload、插件和资产生成事实以 `CLAUDE.md` 为准。修改这些契约前先查真实调用链、相关资源和最近相关 commit，并执行对应 import、测试和目视验证。
- 新增全局 `class_name` 前用 `rg -n 'class_name <Name>' godot/` 检查唯一性。
- 不把退役或遗留场景、脚本重新接入生产主路径；具体范围见 `CLAUDE.md`。
- 本仓已有本地 control-plane、STT 和 Headless Worker 路径，但没有公网四客户端完整环境；任何网络改动都必须明确写“未完成公网四客户端端到端验证”。
- 默认不增加社区插件；确有需要时先给出必要性、维护成本和替代方案。
- 生成原稿和 staging 文件不入库；仍须遵守 `CLAUDE.md` 中牌面命名、尺寸、版权/IP、凭证和 import 契约。
