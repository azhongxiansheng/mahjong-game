# Issue #369 Phase 1 牌桌视觉 prototype

本目录只用于 1600×900 独立视觉验证，不接入 `PlayableTable` 或生产默认
渲染入口。截图只保留桌体、中央物理盘和麻将实体，不包含标题、分数、操作带或
其他 HUD。

## A：生产 `Tile3D` 单牌

`tile_pose_lab_369.tscn` 直接实例化生产 `Tile3D`，验证用户确认的
`72 × 98 × 56` 牌体。既有调用方仍默认使用 `34 mm` 厚度，#369 通过
`APPROVED_TILE_D` 显式选择 `56 mm`：

- 正面、背面、横置、盖牌、两层牌山、立直、被鸣横牌、加杠和暗杠；
- 青绿牌底占厚度 `1/2`，外轮廓 `R7.2`，嵌入边线 `0.65 mm`；
- 同尺寸实例共享纯几何 `ArrayMesh`，材质全部使用实例 surface override；
- `set_tile_visual()` 保留动作 `tile_instance_id`，`set_tile_skin()` 可替换
  牌面覆盖、牌背与牌胚材质；
- 默认皮肤为
  `ui/four_player_table/table3d/skins/qinglan_weave.tres`，牌面继续走仓库
  真实 `TextureExtractor` 加载链。

姿态实验截图：

```bash
godot --path godot \
  -s res://examples/table_2_5d_reference/capture_tile_pose_lab_369.gd
```

仓库内 `tile_pose_lab_369.png` 为真实 1600×900 RGB 原图。

## B：正方牌桌组合

`table_3d_prototype_369.tscn` 使用一个 1600×900 `SubViewport`、一个
`Camera3D` 和同一生产 `Tile3D` 组成牌桌：

- 桌面为 `2.40 × 2.40` 正方形；四席手牌、牌山、牌河和副露从同一南席
  局部坐标逐席旋转 `90°`，不做按主镜头歪斜实体或逐张屏幕补偿；
- 四边各 `17` 墩 × 两层，共 `136` 张真实牌山；所有实体 `scale=1`，
  上下层和桌面零间隙接触；
- 牌河常态为 `6/6`，压力态为 `6/6/6`；每席一张立直牌由同一实体追加
  `90°` 旋转；
- 副露直接消费 `MeldLayout.compute()`，覆盖吃、碰、大明杠、暗杠和加杠；
  被鸣牌真实横置、暗杠两端物理盖牌、加杠沿厚度轴接触叠放；
- 拥挤态中南席两组副露对应 7 张暗手，其余三席一组副露对应 10 张暗手。
  它是 `controlled_layout_stress`，不是合法牌局快照。

桌布使用原创低反光青绿程序化细织纹，不直接复用带龙、云、山、花具体纹样的
`assets/table_felt.png`。木框为单一连续 `FrameRing`，截面包含内斜面、抬高
顶冠、外倒角和下沉侧壁；木纹按同一实体坐标连续采样，不再由四根平面 Rail
拼接。它只抽象复用仓库 2D `TableStage` 的深红木基色、暗缝、细木纹与暖高光
层次，不复制第三方桌面资产或像素布局。

## 真实截图与诊断视角

主镜头四阶段：

```bash
MAHJONG_369_TABLE_PHASE=crowded \
MAHJONG_369_TABLE_VIEW=main \
godot --path godot \
  -s res://examples/table_2_5d_reference/capture_table_3d_prototype_369.gd
```

`MAHJONG_369_TABLE_PHASE` 支持 `hands / opening / midgame / crowded`。
`MAHJONG_369_TABLE_VIEW` 支持 `main / top / south / east / north / west`。
`top` 与四席视角只用于仓库外 `/tmp` 几何诊断：俯视证明正方、间距和旋转
对称；四席视角分别检查左右摆位、遮挡和接触。仓库只保留最终确认的主镜头原图。

仓库内 `table_3d_prototype_369.png` 是用户确认后的 crowded 主镜头，保持
1600×900 RGB 原始输出；诊断视角与局部裁切不入库。

雀魂、NaoMahjong 与 Majiang 只作为牌山、牌河、副露的空间语法和状态覆盖
参考；未复制其资产、角色、Logo、控件、专有纹样或像素布局。
