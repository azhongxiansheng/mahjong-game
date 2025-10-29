# 📖 Godot 官方文档精要总结

**基于**: Godot 4.5.1 官方文档  
**更新日期**: 2025-10-29  
**用途**: 快速参考和常见问题解决

---

## 🎯 目录

1. [核心概念](#核心概念)
2. [GDScript 常用方法](#gdscript-常用方法)
3. [场景和节点](#场景和节点)
4. [信号系统](#信号系统)
5. [物理和碰撞](#物理和碰撞)
6. [输入处理](#输入处理)
7. [常见难点](#常见难点)
8. [性能优化](#性能优化)
9. [网络编程](#网络编程)
10. [调试技巧](#调试技巧)

---

## 核心概念

### 1. 场景树结构
```gdscript
# Godot 的核心是场景树
# 每个节点都是一个对象，有生命周期方法

# 节点生命周期
_ready()           # 节点进入场景树时调用 (一次)
_process(delta)    # 每帧调用 (FPS 依赖)
_physics_process(delta)  # 物理帧调用
_exit_tree()       # 节点离开场景树时调用
```

### 2. 类的定义
```gdscript
# GDScript 4.x 中定义类
class_name MyClass        # 全局类名

extends Node              # 继承自 Node

# 构造函数
func _init() -> void:
    pass

# 虚函数覆盖
func _ready() -> void:
    pass
```

### 3. 类型系统
```gdscript
# GDScript 4.x 强类型
var count: int = 0
var name: String = "test"
var position: Vector2 = Vector2(10, 20)
var data: Dictionary = {}
var items: Array[int] = [1, 2, 3]  # 类型化数组

# 函数签名
func add(a: int, b: int) -> int:
    return a + b

# 可选返回值 (void 表示无返回)
func do_something() -> void:
    pass
```

---

## GDScript 常用方法

### 字符串方法
```gdscript
# 基础操作
var text = "Hello World"
text.to_lower()           # "hello world"
text.to_upper()           # "HELLO WORLD"
text.length()             # 11
text.substr(0, 5)         # "Hello"
text.split(" ")           # ["Hello", "World"]
text.replace("World", "Godot")  # "Hello Godot"

# 格式化
var formatted = "Count: %d, Name: %s" % [5, "test"]

# 判断
text.begins_with("Hello")  # true
text.ends_with("World")    # true
text.contains("o W")       # true
```

### 数组操作
```gdscript
# 创建
var array: Array[int] = [1, 2, 3, 4, 5]
var empty: Array = []

# 添加移除
array.append(6)           # 在末尾添加
array.push_back(7)        # 同上
array.insert(0, 0)        # 在位置 0 插入 0
array.remove_at(0)        # 移除位置 0
array.pop_back()          # 移除最后一个
array.clear()             # 清空数组

# 查询
array.size()              # 大小
array.is_empty()          # 是否为空
array.has(3)              # 是否包含 3
array.find(3)             # 返回索引（找不到返回 -1）

# 遍历
for item in array:
    print(item)

for i in range(array.size()):
    print(array[i])

# 函数式
array.map(func(x): return x * 2)   # [2, 4, 6, 8, 10]
array.filter(func(x): return x > 2)  # [3, 4, 5]
```

### 字典操作
```gdscript
# 创建
var dict: Dictionary = {"name": "test", "value": 42}
var empty: Dictionary = {}

# 访问
dict["name"]              # "test"
dict.get("value", 0)      # 42 (如果找不到返回 0)
dict.get("missing", -1)   # -1

# 修改
dict["new_key"] = "new_value"
dict["name"] = "updated"

# 查询
dict.has("name")          # true
dict.is_empty()           # false
dict.keys()               # ["name", "value", "new_key"]
dict.values()             # ["updated", 42, "new_value"]
dict.size()               # 3

# 遍历
for key in dict:
    print(key, dict[key])

for key in dict.keys():
    print(dict[key])
```

### 类型转换和检查
```gdscript
# 类型转换
var text = "42"
var num = int(text)           # 42
var flt = float(text)         # 42.0
var back_to_text = str(num)   # "42"

# 类型检查
if value is int:
    print("是整数")

var is_valid = value is String

# 强制转换
var base: Node = Button.new()
var button = base as Button
if button:
    button.text = "Click me"
```

---

## 场景和节点

### 节点基础
```gdscript
# 获取节点
var node = get_node("path/to/node")
var node = $NodeName                    # 相对路径（推荐）
var node = get_node("res://path.tscn")  # 绝对路径

# 查询
var parent = get_parent()               # 获取父节点
var children = get_children()           # 获取所有子节点
var owner = get_owner()                 # 获取场景所有者

# 节点操作
add_child(new_node)                     # 添加子节点
remove_child(child_node)                # 移除子节点
free()                                  # 删除该节点
queue_free()                            # 队列删除（更安全）

# 查找
find_child("name", true, false)         # 递归查找子节点
get_tree().get_nodes_in_group("group") # 获取组中所有节点
```

### 场景加载
```gdscript
# 加载场景
var scene = load("res://path/to/scene.tscn")
var instance = scene.instantiate()
add_child(instance)

# 或一步完成
var instance = load("res://path/to/scene.tscn").instantiate()
add_child(instance)

# 动态加载
var resource = ResourceLoader.load("res://path/to/resource.tres")

# 预加载（编辑器验证路径）
@onready var preloaded_scene = preload("res://path/to/scene.tscn")
```

### 节点属性
```gdscript
# 常用属性
node.visible = true                     # 可见性
node.modulate = Color.WHITE             # 颜色/透明度
node.position = Vector2(100, 200)       # 位置
node.rotation = PI / 4                  # 旋转
node.scale = Vector2(2, 2)              # 缩放
node.z_index = 10                       # 渲染顺序

# 禁用/启用
node.process_mode = PROCESS_MODE_INHERIT
node.process_mode = PROCESS_MODE_DISABLED
node.process_mode = PROCESS_MODE_ALWAYS

# 分组
add_to_group("enemies")                 # 添加到组
is_in_group("enemies")                  # 检查是否在组中
remove_from_group("enemies")            # 移除组
```

---

## 信号系统

### 信号基础
```gdscript
# 定义信号
signal health_changed(new_health: int)
signal enemy_died

# 发出信号
health_changed.emit(75)
enemy_died.emit()

# 连接信号
health_changed.connect(_on_health_changed)
health_changed.connect(_on_health_changed.bindv([75]))  # 带参数

# 信号回调函数
func _on_health_changed(new_health: int) -> void:
    print("Health: ", new_health)

# 断开连接
health_changed.disconnect(_on_health_changed)

# 一次性连接
health_changed.connect(_on_health_changed, CONNECT_ONE_SHOT)
```

### 内置信号
```gdscript
# 常用内置信号
ready.connect(_on_ready)              # 节点准备完毕
tree_exiting.connect(_on_tree_exiting)  # 节点退出树

# 按钮信号
button.pressed.connect(_on_button_pressed)

# 计时器信号
timer.timeout.connect(_on_timer_timeout)

# 输入信号
input.connect(_on_input_event)

# 物理信号
body_entered.connect(_on_body_entered)  # Area3D/Area2D
```

### 信号最佳实践
```gdscript
# ✅ 好做法：使用 CONNECT_ONE_SHOT
signal_name.connect(callback, CONNECT_ONE_SHOT)

# ✅ 好做法：使用 Callable 绑定参数
signal_name.connect(callback.bind(custom_value))

# ❌ 避免：在连接中创建 lambda
# signal_name.connect(func(): print("bad"))  # 难以断开

# ✅ 好做法：给回调函数命名规范
func _on_button_pressed() -> void:
    pass
```

---

## 物理和碰撞

### 碰撞检测 2D
```gdscript
# Area2D 基础
var area = Area2D.new()
add_child(area)

# 信号
area.area_entered.connect(_on_area_entered)
area.body_entered.connect(_on_body_entered)  # 与 RigidBody2D

# 检测方法
var areas = area.get_overlapping_areas()      # 重叠的区域
var bodies = area.get_overlapping_bodies()    # 重叠的刚体

# 射线检测
var space_state = get_world_2d().direct_space_state
var query = PhysicsRayQueryParameters2D.create(
    Vector2.ZERO, 
    Vector2(100, 0)
)
var result = space_state.intersect_ray(query)

if result:
    print("Hit: ", result.collider)
    print("Position: ", result.position)
```

### 刚体 2D
```gdscript
# RigidBody2D 基础
var body = RigidBody2D.new()
body.gravity_scale = 1.0
body.linear_velocity = Vector2(10, 0)
body.angular_velocity = PI  # 角速度

# 力和冲动
body.apply_force(Vector2(100, 0))          # 施加力
body.apply_impulse(Vector2(100, 0))        # 施加冲动
body.apply_torque(10)                      # 施加扭矩

# 属性
body.freeze = false                        # 冻结物体
body.lock_rotation = true                  # 锁定旋转
body.mass = 2.0                            # 质量
```

---

## 输入处理

### 输入事件处理
```gdscript
# 在 _input 中处理输入
func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_SPACE:
            jump()
        get_tree().root.set_input_as_handled()  # 标记已处理

# 在 _process 中检查输入
func _process(_delta: float) -> void:
    if Input.is_action_pressed("ui_right"):
        move_right()
    if Input.is_action_just_pressed("ui_accept"):
        confirm()

# 获取输入值
var direction = Input.get_axis("ui_left", "ui_right")
var velocity = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
```

### 鼠标输入
```gdscript
# 鼠标位置
var mouse_pos = get_global_mouse_position()
var local_mouse = get_local_mouse_position()

# 鼠标事件
if event is InputEventMouseButton:
    if event.pressed:
        if event.button_index == MOUSE_BUTTON_LEFT:
            click()

# 鼠标运动
if event is InputEventMouseMotion:
    print("Mouse moved to: ", event.position)

# 光标
Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
```

---

## 常见难点

### 难点 1: 类型不兼容错误
```gdscript
# ❌ 错误: 无法直接比较不同类型
var count = "5"
if count == 5:  # 类型不匹配
    pass

# ✅ 正确: 进行类型转换
if int(count) == 5:
    pass

# ✅ 正确: 声明类型
var count: int = 5
```

### 难点 2: 空引用 (Null Reference)
```gdscript
# ❌ 错误: 不检查 null
var node = get_node("MissingNode")
node.position = Vector2(0, 0)  # 崩溃!

# ✅ 正确: 检查 null
var node = get_node_or_null("MissingNode")
if node:
    node.position = Vector2(0, 0)

# ✅ 正确: 使用 find_child
var node = find_child("NodeName")
if node:
    node.position = Vector2(0, 0)
```

### 难点 3: 信号连接泄漏
```gdscript
# ❌ 问题: 不断开信号导致内存泄漏
# 在 _ready 中多次连接而不断开
if not signal_connected:
    signal_name.connect(callback)
    signal_connected = true

# ✅ 正确: 在需要时连接，不用时断开
func _ready() -> void:
    signal_name.connect(callback)

func _exit_tree() -> void:
    signal_name.disconnect(callback)
```

### 难点 4: 生命周期问题
```gdscript
# ❌ 问题: 在 _init 中使用 get_parent()
func _init() -> void:
    parent = get_parent()  # 返回 null!

# ✅ 正确: 在 _ready 中获取
func _ready() -> void:
    parent = get_parent()  # 现在有效

# ✅ 正确: 使用 @onready
@onready var parent = get_parent()
```

### 难点 5: 输入重复处理
```gdscript
# ❌ 问题: 同时在 _input 和 _process 处理输入
func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_SPACE:
            jump()
        # 忘记标记为已处理

func _process(_delta: float) -> void:
    if Input.is_action_just_pressed("ui_accept"):  # 也会被触发!
        jump()

# ✅ 正确: 使用 set_input_as_handled()
func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_SPACE:
            jump()
            get_tree().root.set_input_as_handled()
```

### 难点 6: 枚举值错误
```gdscript
# ❌ 在 GDScript 4.x 中错误
enum State {
    IDLE = "idle",      # ❌ 字符串值不允许
    RUNNING = "running"
}

# ✅ 正确: 使用整数
enum State {
    IDLE = 0,
    RUNNING = 1,
    JUMPING = 2
}

# 或使用 const + Dictionary
const STATE_NAMES = {
    0: "IDLE",
    1: "RUNNING",
    2: "JUMPING"
}
```

### 难点 7: 类实例化问题
```gdscript
# ❌ 错误: 某些类不能直接 new()
var timer = Timer.new()  # 在某些上下文中可能失败
var button = Button.new()  # 可能需要特殊初始化

# ✅ 正确: 对于 UI 节点使用场景
var button_scene = preload("res://path/to/button.tscn")
var button = button_scene.instantiate()

# ✅ 正确: 对于简单节点可以 new()
var label = Label.new()
label.text = "Hello"
```

---

## 性能优化

### 优化 1: 对象池
```gdscript
class_name ObjectPool

var pool: Array[Node] = []
var object_scene: PackedScene

func _init(scene: PackedScene, initial_size: int = 10) -> void:
    object_scene = scene
    for i in range(initial_size):
        pool.append(scene.instantiate())

func get_object() -> Node:
    if pool.is_empty():
        return object_scene.instantiate()
    return pool.pop_back()

func return_object(obj: Node) -> void:
    obj.visible = false
    obj.get_parent().remove_child(obj)
    pool.append(obj)
```

### 优化 2: 缓存
```gdscript
class_name CacheExample

var _cache: Dictionary = {}

func get_expensive_value(key: String) -> int:
    if _cache.has(key):
        return _cache[key]
    
    var value = expensive_calculation(key)
    _cache[key] = value
    return value

func expensive_calculation(key: String) -> int:
    # 模拟昂贵的计算
    return hash(key) % 100

func clear_cache() -> void:
    _cache.clear()
```

### 优化 3: 延迟处理
```gdscript
# ❌ 问题: 每帧处理所有敌人
func _process(_delta: float) -> void:
    for enemy in enemies:
        check_line_of_sight(enemy)  # 昂贵操作

# ✅ 正确: 用计数器延迟处理
var check_counter = 0
const CHECK_INTERVAL = 10

func _process(_delta: float) -> void:
    check_counter += 1
    if check_counter >= CHECK_INTERVAL:
        check_counter = 0
        for enemy in enemies:
            check_line_of_sight(enemy)
```

### 优化 4: 使用 visible 而不是 process_mode
```gdscript
# ✅ 好: 隐藏但继续处理
node.visible = false

# ✅ 更好: 完全禁用处理
node.process_mode = PROCESS_MODE_DISABLED

# ✅ 最好: 对大量节点使用
for node in inactive_nodes:
    node.process_mode = PROCESS_MODE_DISABLED
```

---

## 网络编程

### WebSocket 基础
```gdscript
class_name SimpleWebSocket

var websocket: WebSocketPeer
var connected = false

func _ready() -> void:
    websocket = WebSocketPeer.new()
    websocket.connect_to_url("ws://localhost:8080")

func _process(_delta: float) -> void:
    websocket.poll()
    
    if websocket.get_ready_state() == WebSocketPeer.STATE_OPEN:
        if not connected:
            connected = true
            print("Connected!")
    
    while websocket.get_available_packet_count():
        var packet = websocket.get_message().get_string_from_utf8()
        print("Received: ", packet)

func send_message(msg: String) -> void:
    if websocket.get_ready_state() == WebSocketPeer.STATE_OPEN:
        websocket.send_text(msg)
```

### HTTP 请求
```gdscript
# 发送 HTTP 请求
var http = HTTPClient.new()
http.connect_to_host("example.com", 443, TLSOptions.client())

# 或使用 HTTPRequest 节点
@onready var http_request = HTTPRequest.new()

func _ready() -> void:
    add_child(http_request)
    http_request.request_completed.connect(_on_request_completed)
    http_request.request("https://api.example.com/data")

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
    var json = JSON.new()
    var data = json.parse_string(body.get_string_from_utf8())
    print("Response: ", data)
```

---

## 调试技巧

### 打印和日志
```gdscript
# 基础打印
print("Simple message")
print("Count: ", count, ", Name: ", name)

# 格式化打印
print("Count: %d, Name: %s" % [count, name])

# 调试打印（可在调试器中关闭）
print_debug("Debug info")

# 错误打印
push_error("This is an error")
push_warning("This is a warning")

# 堆栈追踪
print_stack()

# 性能测量
var start_time = Time.get_ticks_msec()
# ... do work ...
var elapsed = Time.get_ticks_msec() - start_time
print("Took %d ms" % elapsed)
```

### 断点和调试器
```gdscript
# 在代码中设置断点（调试器中）
breakpoint  # 无条件断点

# 条件断点
if condition:
    breakpoint

# 调试器命令
# F5 - 运行
# F6 - 步过
# F7 - 步入
# F8 - 步出
```

### 检查器
```gdscript
# 在检查器中看到变量
@export var speed: float = 100.0   # 在编辑器中可编辑

# 调试时观看变量
var _watch_value: int = 0  # 在调试器中观察

# 打印节点树
get_tree().call_group_flags(0, "", "print_tree_pretty")
```

---

## 最佳实践速查表

### ✅ 应该做的事

```gdscript
# 1. 使用类型提示
var count: int = 0
func calculate(a: int, b: int) -> int:
    return a + b

# 2. 命名约定
var player_speed: float = 100.0        # 蛇形命名
const MAX_HEALTH = 100                 # 大写常量
func _on_button_pressed() -> void:     # 下划线开头为私有

# 3. 检查 null
var node = get_node_or_null("Node")
if node:
    node.do_something()

# 4. 使用 @onready
@onready var sprite = $Sprite2D
@onready var collision = $CollisionShape2D

# 5. 组织代码
# 分组：属性 -> 信号 -> lifecycle -> 方法 -> 内部方法

# 6. 使用常量
const SPEED = 100.0
const ANIMATION_SPEED = 0.2

# 7. 异步操作
await get_tree().create_timer(1.0).timeout
print("1 second passed")
```

### ❌ 应该避免的事

```gdscript
# 1. 避免全局变量
var global_var = 0  # ❌ 难以追踪

# 2. 避免长函数
func do_everything_at_once() -> void:  # ❌ 难以维护
    pass

# 3. 避免嵌套过深
if a:
    if b:
        if c:
            do_something()  # ❌ 箭头反模式

# 4. 避免忽视信号断开
signal_name.connect(callback)  # ❌ 可能泄漏

# 5. 避免在 _init 中使用场景树
func _init() -> void:
    parent = get_parent()  # ❌ 返回 null

# 6. 避免手动内存管理混乱
var node = Node.new()
# ... 忘记释放  # ❌ 内存泄漏
```

---

## 常用快捷键

| 快捷键 | 功能 |
|--------|------|
| F5 | 运行项目 |
| F6 | 运行主场景 |
| F1 | 打开文档 |
| Ctrl+K | 打开脚本 |
| Ctrl+Shift+N | 新脚本 |
| Ctrl+H | 替换 |
| Ctrl+G | 转到行 |
| F9 | 切换断点 |
| F10 | 步过 |
| F11 | 步入 |

---

## 常用节点类型速查

```gdscript
# 2D 节点
Node2D              # 基础 2D 节点
Sprite2D            # 显示图像
AnimatedSprite2D    # 动画精灵
Area2D              # 区域碰撞
RigidBody2D         # 物理刚体
CharacterBody2D     # 角色控制

# UI 节点
Control             # UI 基础
Label               # 文字
Button              # 按钮
TextEdit            # 文本编辑
ColorPickerButton   # 颜色选择

# 工具节点
Timer               # 计时器
AudioStreamPlayer   # 音频播放
AnimationPlayer     # 动画控制
Tween               # 补间动画

# 管理节点
Node                # 基础节点
CanvasLayer         # 画布层
SubViewport         # 子视口
```

---

## 常见错误代码示例

### 错误 1: 类型转换
```gdscript
# ❌ 错误
var value = "42"
var sum = value + 10  # TypeError

# ✅ 正确
var value = "42"
var sum = int(value) + 10
```

### 错误 2: 信号处理
```gdscript
# ❌ 错误: 忘记参数类型
signal changed(value)

func _on_changed(val) -> void:  # ❌ 无类型
    pass

# ✅ 正确
func _on_changed(val: int) -> void:  # ✅ 有类型
    pass
```

### 错误 3: 数组索引
```gdscript
# ❌ 错误: 没有检查范围
var array = [1, 2, 3]
var item = array[10]  # IndexError

# ✅ 正确
if index < array.size():
    var item = array[index]
```

---

## 快速问题解决指南

| 问题 | 解决方案 |
|------|---------|
| "Cannot call method on null" | 检查变量是否为 null 使用 `if node:` |
| "Type mismatch" | 使用正确的类型转换 `int()`, `str()` 等 |
| "Signal already connected" | 在连接前检查或使用 CONNECT_ONE_SHOT |
| "Node not found" | 使用 `get_node_or_null()` 而不是 `get_node()` |
| 游戏卡顿 | 使用 Performance Monitor 分析，考虑使用对象池 |
| 内存泄漏 | 确保在 `_exit_tree()` 中断开信号 |

---

## 推荐学习资源

### 官方文档
- [Godot 4.5 文档](https://docs.godotengine.org/)
- [GDScript 参考](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/)
- [API 文档](https://docs.godotengine.org/en/stable/classes/)

### 视频教程
- Godot 官方频道
- Brackeys (社区)
- Heartbeast (社区)

### 社区资源
- [Godot Engine 论坛](https://forum.godotengine.org/)
- [Reddit r/godot](https://reddit.com/r/godot)
- [Discord 社区](https://discord.com/invite/godotengine)

---

## 使用本文档的方式

### 快速查询
当遇到问题时：
1. 在目录中找到相关章节
2. 查看示例代码
3. 复制相关代码到项目中

### 学习和参考
- 定期阅读"常见难点"部分
- 实践所有代码示例
- 建立自己的笔记

### 维护和更新
- 当遇到新的难点时添加
- 当发现更好的做法时更新
- 定期复习以巩固知识

---

**文档维护**: 2025-10-29  
**Godot 版本**: 4.5.1  
**GDScript 版本**: 4.x

🎮 **祝您 Godot 开发愉快！** 🚀

---

## 附录: 快速参考卡

### 节点生命周期
```
_init() → _ready() → _process() → ... → _exit_tree()
```

### 常用类型
```
int, float, String, Vector2, Vector3, Color, 
Array, Dictionary, Callable, Signal
```

### 常用节点
```
Node → Node2D, Control
Node2D → Sprite2D, Area2D, RigidBody2D
Control → Label, Button, TextEdit
```

### 三大信号用法
```gdscript
signal_name.emit()
signal_name.connect(callback)
signal_name.disconnect(callback)
```
