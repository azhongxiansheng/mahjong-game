## FairyGUI .bin 文件逆向分析工具
## 目标: 从 mahjong.bin 中提取精灵坐标定义

extends Node

class_name BinAnalyzer

## 分析 mahjong.bin 文件
func analyze_mahjong_bin() -> void:
	var bin_path = "res://assets/mahjong_tiles/mahjong.bin" # 需要复制过来
	# 或者从反编译项目
	var alt_path = "user://"

	print("\n" + "=" * 80)
	print("🔬 FairyGUI .bin 文件分析")
	print("=" * 80)

	# 尝试从用户目录读取 (需要手动复制)
	if ResourceLoader.exists(bin_path):
		print("✅ 找到 mahjong.bin")
		analyze_bin_file(bin_path)
	else:
		print("⚠️ mahjong.bin 未找到，尝试其他位置...")
		print("   请复制 mahjong.bin 到 res://assets/mahjong_tiles/")

## 分析单个 .bin 文件
func analyze_bin_file(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("❌ 无法打开文件: %s" % path)
		return

	var data = file.get_buffer(file.get_length())
	print("\n📊 文件大小: %d 字节" % data.size())

	# 打印文件头的十六进制
	print("\n🔍 文件头 (前 256 字节):")
	print("-" * 80)
	for i in range(0, mini(256, data.size()), 16):
		var hex_str = ""
		var ascii_str = ""
		for j in range(16):
			if i + j < data.size():
				var byte = data[i + j]
				hex_str += "%02x " % byte
				if byte >= 32 and byte < 127:
					ascii_str += char(byte)
				else:
					ascii_str += "."
		print("%04x: %-48s | %s" % [i, hex_str, ascii_str])

	# 尝试解析
	print("\n\n🔨 尝试解析...")
	print("-" * 80)

	# 寻找字符串
	print("\n🔎 寻找字符串...")
	_find_strings(data)

	# 寻找潜在的坐标数据
	print("\n🎨 寻找精灵坐标...")
	_find_sprite_coords(data)

	# 分析网格
	print("\n📐 可能的网格排列...")
	_analyze_grid_patterns()

## 在二进制数据中寻找字符串
func _find_strings(data: PackedByteArray) -> void:
	var found_count = 0
	for offset in range(0, mini(data.size() - 2, 2000)):
		# 尝试读取 FairyGUI 字符串格式: [length:u16][string...]
		if offset + 2 <= data.size():
			var length = (data[offset + 1] << 8) | data[offset] # 小端序

			if length > 0 and length < 100 and offset + 2 + length <= data.size():
				var str_bytes = data.slice(offset + 2, offset + 2 + length)
				var text = str_bytes.get_string_from_utf8()

				# 检查是否都是可打印字符
				var is_valid = true
				for c in text:
					if c.unicode_at(0) < 32 or c.unicode_at(0) >= 127:
						is_valid = false
						break

				if is_valid and found_count < 50:
					print("  @0x%04x: \"%s\" (len=%d)" % [offset, text, length])
					found_count += 1

## 寻找精灵坐标数据
func _find_sprite_coords(data: PackedByteArray) -> void:
	var coords = []

	# FairyGUI 通常使用 int16 或 int32 存储坐标
	# 格式可能是: x, y, width, height

	for offset in range(0, data.size() - 8, 2):
		if offset + 8 <= data.size():
			# 尝试读取 4 个 int16
			var x = _read_int16(data, offset)
			var y = _read_int16(data, offset + 2)
			var w = _read_int16(data, offset + 4)
			var h = _read_int16(data, offset + 6)

			# 检查是否合理
			if (_is_valid_coord(x, y, w, h)):
				var key = "%d,%d,%d,%d" % [x, y, w, h]
				if not key in coords:
					coords.append(key)

	if coords.size() > 0:
		print("  发现 %d 个可能的坐标:" % mini(coords.size(), 50))
		for i in range(mini(50, coords.size())):
			var parts = coords[i].split(",")
			var x = int(parts[0])
			var y = int(parts[1])
			var w = int(parts[2])
			var h = int(parts[3])
			print("    pos=(%4d,%4d), size=(%3dx%3d)" % [x, y, w, h])

## 检查坐标是否合理
func _is_valid_coord(x: int, y: int, w: int, h: int) -> bool:
	return (x >= 0 and x <= 2048 and
			y >= 0 and y <= 2048 and
			w > 0 and w <= 256 and
			h > 0 and h <= 256 and
			x + w <= 2048 and
			y + h <= 2048)

## 读取 int16
func _read_int16(data: PackedByteArray, offset: int) -> int:
	if offset + 2 > data.size():
		return 0
	# 小端序
	return ((data[offset + 1] & 0xFF) << 8) | (data[offset] & 0xFF)

## 分析可能的网格排列
func _analyze_grid_patterns() -> void:
	var patterns = [
		[9, 4, "9列 × 4行"],
		[6, 6, "6列 × 6行"],
		[17, 2, "17列 × 2行"],
		[34, 1, "34列 × 1行"],
		[23, 2, "23列 × 2行"],
		[11, 3, "11列 × 3行"],
	]

	for pattern in patterns:
		var cols = pattern[0]
		var rows = pattern[1]
		var desc = pattern[2]
		var total = cols * rows
		var width = cols * 86 # 85 + 1 padding
		var height = rows * 86
		print("  📊 %s (总共 %2d 个)" % [desc, total])
		print("     尺寸: %4d × %4d 像素" % [width, height])
