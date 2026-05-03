# 任务追踪

> **历史背景**：本文件原为 2024 年项目初始化阶段的 27 周课表，与现仓库（麻将王 — 日麻 + 卡牌技能 + Roguelike）完全脱钩，整体替换为指向"活任务追踪"的索引。

## 活任务追踪在哪里

仓库 GitHub Issues **已禁用**；任务追踪走 markdown checkbox 文档：

| 类别 | 文档 |
|---|---|
| **当前里程碑活任务板** | [`docs/superpowers/plans/2026-05-02-content-production.md`](docs/superpowers/plans/2026-05-02-content-production.md) — M6 内容生产任务板（28 牌技能 + 9 角色能力 + 3 章 Boss + 3 起始包，每个 checkbox 一个独立 PR） |
| **里程碑总表 + 状态** | [`README.md`](README.md) §"当前状态"（M0-M5 ✅ / M6 ⏳ / M7 ⏳） |
| **主 spec** | [`docs/superpowers/specs/2026-05-01-mahjong-king-design.md`](docs/superpowers/specs/2026-05-01-mahjong-king-design.md) §13 实现里程碑 |
| **每里程碑实现计划** | [`docs/superpowers/plans/`](docs/superpowers/plans/) 下各 `2026-MM-DD-*.md`（含已完成 M0-M6 + M7 brainstorm 草案） |

## 协作约定

- **认领规则、PR 工作流、TDD、闸门、Git/发布原则**：见 [`AGENTS.md`](AGENTS.md)
- **代码风格、Godot 不变量、已知陷阱、GUT 命令**：见 [`CLAUDE.md`](CLAUDE.md)
- **新增计划应放 `docs/superpowers/plans/`，不要新增根目录 markdown**（CLAUDE.md "Don't add new top-level markdown status reports"）

## 不要相信的旧文档

根目录散落的 `PHASE*.md` / `RAILWAY_*.md` / `*_FINAL_*.md` / `项目*.md` 等历史状态报告**不权威**（详见 CLAUDE.md "Don't trust the README's API surface"）。如需历史信息查 `git log`。
