# #302 生产大厅视觉基线：朱红异能雀庄

## 核心构图

大厅不再由顶部栏、左右面板和等权文字按钮拼成。生产入口 `LobbyShell` 只保留
路由与弹层，所有可见内容由独立 `LobbyStage` 场景承担：

```text
LobbyStage（全幅 16:9 日式雀庄环境）
├─ EnvironmentBackdrop     批准的环境原图，全幅裁切
├─ CharacterStage          左侧大角色与少量紫色异能火
├─ TopResourceBar          玩家印、段位、资源、活动
├─ ModeBannerRail          三条横向牌匾，真实 Control 文字
├─ OmamoriRail             右侧六枚御守功能列
├─ StatusLabel             短状态提示
└─ BottomNav               角色化资料、规则与音频导航
```

角色与环境承担第一视觉层，玩法牌匾承担一级操作权重，顶部、单侧御守和底部导航
只占边缘。禁止恢复旧 `RootVBox/MainRow`、SaaS 卡片墙或暗色空背景。

## 色彩与材质

- 主色：朱红 `#C32617`、墨黑 `#0D0908`、暖米白 `#F7E5BC`。
- 异能色只取素材中的少量灵紫火焰，不把所有边框改成霓虹紫。
- 横幅与御守使用已批准 RGBA 素材表，通过 `AtlasTexture.region` 裁切；标题、
  说明和可访问性文本始终来自 Godot `Button/Label`，不把图片伪字当 UI。
- 角色生产 PNG 已在导入前完成 alpha matte、透明像素 RGB 与绿色边缘 despill；
  场景直接消费清理后的 RGBA，不用运行时 Shader 掩盖素材污染。

## 生产行为映射

| 舞台入口 | 既有生产行为 |
|---|---|
| 电脑练习 | `PRACTICE` 规则抽屉 |
| 公共匹配 | `PUBLIC_CASUAL` 规则抽屉 |
| 规则研习 | 既有规则资料馆；不伪造第三种对局模式 |
| 公告 / 帮助 / 设置 | 既有公开信号 |
| 角色 / 道具 / 规则御守 | 既有资料馆页面 |
| BGM / SFX | 既有音量弹层 |

三条牌匾和六枚御守根节点均为原生 `Button`，支持鼠标、键盘 focus、disabled 与
无障碍文本；内部图片和文字节点忽略鼠标输入。牌匾 hover/focus 只做可取消的
短促放大与提亮，pressed 不延迟业务信号。

## 资产与边界

生产舞台纳入四个已批准文件：环境、透明男性角色、三条横幅素材表、六枚御守
素材表。附属层另纳入一套无文字的大厅实体材质：漆木框、和纸面板、选择牌、
展开卷轴、木札、御守匣、滑杆轨道/滑块和朱印角饰。附属层通过
`StyleBoxTexture` 与真实 `Texture2D` 消费这些 RGBA 文件，不用纯色
`StyleBoxFlat` 冒充材质。

- 规则抽屉：保留既有 `SessionIntent`、互斥选择、焦点和返回契约，只把可见层
  重做为右侧漆木/和纸挂牌。
- 资料馆：保留真实 `LobbyCodexCatalog` 数据和三页入口，重做为角色舞台、
  木札名录、展开卷轴三层。
- 音量：保留真实 `SettingsManager`、两条 `HSlider`、试听和关闭契约，重做为
  右下御守匣。

生成原稿、青幕、QA contact sheet 与清理脚本只留在仓库外 staging；仓库只纳入
清理后生产 PNG。未新增插件，未复制第三方代码或 IP。#302 不重做牌桌 HUD、
对局规则、匹配流程或网络协议，也不提前实现持续环境动效与完整 SFX 收口。
