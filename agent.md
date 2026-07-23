# Agent Instructions

> Codex / Grok / Claude 等 AI agent 的**轻量入口**。
> 详细开发原则以 [`AGENTS.md`](./AGENTS.md) 为权威源；项目技术事实见 [`CLAUDE.md`](./CLAUDE.md)。
> 修改规则时：**先改 `AGENTS.md`，再同步本文件与 `CLAUDE.md`**。
> 优先级：**用户显式指令 > `AGENTS.md` / 本文件 > 默认行为**。

## 默认语言

- 与用户沟通默认**中文**；用户明确指定其他语言时再切换。
- PR / Issue 的标题、正文、评论、检查说明默认**中文**。

## 分支与 Worktree

- 业务代码 / 功能 / 缺陷修复：默认从最新 `main` 建任务分支，并在独立 `git worktree` 内开发；不直接在主工作区改业务代码。
- 若当前已在非 `main` 任务分支或已是该任务 worktree → 直接继续，不重复新建。
- 分支名可用 `feat/` `fix/` `docs/` `refactor/` `chore/` 或 `codex/` 前缀。
- **纯文档 / agent 规范**可走 `docs/*` 小分支，不强求 worktree。
- PR 合并目标默认 `main`（或创建 worktree 时的基分支）。

```bash
git worktree add .worktrees/<task-name> -b <branch-name> [main]
```

## 提交与 PR

- 改动完成并通过相关验证后：commit → 默认尽快 push → 按需开 PR。
- PR 用中文写：改动摘要、影响模块、验证方式与结果；UI 附截图或手测说明。
- 纯探索 / 只读无版本改动时，跳过 commit/PR 并说明原因。

## 验证门禁

```bash
godot --headless --path godot --import
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests -ginclude_subdirs -gexit
# UI 可选：godot --path godot -s tools/capture_screens.gd
```

- 功能/缺陷默认 TDD（Red → Green → Refactor），除非用户允许跳过。
- 禁止用 mock 顶替日麻规则等核心被测逻辑。
- 网络/WebSocket：无本仓服务端 → 必须声明「未端到端验证」。
- 仅改文档时：至少 `git diff --check`。

## 计划与 UI

- 实现前给可执行计划：假设 / 范围 / 验证 / 风险 / 成功标准。
- UI：简单 → ASCII 草图确认；复杂 → 草图 + 取舍（可选截图）；复杂流程 → Mermaid。

## 红线（摘要）

- 不扩张 `main.go`；不新增根目录状态报告 md；不信根目录 200+ 陈旧笔记。
- 主路径：`ui/lobby` + `ui/four_player_table`；`ui/run` 已退出生产入口（非微信登录 / 非中式 `game_ui`）。
- 改资产或 `class_name` 后必须 `--import`；牌面 272×389 文件名契约；WHITE modulate；赤宝 `0m/0p/0s`。
- 滤波：LINEAR_WITH_MIPMAPS（勿写回 NEAREST）。
- `class_name` 全局唯一；资产中间产物不入库。

完整条款见 [`AGENTS.md`](./AGENTS.md)。
