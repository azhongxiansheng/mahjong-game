# Windows Alpha 打包与首次说明（#258 / E7-04）

> 状态：工程交付规格。
> **网络端到端未验证。**
> 真实 Windows 10/11 x64 clean smoke、真实麦克风、公网整场仍待真机。

## 出口形态

- **未签名 ZIP**：`dist/windows-alpha/MahjongGame-windows-x86_64-alpha.zip`
- **不**要求 Microsoft Store，**不**要求代码签名
- 解压目录清晰：`MahjongGame.exe` + `MahjongGame.pck` + `README-Windows-Alpha.txt`
- **SmartScreen / 来源未知**：未签名 Alpha 的预期风险

## 官方导出依据

- Godot **4.6.1** `godot --headless --path godot --export-release "Windows Desktop" <path>`
- 预设：`godot/export_presets.cfg`
  - platform `Windows Desktop`
  - `export_filter="exclude"`（导出全部资源减去 denylist）+ `export_files` 精确排除破损 legacy 与 `main.tscn`（会拖入 `game_ui`）
  - `exclude_filter` 通配：`tests/*`、`addons/gut/*`、`tools/asset_gen/*`、`scenes/*` 等
  - 不用 `scenes`-only：EditorFileSystem 对 `lobby_shell.gd` 的 `preload(lobby_stage.tscn)` 依赖登记不完整，scenes 模式会得到不可运行的极小 PCK（已实测 ~153KB）
  - 不以修复/删除 legacy 通过门禁；denylist 排除即可
  - `binary_format/architecture=x86_64`，`codesign/enable=false`，`binary_format/embed_pck=false`
- 导出日志门禁：含 `SCRIPT ERROR` / `Parse Error` / `Compile Error` / `Failed to load script` 即失败（即使 exit 0）
- **权威导出清单**：export 日志 `Storing File:` 行（不得含 tests/gut/asset_gen/legacy 入口）
- 说明：PCK 内 `global_script_class_cache.cfg` 可能嵌入全仓 class 路径字符串，**不能**用裸 `strings` 误判为已打包 tests
- 文档：
  - https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_windows.html
  - Godot 4.6-stable 导出源码

## 包内容边界

**必须包含**：可运行 exe、pck、必要原生依赖。

**禁止入包**：

- 包顶层 `.godot` 工作缓存、`tests/`、`addons/gut/`
- 业务源代码工作副本、临时文件
- whisper / ggml 大模型（生产参考体积 **487601967** 字节）
- 破损 legacy：`scripts/game_ui.gd`、`card_tile.gd`、`hand_display.gd`、`main_simple.gd`

模型运行时路径（#245）：`user://models/whisper/<version>`。

说明：Godot 导出过程中可能在工程侧使用 `.godot/imported` / `.godot/exported` 作为**转换缓存**，不得与 **ZIP 包顶层** 工作缓存混淆；验收以 ZIP 布局 + PCK 内部路径为准。

## 首次应用内说明（仅 Windows 运行时）

Windows 原生防火墙 / 麦克风弹窗**不保证**出现。

| 时机 | 语义 |
|------|------|
| 首次确认公共匹配 Intent（`PUBLIC_CASUAL`）且 Windows | 仅出站；防火墙仅允许所需网络；SmartScreen 风险 |
| 首次 PTT 且 Windows | 隐私允许桌面应用麦克风；模型按需下载 + SHA-256；不随包内置 |

- **macOS / Linux**：不显示、不 ack、不消费 Windows flag（避免污染 #257）
- 持久化键（`user://settings.json`，Windows 专属命名）：
  - `windows_first_public_connect_notice_acked`
  - `windows_first_ptt_notice_acked`
- 实现：`godot/platform/platform_first_use_notices.gd`（**无** `class_name`，调用方 `preload`）
- 入口：`LobbyShell` / `PlayableTable`

## 脚本

| 脚本 | 作用 |
|------|------|
| `scripts/package_windows_alpha.sh` | 模板 → import/export 日志门禁 → stored-files → ZIP |
| `scripts/windows_alpha_contract_test.sh` | 静态契约（含 PS1 早退非零 FAIL / 结构化证据 / 严格顶层布局） |
| `scripts/windows_clean_smoke.ps1` | **Windows 真机规范入口** |
| `scripts/windows_clean_smoke.sh` | 非 Windows **NOT_RUN** / 转发；**不**冒充真机通过 |

