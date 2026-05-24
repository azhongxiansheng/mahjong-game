# Godot 生态框架/插件评估 — 2026-05-24

## 调研背景
项目当前(1670+ tests / 30+ PR polish)已完成日麻规则全栈、SFX/设置/统计/成就/教程/粒子/震动/HUD/splash/座位飘字/牌墙脉冲等商业级 polish。本文档评估是否引入 Godot 生态外部框架/插件,让项目"更专业",权衡 ROI。

## 评估清单(2026 年现状)

### 高知名度候选 — 已逐一审视

| 插件 | 用途 | 适用我们? | 决定 |
|-----|------|----------|------|
| **Beehave** (v2.10) | 行为树 AI | ❌ 不适合 | **不引入** |
| **Phantom Camera** (v0.10) | 镜头/震动/cinematic | ❌ 不适合 | **不引入** |
| **GdUnit4** | 单测/CI/HTML 报告 | ⚠️ 1670 tests 已在 GUT | **暂保留 GUT** |
| **Dialogue Manager (nathanhoad)** v4 | 分支对话 | ✅ 可选 | **观望** |
| **Dialogic 2.x** | 视觉小说级对话 | ⚠️ 重 | **不引入** |
| **Input Helper** | 输入重映射 | ✅ 价值小 | **观望** |
| **Quick Audio** | 音频总线管理 | ⚠️ 已有 AudioManager | **不引入** |
| **Godot Doctor** | 场景/资源静态验证 | ❌ 仓库 404 / 未维护 | **不引入** |
| **GodotSteam** | Steam 集成 | ⏳ 未发行前不需 | **后续** |
| **Cogito** | FPS 沉浸模板 | ❌ 不相关 | **不引入** |
| **GOAP** | 目标导向 AI | ❌ 我们是回合制 | **不引入** |
| **Jolt Physics** | 3D 物理 | ❌ 无物理需求 | **不引入** |

### 详细评估理由

**Beehave (behavior tree)**:tick-based 框架,设计给实时 NPC(巡逻/追击/攻击 状态机)。我们的 AI 是**一次性决策**(每回合摸/切/鸣/胡 各一次),决策树+评分函数更直接,改 Beehave 反而增加复杂度。SimpleAi / HeuristicAi 已稳定,**不动**。

**Phantom Camera**:Cinemachine 风格 Camera2D/3D 包装。我们整个 UI 走 Control 节点,不用 Camera。已自撸 ScreenShake (4 tier),够用。**不引入**。

**GdUnit4**:技术更先进(HTML 报告、并行执行、Mocking、JUnit XML),但 1670 个测全在 GUT 9.x 写,迁移成本极大(测试 API 不兼容),且 CI 已 work。**收益<成本,暂保留 GUT**;未来 net foundation 模块按 C# 重写时再考虑 GdUnit4Net(支持 VSTest)。

**Dialogue Manager** (nathanhoad/godot_dialogue_manager):v4 支持 Godot 4.6+。我们 EventNode 当前是 1-2 段静态文本,如果未来加 boss 大量对话 / 角色背景故事则有价值。**现阶段不引入**,做需求驱动决策。

**Input Helper**:键盘重映射。当前热键 D/H/ESC 已规约,玩家自定义键位是 nice-to-have 但不阻断商业化。**后续 polish 圈再决**。

**Godot Doctor**:仓库未找到(404),社区版本已停更或换名。**自撸**:写一个 `tests/health/test_scene_resources_load.gd` 扫所有 `.tscn` + `.tres` 确保可 load,达到同等效果。

---

## 决定:不引入第三方插件,改自研 "Pro 工具链"

社区调研后结论:**我们项目类型(回合制 UI 麻将+肉鸽)与主流 Godot 插件目标场景错位**。强行套用反而增加维护负担。代替策略 — **自研 3 个轻量级 "Pro" 内部工具**:

### 1. DebugOverlay (F3 toggle)
现状:无运行时调试观测点。  
方案:autoload `DebugOverlay`,F3 唤起浮动半透明 panel,实时显:FPS / battle state 摘要 / wall remaining / current_seat / phase / event_chain_depth / autoload 实例数。pro QA 工具。

### 2. SceneResourceHealthCheck (test 时跑)
现状:`.import` 缺失或 `.tscn` 引用断链只在启动时崩。  
方案:GUT 测试 `tests/health/test_scene_resources_load.gd` 扫所有 `res://` 下 `.tscn/.tres/.gd`,断言 `ResourceLoader.exists` + `load(...) != null`。CI 阶段一发 catch 漂移。

### 3. PerfBudget (test 时跑)
现状:无性能基准。  
方案:GUT 测试 `tests/perf/test_bc_runtime_budget.gd` 跑 100 局 BC.run_to_end,断言总时长 < 阈值。SIMple regression detector。

---

## 后续候选(此 PR 不做)
- **Dialogue Manager**:若 M9+ 加 boss 剧情对话则考虑
- **GodotSteam**:发行前装,加 Steam achievements 同步
- **GdUnit4Net**:net foundation C# 模块单独评估

---

## 参考资料
- https://github.com/godotengine/awesome-godot
- https://github.com/bitbrain/beehave (Beehave)
- https://github.com/ramokz/phantom-camera (Phantom Camera)
- https://github.com/nathanhoad/godot_dialogue_manager (Dialogue Manager)
- https://github.com/godot-gdunit-labs/gdUnit4 (GdUnit4)
