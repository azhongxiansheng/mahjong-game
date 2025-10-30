# 反编译代码深度分析 - FairyGUI 麻将游戏架构

## 目录
1. [整体架构](#整体架构)
2. [核心设计模式](#核心设计模式)
3. [场景管理系统](#场景管理系统)
4. [FairyGUI 使用方式](#fairygui-使用方式)
5. [纹理和精灵系统](#纹理和精灵系统)
6. [关键实现细节](#关键实现细节)
7. [与 Godot 的对比](#与-godot-的对比)

---

## 整体架构

### 技术栈
- **游戏引擎**: Cocos Creator (HTML5 Web Engine)
- **UI 框架**: FairyGUI
- **语言**: TypeScript
- **项目结构**: 单场景架构 + 多 UI 场景切换

### 核心文件结构
```
assets/
├── Script/
│   ├── GameMain.ts          ⭐ 主控制器 - 全局唯一
│   ├── MainScene.ts         🎬 Cocos 场景（空）
│   ├── FairyGUIManager.ts   🎨 FairyGUI 单例管理
│   ├── WeChatLoginScene.ts  🔐 登录场景
│   ├── PlazaScene.ts        🏛️ 游戏大厅
│   └── WaitingRoomScene.ts  🎲 等待房间 (游戏场景)
├── resources/
│   ├── mahjong_atlas0.png     (2048x2048)
│   ├── mahjong_atlas0_1.png   (1024x1024)
│   ├── mahjong_atlas0_2.png   (2048x2048)
│   └── mahjong.bin            (FairyGUI 精灵定义文件)
└── ui/
    ├── Package1_atlas0.png
    └── Package1.bin
```

---

## 核心设计模式

### 1️⃣ **单例模式 + 场景管理**

```typescript
// 🎮 GameMain - 唯一的 Cocos 场景组件
export default class GameMain extends cc.Component {
    private wechatLoginScene: WeChatLoginScene = null;
    private plazaScene: PlazaScene = null;
    private waitingRoomScene: WaitingRoomScene = null;
    private currentScene: any = null;

    // 所有场景通过 window.gameMain 的方法切换
    public showWelcome() { }      // 显示登录
    public showPlaza() { }         // 显示大厅
    public showWaitingRoom() { }   // 显示游戏房间
}
```

**关键点:**
- ✅ GameMain 本身是 Cocos 的唯一场景（`MainScene.ts` 为空）
- ✅ 所有 UI 都在 FairyGUI 的 `GRoot` 中创建和管理
- ✅ 避免 Cocos 场景切换导致的 GRoot 销毁问题
- ✅ 通过 `window.gameMain` 全局访问

### 2️⃣ **非继承 Component 的 Scene 类**

```typescript
// ❌ 不继承 cc.Component
// ✅ 直接作为 UI 管理类
export default class WaitingRoomScene {
    private view: any = null;          // FairyGUI 对象
    private players: { [key: string]: PlayerData } = {};

    public init(): void {
        const fgui = window.fgui;
        fgui.UIPackage.addPackage('mahjong');  // 加载 UI 包
        this.createView();                      // 创建视图
        this.initUI();                          // 初始化组件
    }

    public show(): void {
        fgui.GRoot.inst.addChild(this.view);    // 显示视图
    }

    public hide(): void {
        this.view.removeFromParent();           // 隐藏视图
    }
}
```

**为什么这样设计？**
- ✅ FairyGUI 的 `GRoot` 需要在整个应用生命周期存活
- ✅ 如果每次场景切换都销毁 GRoot，就丢失了所有 UI 状态
- ✅ 所以改为：**1 个 Cocos 场景 + 多个 FairyGUI UI 视图**

---

## 场景管理系统

### 生命周期流程

```
GameMain.onLoad()
  ↓ (延迟 500ms，确保 FairyGUI 加载)
GameMain.start()
  ↓
创建/初始化 GRoot (全局唯一)
  ↓ (延迟 200ms)
加载所有资源 cc.loader.loadResDir()
  ↓ (延迟 100ms)
显示欢迎界面 GameMain.showWelcome()
  ↓
用户登录成功
  ↓
GameMain.showPlaza() 
  ↓
用户创建房间 / 进入房间
  ↓
GameMain.showWaitingRoom()
  ↓
所有玩家准备
  ↓
开始游戏 (TODO)
```

### 场景切换的关键代码

```typescript
// showPlaza() 的实现
public showPlaza(): void {
    this.hideCurrentScene();              // 隐藏旧场景
    
    if (!this.plazaScene) {
        this.plazaScene = new PlazaScene();
        this.plazaScene.init();            // 首次初始化
    } else {
        this.plazaScene.show();            // 重新显示
    }
    
    this.currentScene = this.plazaScene;
}

// hideCurrentScene() 的实现
private hideCurrentScene(): void {
    if (this.currentScene && this.currentScene.hide) {
        this.currentScene.hide();          // 隐藏当前场景
    }
}
```

**设计优势:**
1. ✅ 一次性创建，需要时显示/隐藏 (不销毁)
2. ✅ 状态保留 (玩家数据在内存中)
3. ✅ 切换流畅 (无重新初始化)
4. ✅ GRoot 始终存活 (UI 框架完整)

---

## FairyGUI 使用方式

### FairyGUI 初始化流程

```typescript
start() {
    setTimeout(() => {
        const fgui = window.fgui;
        
        // 1️⃣ 创建全局根节点 (只创建一次)
        if (!fgui.GRoot.inst) {
            fgui.GRoot.create();
        }
        
        // 2️⃣ 等待初始化完成
        setTimeout(() => {
            // 3️⃣ 加载所有资源
            cc.loader.loadResDir('', (err, assets) => {
                // 4️⃣ 显示 UI
                this.showWelcome();
            });
        }, 200);
    }, 500);
}
```

**关键点:**
- ✅ GRoot 是 FairyGUI 的全局唯一根容器
- ✅ 必须在所有 UI 操作之前创建
- ✅ 需要延迟确保 SDK 完全加载
- ✅ 一旦创建，在整个应用生命周期保持活跃

### 创建 UI 对象

```typescript
private createView(): void {
    const fgui = window.fgui;
    
    // 1️⃣ 添加 UI 包 (mahjong.bin 中的定义)
    fgui.UIPackage.addPackage('mahjong');
    
    // 2️⃣ 创建 UI 对象
    this.view = fgui.UIPackage.createObject("mahjong", "WaitingRoomLayer");
    
    // 3️⃣ 获取子组件
    const readyBtn = this.view.getChild("btn_ready_bg");
    const playerText = this.view.getChild("player_east_text");
    
    // 4️⃣ 绑定事件
    readyBtn.onClick(this.onReadyClick.bind(this));
    
    // 5️⃣ 添加到 GRoot
    fgui.GRoot.inst.addChild(this.view);
}
```

**关键 API:**
| 方法 | 作用 |
|------|------|
| `UIPackage.addPackage(name)` | 加载 UI 包 (mahjong.bin + 纹理) |
| `UIPackage.createObject(pkg, name)` | 创建指定的 UI 对象 |
| `view.getChild(name)` | 获取子组件 (按名称) |
| `button.onClick(callback)` | 绑定按钮点击事件 |
| `GRoot.inst.addChild(view)` | 添加到屏幕 |

---

## 纹理和精灵系统

### 文件格式说明

#### 1. **mahjong.bin** (FairyGUI 包定义文件)
```
文件结构:
┌─────────────────────────────┐
│ Header (16 bytes)           │
│ - Magic Number (4)          │ 0x49555646 (FGUI)
│ - Version (4)               │
│ - PackageName (string)      │
├─────────────────────────────┤
│ Sprite Definitions          │
│ - Name (string)             │ e.g., "w1", "t5", "E"
│ - AtlasID (int)             │ 0, 1, 2 (指向 atlas0, atlas0_1, atlas0_2)
│ - X, Y, Width, Height (ints)│ 在 atlas 中的精确位置
│ - ... (更多精灵定义)        │
├─────────────────────────────┤
│ UI Components               │
│ - WaitingRoomLayer (定义)   │
│ - GameTableLayer (定义)     │
│ - ... (更多 UI 层定义)      │
└─────────────────────────────┘
```

#### 2. **mahjong_atlas0.png** (2048x2048)
```
包含所有麻将牌精灵:
┌──────────────────────────────────┐
│ Row 0: w1 w2 w3 ... w9 t1 ... s5 │
│ Row 1: s6 s7 s8 s9 E S W N Z F B │
│ Row 2: ...                       │
│ ... (共 23x23 个格子，每个 85x85) │
└──────────────────────────────────┘

精灵位置计算:
X = col * (TILE_SIZE + PADDING) = col * 86
Y = row * (TILE_SIZE + PADDING) = row * 86
Width = 85, Height = 85
```

### 精灵加载流程

```typescript
// 🎮 FairyGUI 内部的加载过程

// 1️⃣ 读取 mahjong.bin，解析所有精灵定义
const sprites = parseBinFile("mahjong.bin");
// sprites = {
//   "w1": { atlas: 0, x: 0, y: 0, w: 85, h: 85 },
//   "w2": { atlas: 0, x: 86, y: 0, w: 85, h: 85 },
//   ...
//   "E": { atlas: 0, x: 344, y: 86, w: 85, h: 85 },
// }

// 2️⃣ 加载 atlas 纹理
const atlases = [
    loadTexture("mahjong_atlas0.png"),     // 2048x2048
    loadTexture("mahjong_atlas0_1.png"),   // 1024x1024
    loadTexture("mahjong_atlas0_2.png"),   // 2048x2048
];

// 3️⃣ 当使用某个精灵时，从 atlas 中裁剪
function getTileTexture(tileName) {
    const spriteInfo = sprites[tileName];
    const atlas = atlases[spriteInfo.atlas];
    
    // 从 atlas 中截取指定区域
    return atlas.getRegion(
        spriteInfo.x,
        spriteInfo.y,
        spriteInfo.w,
        spriteInfo.h
    );
}
```

### 在 UI 中使用纹理

```typescript
// 在 FairyGUI 中使用精灵很简单:

// 1️⃣ 定义 UI (在 mahjong.bin 中已定义)
// 对应的 FUI 文件包含:
// - WaitingRoomLayer (UI 层)
//   - player_seats (玩家座位)
//     - player_east_image (图像组件)
//     - player_south_image
//     - ...
//   - table_layer (麻将桌)
//     - player_hand (玩家手牌)
//       - tile_1 (图像)
//       - tile_2 (图像)
//       - ...

// 2️⃣ 在代码中更新精灵
const tileImage = this.view.getChild("tile_1");
tileImage.source = "mahjong|w1";  // 使用 mahjong 包中的 w1 精灵
```

---

## 关键实现细节

### 1. **玩家管理**

```typescript
interface PlayerData {
    userId: string;           // 唯一标识
    nickname: string;         // 玩家昵称
    isReady: boolean;        // 准备状态
    position: string;        // 位置 (east, south, west, north)
}

// 存储方式: 对象字典 (兼容 ES5)
private players: { [key: string]: PlayerData } = {};

// 添加玩家
addPlayer(player) {
    this.players[player.userId] = player;
}

// 更新 UI
updatePlayerUI(player) {
    let textComponent = null;
    
    switch (player.position) {
        case "east":
            textComponent = this.playerEastText;
            break;
        // ... 其他位置
    }
    
    textComponent.text = `${player.nickname}\n${player.isReady ? "已准备" : "未准备"}`;
}
```

### 2. **事件系统**

```typescript
// FairyGUI 的事件绑定
const readyBtn = this.view.getChild("btn_ready_bg");
readyBtn.onClick(this.onReadyClick.bind(this));

// 回调函数
private onReadyClick(): void {
    this.isReady = !this.isReady;
    
    const currentPlayer = this.players["player_self"];
    currentPlayer.isReady = this.isReady;
    this.updatePlayerUI(currentPlayer);
    
    // 触发 AI 玩家准备
    this.triggerAIReady();
}
```

### 3. **异步管理**

```typescript
// 使用 setTimeout 实现异步延迟
// ✅ 确保初始化顺序

// 500ms: 等待 FairyGUI SDK 加载
setTimeout(() => {
    // 创建 GRoot
    fgui.GRoot.create();
    
    // 200ms: 等待 GRoot 完全初始化
    setTimeout(() => {
        // 加载资源
        cc.loader.loadResDir('', (err, assets) => {
            // 100ms: 等待 UI 准备
            setTimeout(() => {
                this.showWelcome();
            }, 100);
        });
    }, 200);
}, 500);
```

### 4. **屏幕适配**

```typescript
private createView(): void {
    const designWidth = 1280;   // 设计分辨率
    const designHeight = 720;

    const screenWidth = cc.winSize.width;     // 实际屏幕
    const screenHeight = cc.winSize.height;

    // 计算缩放比例 (保持宽高比)
    const scaleX = screenWidth / designWidth;
    const scaleY = screenHeight / designHeight;
    const scale = Math.min(scaleX, scaleY);  // 避免超出边界

    // 应用缩放和居中
    this.view.setScale(scale, scale);

    const finalWidth = designWidth * scale;
    const finalHeight = designHeight * scale;
    const x = (screenWidth - finalWidth) / 2 + finalWidth / 2;
    const y = (screenHeight - finalHeight) / 2 + finalHeight / 2;

    this.view.setPosition(x, y);
    this.view.setPivot(0.5, 0.5, true);      // 设置旋转中心

    fgui.GRoot.inst.addChild(this.view);
}
```

---

## 与 Godot 的对比

| 特性 | Cocos + FairyGUI | Godot |
|------|------------------|--------|
| **场景管理** | 1 个 Cocos 场景 + 多个 FairyGUI UI | 多个 Godot 场景 |
| **UI 框架** | FairyGUI (专业 UI) | Control + CanvasLayer |
| **精灵加载** | 从 .bin 文件定义裁剪 | 直接加载 Texture2D |
| **文本渲染** | FairyGUI 文本组件 | Label / RichTextLabel |
| **事件系统** | onClick, onStateChange | signal/connect |
| **协程** | setTimeout + Promise | async/await |
| **适配方案** | 手动计算缩放 | 使用 CanvasScaler |
| **性能** | 高 (专业引擎) | 高 (轻量化) |

---

## 在 Godot 中的实现策略

### 🎯 应该采用的模式

1. **单实例 TextureExtractor**
   ```gdscript
   class_name TextureExtractor extends Node
   
   # 全局唯一实例
   var extracted_tiles = {}  # {"w1": Texture2D, "w2": Texture2D, ...}
   
   func get_tile_texture(tile_name: String) -> Texture2D:
       return extracted_tiles.get(tile_name, null)
   ```

2. **非场景继承的 UI 管理类**
   ```gdscript
   class_name MahjongUIManager extends Node
   
   # 不处理游戏逻辑，只管理 UI
   var game_view: Control
   var player_displays: Array
   
   func init():
       create_ui()
       init_components()
       add_to_scene()
   ```

3. **集中的事件总线**
   ```gdscript
   class_name EventBus extends Node
   
   signal ready_state_changed(player_id, is_ready)
   signal all_players_ready
   signal game_started
   
   # 所有事件通过这里广播
   ```

### 🚀 下一步改进计划

1. ✅ 确保纹理正确加载和显示
2. ⏳ 实现类似 FairyGUI 的 UI 容器系统
3. ⏳ 创建高效的事件管理系统
4. ⏳ 添加屏幕自适应
5. ⏳ 实现游戏逻辑 (AI, 胡牌, 计分)

---

## 总结

**原始游戏的核心设计理念：**
- ✅ **单场景架构**: 避免 UI 框架重新初始化
- ✅ **模块化场景类**: 每个场景都是独立的 UI 管理类
- ✅ **全局 FairyGUI 管理**: GRoot 是全局唯一
- ✅ **精灵系统**: 通过 .bin 文件定义精灵坐标和映射
- ✅ **事件驱动**: 玩家交互 → UI 更新 → 逻辑处理

**Godot 实现的等价设计：**
- ✅ **单主场景 + 多个 UI 节点**
- ✅ **TextureExtractor 全局单例**
- ✅ **CardUI 负责单个牌的渲染**
- ✅ **HandDisplayManager 管理手牌显示**
- ✅ **GameController 驱动游戏逻辑**