### PowerShell smoke 规则

1. **ZIP**：`Get-FileHash -Algorithm SHA256` 计算当前包哈希，写入 smoke report。
2. **严格布局**：解压后恰 1 个顶层目录 `MahjongGame-windows-x86_64-alpha/`；内含 exe/pck/README；可有必要 DLL；禁止 tests/gut/.godot/model 与未知工作副本文件。
3. **启动观察 / early-exit 规则**（默认 15s）：
   - 观察窗口内 **非零退出（early non-zero）→ exit 1 FAIL**（不得当成功）
   - 观察窗口内 **exit 0** → 启动观察通过
   - **存活至超时** → 启动观察通过，并 **精确 Stop-Process 该 PID**
4. **结构化 structured EvidenceFile（JSON）**：未提供或不合格 → **exit 3 PENDING**。exit 0 前必须：
   - `zip_sha256` 与脚本对本 ZIP 的 `Get-FileHash SHA256` **完全一致**
   - `windows_version` 与脚本本机采集值 **规范化后严格相等**（折叠空白、小写；不能只判非空）
   - `timestamp_utc` 可解析为 `DateTimeOffset`，且带 `Z` 或 `±HH:MM` 时区
   - `operator` 非空
   - 下列项均为 `ok: true` 且含非空 `note`（或 `evidence_path`）：
     - `clean_profile`
     - `first_public_connect_notice`
     - `first_ptt_notice`
     - `firewall_behavior`
     - `real_microphone`
     - `model_resume_and_sha256`
     - **`public_match_complete`**（**完整牌局**至最终结算，不是一手/一局 hand）
   - **拒绝**旧字段 `public_match_full_hand` 与四裸 token（MIC_OK 等）
   - smoke report 记录 `evidence_file_sha256` 便于复核

`public_match_complete.note` 必须记录：房间/场次标识、东风或半庄、从开始到最终结算完成；禁止只描述单手/单局而无整场结算。

```powershell
powershell -ExecutionPolicy Bypass -File scripts\windows_clean_smoke.ps1
powershell -ExecutionPolicy Bypass -File scripts\windows_clean_smoke.ps1 `
  -EvidenceFile .\evidence.json -ReportPath .\smoke-report.json
```

evidence.json 示例：

```json
{
  "zip_sha256": "<must match Get-FileHash of current ZIP>",
  "windows_version": "Windows 11 23H2 (build 22631)",
  "operator": "qa@example",
  "timestamp_utc": "2026-07-26T00:00:00Z",
  "clean_profile": { "ok": true, "note": "new Windows user profile" },
  "first_public_connect_notice": { "ok": true, "note": "dialog shown once; cancel then confirm" },
  "first_ptt_notice": { "ok": true, "note": "dialog before first PTT" },
  "firewall_behavior": { "ok": true, "note": "prompt appeared / did not; action taken" },
  "real_microphone": { "ok": true, "note": "PTT captured real device" },
  "model_resume_and_sha256": { "ok": true, "note": "interrupt resume + SHA pass" },
  "public_match_complete": {
    "ok": true,
    "note": "room_id=pub-east-1 round=东风 started→final settlement complete"
  }
}
```

`windows_version` 必须等于该机 smoke 脚本打印的本机版本字符串（规范化后一致）。
`timestamp_utc` 示例：`2026-07-26T00:00:00Z`（必须含时区）。

## 验证分层

1. **本机交叉**：契约、import、真实 export 日志错误模式 0、stored-files、GUT 受影响模块。
2. **真机 Windows**：仅 `.ps1`；无结构化证据不得声称通过。
3. 任何网络相关交付均声明：**网络端到端未验证**。
4. macOS 静态契约**不能**实际执行 Windows EXE 早退分支；该分支以 PS1 源码门禁约束。

## 非目标

- #257 macOS Alpha
- #259 四端最终验收
- 代码签名与 Store 上架
