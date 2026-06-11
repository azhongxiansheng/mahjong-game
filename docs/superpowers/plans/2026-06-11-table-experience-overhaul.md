# 牌桌体验重做 — 实施计划(T1-T5)

> Spec:`docs/superpowers/specs/2026-06-11-table-experience-overhaul.md`。
> 顺序按「性价比 × 风险隔离」排:T1/T2 不动架构纯增量;T3 改桌面但保接口;
> T4 重排现有结算;T5 动渲染架构,放最后。每个 T 独立可交付、可单独验收。

## T1 宣告演出系统(G1)— 预计 1 个工作单元

**新文件** `godot/ui/four_player_table/call_announce.gd`(`class_name CallAnnounce extends Control`):

- `static func play(parent, kind: StringName, seat_id: int, avatar_tex) -> CallAnnounce`
  kind ∈ chi/pon/minkan/ankan/added_kan/riichi/tsumo/ron/yakuman。
- 三层结构(全 Control,挂 caller 给的 overlay 层,z_index 200,mouse_filter IGNORE):
  1. 大字 Label:书法字体 80px(胡 104px),`label_settings` outline 8px 按 kind 配色
     (DT 新增 ANNOUNCE_* tokens),Anima `slide` 从座位方向位移入场
     (seat 0 底/1 右/2 顶/3 左,位移 24-32px,0.5s cubic-bezier(.16,1,.3,1) 等价 easing)。
  2. 光晕:同字 Label 放大 1.06 + 金白色低透明度 + blur(Godot 用 8 份偏移叠影或
     BackBufferCopy+shader;v1 先用 3 层错位淡色字模拟,够用)。
  3. 冲击波:圆环 `_draw` 圆弧 + Tween scale 1→4 / alpha 1→0,0.75s。
- 头像:160px 圆形裁切(shader 或 mask),与大字同步 slide。
- 总时长 1.2s 后自毁(单元测试断言无孤儿)。
- **字体**:下载 Ma Shan Zheng(马善政,OFL)→ fontTools 子集化到宣告字集
  (吃碰杠立直自摸荣和役満流局倍跳满贯天地国士十三幺七对清一色字牌+数字)
  → `assets/fonts/MaShanZheng-Announce.ttf`(预计 <500KB)。
- **接线**:`playable_table._handle_event_dramatic` 在 PLAYER_ACTION(chi/pon/kan)、
  RIICHI_DECLARED、TSUMO_DECLARED、RON_DECLARED 分支调 CallAnnounce.play;
  对应 toast 文案降级移除(toast 保留流局/技能等次要信息)。
- **F6 手测场景** `tests/scenes/table/call_announce_test.tscn`:按键逐个预览 9 种 kind。
- GUT:`tests/ui/test_call_announce.gd` — play 后节点存在、1.5s 后自毁、kind 配色映射。

## T2 单牌状态系统(G2)— 预计 1 个工作单元

`card_tile_back.gd` 加状态 API(全部默认 false,bind 后由 caller 标记):

- `set_dora(bool)`:叠加 TextureRect 斜向渐变遮罩,AnimationPlayer/Tween 循环
  translate(-140%→140%,2.4s)。只对 face_up 牌生效。
