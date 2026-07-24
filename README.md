# 麻将王

面向桌面端的日式麻将项目。当前产品方向是：原创大厅、统一电脑对战、服务端权威公共匹配、实时语音，以及可确定性回放的“嘴强道具”。旧版单机 Roguelike / Run 流程已经退出生产入口。

## 当前事实源

按以下优先级理解项目，不要从历史计划反推当前实现：

1. [`AGENTS.md`](AGENTS.md)：开发工作流、TDD、验证和 Git 规则。
2. [`CLAUDE.md`](CLAUDE.md)：仓库结构、生产入口和技术不变量。
3. [`docs/superpowers/specs/2026-07-22-multiplayer-trash-talk-prd.md`](docs/superpowers/specs/2026-07-22-multiplayer-trash-talk-prd.md)：当前产品契约。
4. [`docs/superpowers/specs/2026-07-22-multiplayer-trash-talk-epics.md`](docs/superpowers/specs/2026-07-22-multiplayer-trash-talk-epics.md)：Epic 边界与完成定义。
5. [`docs/superpowers/plans/2026-07-22-multiplayer-trash-talk-issue-backlog.md`](docs/superpowers/plans/2026-07-22-multiplayer-trash-talk-issue-backlog.md)：叶子 Issue 与依赖关系。

配套工程契约：

- [`E0-02 代码 / IP 盘点`](docs/superpowers/specs/2026-07-22-e0-02-code-ip-inventory.md)
- [`E0-03 架构与协议 ADR`](docs/superpowers/specs/2026-07-22-e0-03-architecture-protocol-adr.md)
- [`E0-04 验收测试矩阵`](docs/superpowers/specs/2026-07-22-e0-04-acceptance-test-matrix.md)
- [`Master Implementation Plan`](docs/superpowers/plans/2026-07-22-multiplayer-trash-talk-master-plan.md)

## 生产主路径

- Godot 主场景：`godot/ui/lobby/lobby_shell.tscn`
- 四人牌桌：`godot/ui/four_player_table/`
- 日麻规则与对战：`godot/core/`、`godot/battle/`
- 根目录 `main.go`：仅 Railway 健康检查桩，不是联机游戏服务端

`godot/ui/run/run_flow`、旧微信登录场景和中式麻将 `legacy` 代码不属于生产入口。

## 快速验证

```bash
# 资源与 class_name 缓存
godot --headless --path godot --import

# 全量 GUT（仅在 AGENTS.md 规定的升级条件下执行）
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -ginclude_subdirs -gexit

# Go 健康检查桩
go test ./...
```

具体改动应按 [`AGENTS.md`](AGENTS.md) 选择 focused、模块、UI 或全量验证，不要机械执行所有门禁。

## 历史文档

与当前玩法无关的旧肉鸽、抽卡、Steam、旧联机方案、旧发布说明和旧平衡记录已移入 `docs/archive/`。该目录是冻结历史，默认搜索已排除；除非用户明确要求追溯历史，否则不要读取或引用。
