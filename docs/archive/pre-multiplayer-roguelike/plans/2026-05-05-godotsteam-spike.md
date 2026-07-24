# GodotSteam 集成 spike（2026-05-05）

> **类型**：Steam 集成技术 spike doc。补充 [`steam-readiness brainstorm`](2026-05-05-steam-readiness.md)（PR #120）的 D2 项 — GodotSteam 插件集成可行性研究。**纯研究，不动代码**。
>
> 上游链接：[CoaguCo-Industries / GodotSteam @ Codeberg](https://codeberg.org/GodotSteam/GodotSteam)（GitHub 已 archive 2026-04-04，迁 Codeberg 主仓）

## TL;DR

- **GodotSteam 4.18.1 可用**（2026-04-04 release）— **匹配 Godot 4.6.2 + Steamworks SDK 1.64**；本项目 Godot 4.5 / 4.6.1 验证过，4.6.2 minor 升级风险低
- **集成方法二选一**：
  - **GDExtension（推荐）**：plugin-style，addons/ 目录拖入即可；不用重编 Godot
  - **Module**：把 GodotSteam 编进 Godot 引擎，需要从源码 build Godot；维护成本高
- **预编译 binary 可下载** — 不用自己 build
- **平台**：Win / Linux / Mac（与 Godot export targets 一致；Steam Deck = Linux）
- **预估工时**：GDExtension 接入 2-3 天 spike + 调试；首个真正使用功能（成就 emit）半天

## 一、GodotSteam 提供的 API（v4.18.1）

按本项目需求分类：

### v1.0 必须

| 功能 | API class | 备注 |
|---|---|---|
| **初始化 / restart 检测** | `Steam.steamInit()` / `Steam.restartAppIfNecessary(appid)` | 启动时调；如果用户绕过 Steam 客户端启动，restart 把控制权交回 Steam |
| **Steam Achievements** | `Steam.setAchievement(name)` / `Steam.getAchievement(name)` / `Steam.storeStats()` | 成就名在 Steamworks 后台预先定义；`storeStats` 才真上传 |
| **Steam Cloud 存档** | `Steam.fileWrite(path, bytes)` / `fileRead(path, size)` / `fileExists(path)` | M5 SaveSystem 改写到 Steam 路径（与本地存档可双写防丢） |
| **Steam Input** | `Steam.activateActionSet(handle, set)` + action API | Steam Deck 控制器映射；现 UI 全鼠标，需 Steam Input action 抽象层 |
| **持久化 Stats**（可选）| `Steam.setStatInt(name, value)` | Run 总数 / 总通关数 / 总胡牌数等数值统计 |

### v1.1+ 推荐

| 功能 | API | 备注 |
|---|---|---|
| **Workshop**（玩家 mod） | `Steam.createItem` / `submitItemUpdate` | 玩家上传 starter pack / Boss / skill；Phase 3 才考虑 |
| **Trading Cards / 表情**（不需要 API）| (Valve 后台配置) | 玩家收集 → 兑换徽章 |
| **Friends / Presence** | `Steam.getFriendCount` / `setRichPresence` | 显示好友在玩什么；联机时有用 |
| **Leaderboards** | `Steam.findLeaderboard` / `uploadLeaderboardScore` | Run 用时 / 最高分排行榜 |

### Phase 2 联机（可选）

| 功能 | API | 备注 |
|---|---|---|
| **Steam Networking Sockets** | `Steam.createListenSocketP2P` / `connectP2P` | P2P 建连，省后端服务器；适合 4 人 PvP 对战 |
| **Steam Lobbies** | `Steam.createLobby` / `joinLobby` | 房间匹配 |

## 二、集成步骤（GDExtension 方案）

### Step 1：环境准备（半天）

1. 注册 Steamworks 账户（$100，独立流程；用户操作；审核 ~1 周）
2. 在 Steamworks 后台申请 AppID（可拿到测试用 AppID 480 = Spacewar 先 dry-run）
3. 下载 Steamworks SDK（v1.64 与 GodotSteam 4.18.1 对齐）

### Step 2：插件接入（半天）

1. 从 Codeberg 下载 GodotSteam 4.18.1 GDExtension 预编译 binary（zip/tarball）
2. 解压到 `godot/addons/godotsteam/`（含 `.gdextension` 配置 + `.so` / `.dylib` / `.dll`）
3. 项目编辑器启用插件
4. 在 `project.godot` 加 autoload `Steam`（GDExtension 全局类）

### Step 3：smoke test（半天）

1. 主入口（`scenes/wechat_login_final.tscn` or 新 `boot.gd`）调 `Steam.steamInit()`
2. 验证返回 status code（1 = OK）
3. 用 SteamAppID 480 dry-run，确认 `Steam.getPersonaName()` 返回 Steam 用户名
4. GUT 测试：mock SteamAPI 返回 stub（生产代码用 `if Steam.is_steam_running()` gate；测试 fake）

### Step 4：成就 + 云存档（1-2 天）

1. **成就**：先列 30-40 个候选（baseline 13 章节通关 / Boss 击杀 / yaku 收集 / starter 通关 / Run 速度等）→ Steamworks 后台定义 → BattleEvent 钩子 emit `Steam.setAchievement(name)`
2. **云存档**：M5 `SaveSystem` 加 `STEAM_USER_DATA` 路径，写入时双写（local + cloud），读取时 cloud 优先

### Step 5：Steam Input 控制器映射（1-2 天）

- 列出现 UI 所有交互点（节点选择 / 商店 / 立直按钮 / 弃牌选择 / 等等）
- Steam Input action 定义（StickMove / ButtonA / ButtonB / DPad）
- UI focus 系统改造（鼠标 + 键盘 + 控制器三路输入）

### Step 6：build 上传（半天）

- `steamcmd` + depot 配置
- `default` branch / `beta` branch / `internal` branch（review / 测试用）
- 一键脚本：`scripts/steam_release.sh` (Godot export → steamcmd upload)

## 三、风险与缓解

| 风险 | 缓解 |
|---|---|
| GodotSteam 4.18.1 与 Godot 4.6.2 二进制 ABI 不完全兼容 | 先用预编译 binary smoke test；不行就降到上一个稳定版（如 4.17 / Godot 4.5.x）|
| Steamworks SDK 1.64 → 1.65 时 GodotSteam 可能滞后 | 锁版本 + 不主动升级 SDK；release time 同步 |
| Steam Deck Linux ARM 不支持 | GodotSteam 支持 Linux x86_64；Deck 用 Proton 跑 Win 版本反而最稳 |
| GDExtension 调用 SDK 时崩溃（空 SteamClient 句柄）| 所有 Steam.* 调用前 gate `if Steam.is_steam_running()` |
| Codeberg 仓库可访问性 / mirror | clone 后存 git submodule 或 vendored；不依赖 upstream 永远可访问 |

## 四、与本项目代码的接触面

按文件 / 模块预估改动：

| 模块 / 文件 | 改动 | 工时 |
|---|---|---|
| `project.godot` | 加 autoload `Steam` + 启用 GDExtension | 0.5 hr |
| 新文件 `meta/steam_bridge.gd` | 封装 Steam.* 调用 + fake gate | 2 hr |
| `meta/save_system.gd` | M5 现存档逻辑加 cloud 路径 | 4 hr |
| `meta/run_state.gd` 调用方 | 成就 emit 钩子（章节通关 / Run 完成）| 2 hr |
| `battle/skill_scheduler.gd` 或 hook 层 | 成就 emit 钩子（首次役满 / 国士无双 etc）| 4 hr |
| 新文件 `meta/achievements.gd` | 成就名常量 + emit 函数表 | 2 hr |
| 新文件 `addons/godotsteam/*` | 插件本体（zip 解压）| 0 |
| 测试 `tests/meta/test_steam_bridge.gd` | mock + smoke | 4 hr |

**总工时**：~3-4 天（不含 Steam Input 控制器映射 + build pipeline）；含全部 ~6-8 天。

## 五、关键开放问题

1. **预编译 binary or 自 build**：用 v4.18.1 release zip 是最简，但要确认是否包含 GDExtension 版本（vs Module 版本）
2. **Godot 版本**：当前 spec 说 Godot 4.5；GodotSteam 4.18.1 锁 4.6.2。需要本项目升 Godot → 4.6.2 一并测
3. **测试策略**：Steam.* 调用在 GUT headless 不可用（无 Steam 客户端）；需 fake / mock 层；用 `if OS.has_feature("steam")` 还是注入 service？
4. **国区 Steam vs 国际 Steam**：v1 先国际；GodotSteam 不区分，但 Steamworks 账户是分开的
5. **隐私 / 法务**：Steam Cloud 存档涉用户数据 — Steam 隐私政策已覆盖；额外 EULA 写不写？

## 六、与 steam-readiness D-list 的对接

| D-item | 本 spike 影响 |
|---|---|
| D2 GodotSteam 集成 | ✅ 路径已定（GDExtension + 预编译 binary）|
| D3 Steamworks 注册 + AppID | 用户操作（异步等审核） |
| D4 成就列表 30-40 个 | 待 brainstorm；本项目天然钩子充足 |
| D5 Steam Cloud 存档迁移 | 4 hr 工作量，M5 现存档基础完整 |
| D7 Build 上传流水线 | steamcmd 脚本 + depot 配置；半天 |
| D8 Steam Deck 控制器映射 | 1-2 天；UI focus 系统改造是大头 |

## 七、不在本 spike 范围

- 法务 / EULA / 隐私 / 数据合规（独立流程）
- 国区版号申请（不是 Steam 直接控制）
- Trailer / 截图 / 商店页素材（美术 / 文案）
- Steam P2P 联机（Phase 2 联机骨架另行 brainstorm）
