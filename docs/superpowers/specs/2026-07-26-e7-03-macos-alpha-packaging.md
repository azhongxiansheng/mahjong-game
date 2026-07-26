# E7-03（#257）macOS Alpha 打包与模型按需下载

> 状态：Alpha 交付说明。网络端到端未验证。不含 App Store、公证、Windows #258、四端最终 #259。

## 范围

- Godot **4.6.1** macOS **release** 导出预设 `macOS Alpha`（`godot/export_presets.cfg`）。
- Bundle id 稳定：`com.lovteam.MahjongGame`。
- **Built-in ad-hoc** 签名（`codesign/codesign=1`）；**禁止** Developer ID、企业证书、Apple 凭证与公证。
- `codesign/entitlements/audio_input=true`；`NSMicrophoneUsageDescription` 说明欢乐场「按住说话」用途。
- 包内含 Godot 运行时与项目资源；**不内置** `ggml-small.bin`（487,601,967 字节）或其它大模型 / partial。
- 当前仓库**无**生产 GDExtension；包不虚构 whisper 推理扩展依赖。

## 用户可见（仅 TRASH_TALK / 欢乐场）

右下角内联（无弹窗、无持久化「已读」）：

```text
麦克风仅在按住说话时启用
模型：下载中 37% / 校验中… / 就绪 / 失败，点此重试
        [🎙 按住说话]
```

- 进入欢乐场即显示用途说明；**仅 PTT 按下**才触发真实麦克风采集 / 系统授权。
- 模型 checking / downloading / verifying / ready / failed / cancelled 同区展示；失败不阻断牌局与 PTT。
- STANDARD / 标准场：零 PTT、零权限说明、零 model manager、零下载、不主动申请麦克风。

## Gatekeeper / 未公证限制

- ad-hoc 签名应用从浏览器下载后可能被 Gatekeeper 拦截。
- 本机验证可用：系统设置放行，或 `xattr -dr com.apple.quarantine /path/to/MahjongGame.app`（仅用户自愿）。
- **未**公证、**未** App Store 分发。

## 命令

```bash
# 契约（无导出）
scripts/e7_257_macos_export_contract_test.sh

# 安装 4.6.1 export template（如缺失）并导出到 /tmp/mahjong-e7-257-*
scripts/e7_257_macos_package.sh

# 干净目录风格 smoke：Info.plist / ad-hoc / 包内容无模型
scripts/e7_257_macos_package_smoke.sh

# 真实 ggml-small 下载 + SHA-256（隔离 /tmp/mahjong-e7-257-*）
scripts/e7_257_whisper_model_download_smoke.sh
```

所有 staging / 日志路径必须匹配 `/tmp/mahjong-e7-257-*`；**不得**清理或写入真实
Godot 4.6 macOS `user://` 路径：
`~/Library/Application Support/Godot/app_userdata/MahjongGame`
（smoke 以隔离 `HOME` 证明 fake 树写入，并对真实目录做只读快照对比）。

## 导出与 ETC2/ASTC

Godot 4.6.1 在导出 **universal / arm64** 时若未启用
`rendering/textures/vram_compression/import_etc2_astc`，导出失败并提示：
`Cannot export for universal or arm64 if ETC2 ASTC texture format is disabled.`
本仓库 `project.godot` 因此启用该开关；修改后须按 AGENTS.md 跑全量 GUT。

## macOS HF URL 解析运行依赖

Godot 内置 mbedtls 对 `huggingface.co` resolve 入口 TLS 握手可能失败，而最终 CDN
（如 `*.cdn.hf.co`）可成功。macOS 上 `WhisperModelManager` 用可 kill 的系统
`/usr/bin/curl` **子进程**（`OS.create_process` + `exec`，`--max-time 25`，stdout
写入 `/tmp/mahjong-e7-257-resolve-*.txt` 后由主线程轮询）仅解析最终 URL（不下载
body），再由 `HTTPRequest` 下载完整模型并做 Range/SHA/原子启用。

- **仅 macOS** 走此旁路；Windows 不调用 curl。
- 缺少 `/usr/bin/curl` 时回退原始 manifest URL 直连。
- cancel / release / 节点销毁（`PREDELETE`）对活跃解析进程立即 `OS.kill`，主线程
  **永不** `wait_to_finish` 等待网络 worker；token 使迟到结果作废且不发起模型 GET。
- 正式 #257 模型 smoke 必须用**导出** `MahjongGame.app`，不得用编辑器 `godot` 冒充。

## 生产模型清单（固定）

| 字段 | 值 |
|------|-----|
| filename | `ggml-small.bin` |
| size | `487601967` |
| sha256 | `1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b` |
| revision | `5359861c739e955e79d9a303bcbc70fb988958b1` |

实现：`WhisperModelManifest.production_small()` + `WhisperModelManager`（#245）；UI 绑定 `PlayableTable.bind_voice_from_battle`（#257）。

## 明确未验证 / 非目标

- **网络端到端未验证**（公网整场、四客户端、匹配连房不在本 Issue 闭环）。
- 真实麦克风授权/采集需要**可见人工操作**；headless smoke 不冒充已授权。
- 不含 Windows #258、四端最终 #259、App Store、公证。