- `set_lifted(bool)`:现有 hover 抬起基础上加 2px 金圈(draw 描边)+ 投影。
- `set_hover_match(bool)`:蓝色半透明蒙版(#3c8cbe66)。
- `set_win_tile(bool)`:scale 脉冲循环(Anima heartbeat 0.9s)。
- `set_dim(bool)`:modulate 0.45 灰(注意与"modulate 必须 WHITE"约束兼容——
  dim 用叠加 ColorRect 遮罩实现,**不动 modulate**)。
- **接线**:
  - SeatPanel 手牌行:bind 时对照 `state.dora_indicators` 实牌集合标 dora;
    `player_card_clicked` 悬停信号扩展 hover_match(SeatPanel 内同 id 标记,
    v1 只做自家手牌内联动,全桌联动随 T5 增量化再开)。
  - DiscardRiver:最新弃牌已有描边,改为 glow 衰减(Tween modulate 叠加层)+
    dora 标记。
  - 吃牌选择模式(`_pick_chi_companions_interactive`):候选牌外全部 set_dim,
    选完/取消恢复。米 spec AC-G2-c。
- GUT:`tests/ui/test_tile_states.gd` — 状态互斥/叠加正确、dim 不改 modulate、
  全量 rebind 后 caller 重标流程。

## T3 桌面舞台重做(G3)— 预计 2 个工作单元

1. **桌面纹理烘焙** `tools/asset_gen/bake_table_felt.py`(PIL):
   - 毛毡:#1f5132 底 + 高斯噪声 ×2 octave + 中心 radial 提亮 + 暗角 → `assets/table_felt.png` 1280×800。
   - 木护栏:左右 130px 竖条木纹渐变(#4e1d11→#0e0402)+ 2px 暖白高光线 → `assets/table_rail_{l,r}.png`。
   - FourPlayerTable 背景换装(TextureRect 三件套,替代现 mahjong_table_bg)。
2. **中心盘重做** `center_info_panel.gd`:
   - 200×200 圆角深蓝面板(StyleBoxFlat 渐变近似:顶部高光线 + 金边)。
   - 四边:各家分数(tabular 数字 + 自风字)按座位旋转排布;立直时该边亮
     金条+红点(`center-stick--on` 等价:6×70 ColorRect + 8px 红圆 + 发光)。
   - 中央:局数大字 + 本场/墙余小字 + dora 指示牌行(保留现有)。
   - 分数从 SeatPanel 移入中心盘后,SeatPanel 分数标签移除。
3. **SeatPanel 瘦身**:
   - 删 240×100 Bg 色块;保留:头像(56px 圆形裁切)+名字+段位风位小字,
     横向轻条贴桌边;furiten/tenpai/ippatsu 徽章挪到头像旁。
   - ActiveGlow 改为头像金色描边圈 + 呼吸(替代整框金边)。
   - **接口不变**:bind_seat/set_active/set_emote/say_for_event/set_hand_clickable
     签名保持,内部重画。手牌行(自家)从 SeatPanel 拆出独立定位贴桌底,
     尺寸 40×60→48×68。
4. 对手手牌侧视:`bake_tile_sides.py` 生成左/右/上三向侧视牌背 PNG(白面薄边+
   绿背渐变,272×389 同契约),CardTileBack back 模式按 seat 选贴图。
- 验收:capture_screens 截图对比 + 现有 GUT UI 测试全绿 + 新增布局断言测试。

## T4 结算编排(G4)— 预计 1 个工作单元

`playable_table._show_hand_result_overlay` 重排:

1. 役列表:整段 Label → VBox 逐条 Label,Anima `stagger_in`(fade_in_left,
   0.26s/条 0.08 错峰),每条「役名 …… N 飜」两端对齐。
2. 分数滚动:`detail` 中得分数字拆独立 Label,Tween `set_text` 0→target
   (0.6s,quad_out;is-up 金辉光/is-down 红辉光 = font_color + shadow)。
3. 点击任意处跳过:已有 overlay gui_input 关闭逻辑前置一个「未播完→先到终态」
   状态机(`_sequence_done` flag)。
4. win-announce(T1 的 ron/tsumo/yakuman kind)在 overlay 弹出前播,popin 延后
   0.5s 衔接。
- GUT:逐条入场节点计数、跳过到终态、分数终值正确。

## T5 发牌动画 + 河增量更新(G5)— 预计 2 个工作单元,风险最高

1. **DiscardRiver 增量化**:`set_tiles` 改 diff:只 append 新弃牌节点/只在
   riichi index 变化时旋转既有节点;新牌入场动画(从该家手牌方向 24px 位移
   + glow 衰减)。保留 `rebuild()` 全量路径做 fallback(状态不一致时)。
2. **SeatPanel 手牌行增量化**(仅自家):摸牌位单独节点滑入;切牌后排序重排
   用 Anima Grid/Nodes 位移过渡。
3. **发牌演出** `deal_animation.gd`:GAME_BEGIN 时 52 张牌背从中心按 4×13 序
   飞向四家(每张 0.04s 错峰,总 ~2.2s),期间真手牌 visible=false;
   SettingsManager 加 `skip_deal_animation` 开关。
4. 回归防线:全套 GUT + 10 seeds e2e(现有 test_10_seeds_with_full_skills)+
   capture_screens。

## 里程碑顺序与提交纪律

- 每个 T 一个(或两个)commit,自带测试与 F6 手测场景,全套 GUT 绿才进下一个。
- T1→T2→T3→T4→T5。T3 内部三步可拆分提交(纹理→中心盘→SeatPanel)。
- 每个 T 完成后 capture_screens 留档对比(/tmp/shot_*.png)。
