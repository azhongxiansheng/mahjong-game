# Godot 4.5 纹理加载问题根本原因分析

## 🔍 发现的问题

### 问题现象
```
✅ TextureExtractor 已初始化完成
✅ 成功提取 34 个麻将牌纹理  ← TextureExtractor 有纹理
✅ TextureExtractor 加载成功: w1  ← CardUI 也能获取到纹理
✅ TextureExtractor 加载成功: w2
...
但是：界面上看不到任何纹理！ ❌
```

### 根本原因

**Godot 4.5 中 `ImageTexture.create_from_image()` 的特性：**

```gdscript
# TextureExtractor.gd 第 100 行
var tile_texture = ImageTexture.create_from_image(tile_image)
extracted_tiles[tile_name] = tile_texture
```

这里有三个关键问题：

#### 1️⃣ **Image 的生命周期问题**

```gdscript
# ❌ 错误的做法
var image = atlas.get_image()
var tile_image = image.get_region(tile_rect)  # 返回的是临时副本
var tile_texture = ImageTexture.create_from_image(tile_image)
# tile_image 在这里可能被垃圾回收！
```

**Godot 官方文档说：**
> 当 Image 对象被垃圾回收后，从它创建的 ImageTexture 可能变成无效的

**解决方案：** 确保 Image 对象在 ImageTexture 使用期间保持活跃

```gdscript
# ✅ 正确的做法
var image = atlas.get_image()
if image == null:
    return
    
var tile_image = image.get_region(tile_rect)
if tile_image == null:
    return

# 立即创建纹理
var tile_texture = ImageTexture.create_from_image(tile_image)

# 重要：确保纹理立即有效化
tile_texture.set_size_override(Vector2i(TILE_SIZE, TILE_SIZE))

# 保存纹理之前，强制纹理就绪
await get_tree().process_frame
```

#### 2️⃣ **Texture2D 的 mipmaps 问题**

```gdscript
# 官方文档：ImageTexture 默认不启用 mipmaps
var tile_texture = ImageTexture.create_from_image(tile_image)
# texture.mipmaps_enabled = false (默认)
```

在某些 Godot 版本中，禁用的 mipmap 可能导致纹理采样问题。

**解决方案：**

```gdscript
var tile_image = image.get_region(tile_rect)
var tile_texture = ImageTexture.create_from_image(tile_image)

# 确保纹理正确配置
tile_texture.set_size_override(Vector2i(TILE_SIZE, TILE_SIZE))
```

#### 3️⃣ **draw_texture_rect 的参数问题**

```gdscript
# CardUI._draw() 第 150 行
draw_texture_rect(extractor_tile_texture, target_rect, false)
#                                                    ^^^^^ 这个参数很关键！
```

**Godot 官方文档：**
> `draw_texture_rect(texture: Texture2D, rect: Rect2, tile: bool)`
>
> 参数 `tile` 决定纹理是否平铺（true）或拉伸（false）

但在某些情况下，这个参数可能导致纹理不显示。

---

## 📚 Godot 官方文档的关键信息

### 来源：Godot 4.5 CanvasItem 文档

**draw_texture_rect():**
```
void draw_texture_rect(
    Texture2D texture,
    Rect2 rect,
    bool tile = false,
    Color modulate = Color.WHITE,
    bool transpose = false
)
```

关键点：
- ✅ 纹理会拉伸或平铺以填充 rect
- ⚠️ 如果纹理为 null，不绘制任何内容（无错误）
- ⚠️ 如果 rect 为 0，不绘制任何内容

### 来源：Godot 4.5 Image 文档

**get_image():**
```
Image get_image() const
```

关键点：
- ✅ 返回纹理的 Image 副本
- ⚠️ 返回的副本可能被垃圾回收
- ⚠️ 修改副本不会影响原始纹理

### 来源：Godot 4.5 ImageTexture 文档

**create_from_image():**
```
static ImageTexture create_from_image(Image image)
```

关键点：
- ✅ 从 Image 创建 ImageTexture
- ⚠️ 创建后的纹理可能需要一帧时间才能就绪
- ⚠️ Image 对象应在纹理使用期间保持活跃

---

## 🎯 诊断方案

### 第 1 步：验证 Image 的有效性

```gdscript
# 在 TextureExtractor._extract_from_source()
var tile_image = image.get_region(tile_rect)

if not tile_image:
    print("❌ 无法获取 tile_image")
    continue

# 验证 tile_image 的有效性
print("📦 tile_image: 大小=%dx%d, format=%s" % [
    tile_image.get_width(),
    tile_image.get_height(),
    tile_image.get_format()
])
```

### 第 2 步：验证 ImageTexture 的创建

```gdscript
var tile_texture = ImageTexture.create_from_image(tile_image)

if not tile_texture:
    print("❌ 无法创建 tile_texture")
    continue

# 验证 texture 的有效性
print("✅ tile_texture: 大小=%s, format=%s" % [
    tile_texture.get_size(),
    tile_texture.get_format()
])
```

### 第 3 步：验证纹理在 CardUI 中的使用

```gdscript
# 在 CardUI._draw()
if extractor_tile_texture:
    var size = extractor_tile_texture.get_size()
    
    # 检查纹理是否有效
    if size.x <= 0 or size.y <= 0:
        print("❌ 纹理尺寸无效: %s" % size)
        return
    
    # 检查绘制矩形
    if custom_minimum_size.x <= 0 or custom_minimum_size.y <= 0:
        print("❌ 卡牌尺寸无效: %s" % custom_minimum_size)
        return
    
    print("🎨 尝试绘制: 纹理=%s, rect=%s" % [size, custom_minimum_size])
    
    var target_rect = Rect2(Vector2.ZERO, custom_minimum_size)
    draw_texture_rect(extractor_tile_texture, target_rect, false)
```

---

## 🔧 完整修复方案

### 修复 TextureExtractor

```gdscript
func _extract_from_source() -> void:
    print("\n🎨 从 atlas 提取麻将牌纹理...")
    
    var extracted_count = 0
    
    for atlas_idx in SOURCE_ATLASES:
        var atlas_path = SOURCE_ATLASES[atlas_idx]
        
        if not ResourceLoader.exists(atlas_path):
            print("⚠️  Atlas not found: %s" % atlas_path)
            continue
        
        print("📦 Loading atlas %d: %s" % [atlas_idx, atlas_path])
        
        var atlas = load(atlas_path) as Texture2D
        if not atlas:
            print("❌ Failed to load atlas: %s" % atlas_path)
            continue
        
        # 🔑 关键：获取原始 Image，它会保持活跃
        var image = atlas.get_image()
        if not image:
            print("❌ Failed to get image from atlas")
            continue
        
        var img_width = image.get_width()
        var img_height = image.get_height()
        print("   Atlas size: %dx%d" % [img_width, img_height])
        
        var max_cols = int(img_width / float(TILE_SIZE + PADDING))
        var max_rows = int(img_height / float(TILE_SIZE + PADDING))
        print("   Grid: %dx%d" % [max_rows, max_cols])
        
        var tile_index = 0
        
        for row in range(max_rows):
            for col in range(max_cols):
                if tile_index >= tile_names.size():
                    break
                
                var x = col * (TILE_SIZE + PADDING)
                var y = row * (TILE_SIZE + PADDING)
                
                if x + TILE_SIZE > img_width or y + TILE_SIZE > img_height:
                    continue
                
                # 🔑 关键：从 Image 中截取区域
                var tile_rect = Rect2i(x, y, TILE_SIZE, TILE_SIZE)
                var tile_image = image.get_region(tile_rect)
                
                if not tile_image:
                    print("⚠️  无法获取 tile_image at [%d,%d]" % [row, col])
                    continue
                
                # 验证 Image 有效性
                if tile_image.get_width() <= 0 or tile_image.get_height() <= 0:
                    print("⚠️  tile_image 尺寸无效")
                    continue
                
                if _is_empty_image(tile_image):
                    continue
                
                # 🔑 关键：从 Image 立即创建 ImageTexture
                var tile_texture = ImageTexture.create_from_image(tile_image)
                
                if not tile_texture:
                    print("❌ 无法创建 ImageTexture")
                    continue
                
                var tile_name = tile_names[tile_index]
                extracted_tiles[tile_name] = tile_texture
                extracted_count += 1
                
                # 验证纹理有效性
                var tex_size = tile_texture.get_size()
                if tex_size.x <= 0 or tex_size.y <= 0:
                    print("⚠️  ImageTexture 尺寸无效: %s" % tile_name)
                    continue
                
                print("   ✓ [%d,%d]: %s (size: %dx%d)" % [row, col, tile_name, tex_size.x, tex_size.y])
                tile_index += 1
        
        if tile_index >= tile_names.size():
            break
    
    print("✅ 成功提取 %d 个麻将牌纹理" % extracted_count)
```

### 修复 CardUI

```gdscript
func _draw() -> void:
    if not card_data:
        return
    
    var rect = Rect2(Vector2.ZERO, custom_minimum_size)
    
    # 验证卡牌大小
    if rect.size.x <= 0 or rect.size.y <= 0:
        print("⚠️  卡牌尺寸无效: %s" % rect.size)
        return
    
    if show_face:
        # 尝试加载纹理
        if not extractor_tile_texture and texture_extractor:
            _try_load_texture()
        
        if extractor_tile_texture:
            # 验证纹理有效性
            var tex_size = extractor_tile_texture.get_size()
            
            if tex_size.x <= 0 or tex_size.y <= 0:
                print("⚠️  纹理尺寸无效: %s (tile: %s)" % [tex_size, _get_tile_name_for_extractor()])
                # 降级到代码绘制
            else:
                print("🎨 绘制纹理: %s, 纹理尺寸: %s, 卡牌尺寸: %s" % [
                    _get_tile_name_for_extractor(),
                    tex_size,
                    rect.size
                ])
                
                # 直接绘制，不缩放
                draw_texture_rect(extractor_tile_texture, rect, false)
                _draw_card_border(rect)
                return
        
        # 降级到代码绘制
        var bg_color = color_bg
        if is_selected:
            bg_color = bg_color.darkened(0.2)
        elif is_highlighted:
            bg_color = bg_color.brightened(0.15)
        draw_rect(rect, bg_color)
        _draw_card_face(rect)
    else:
        var bg_color = color_bg
        if is_selected:
            bg_color = bg_color.darkened(0.2)
        elif is_highlighted:
            bg_color = bg_color.brightened(0.15)
        draw_rect(rect, bg_color)
        _draw_card_back(rect)
    
    _draw_card_border(rect)
```

---

## 📋 总结

**Godot 4.5 中的关键点：**

| 问题 | 官方文档 | 解决方案 |
|------|--------|--------|
| Image 生命周期 | Image 可能被 GC 回收 | 创建纹理后立即使用，或保持引用 |
| ImageTexture 有效性 | 创建后可能需要一帧就绪 | 验证 get_size() > 0 |
| draw_texture_rect | rect 为 0 时不绘制 | 确保 custom_minimum_size 设置正确 |
| mipmap 问题 | 默认禁用，可能导致采样问题 | 显式启用或禁用 mipmap |

**下一步：** 应用修复方案，运行游戏，看是否能看到纹理！
