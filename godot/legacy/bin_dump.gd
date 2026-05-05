## 简单的 .bin 文件转储工具
extends Node

func _ready():
	print("🔍 开始分析 mahjong.bin...")
	dump_bin_file()

func dump_bin_file():
	var bin_path = "res://assets/mahjong_tiles/mahjong.bin"

	if not ResourceLoader.exists(bin_path):
		print("❌ 文件不存在: %s" % bin_path)
		return

	var file = FileAccess.open(bin_path, FileAccess.READ)
	if file == null:
		print("❌ 无法打开文件")
		return

	var data = file.get_buffer(file.get_length())
	print("✅ 读取 %d 字节" % data.size())

	# 打印前 1024 字节的十六进制
	print("\n📖 文件内容 (前 512 字节):")
	var output = ""
	for i in range(0, mini(512, data.size()), 16):
		var hex_line = "%04x: " % i
		for j in range(16):
			if i + j < data.size():
				hex_line += "%02x " % data[i + j]
			else:
				hex_line += "   "
		hex_line += " | "
		for j in range(16):
			if i + j < data.size():
				var b = data[i + j]
				if b >= 32 and b < 127:
					hex_line += char(b)
				else:
					hex_line += "."
		print(hex_line)
		output += hex_line + "\n"

	# 寻找坐标
	print("\n🎨 寻找坐标模式 (int16 x4)...")
	var found = 0
	for offset in range(0, mini(data.size() - 8, 5000), 2):
		var x = _read_int16(data, offset)
		var y = _read_int16(data, offset + 2)
		var w = _read_int16(data, offset + 4)
		var h = _read_int16(data, offset + 6)

		if _is_reasonable(x, y, w, h):
			if found < 100:
				print("  @0x%04x: x=%4d, y=%4d, w=%3d, h=%3d" % [offset, x, y, w, h])
			found += 1

	print("\n✅ 总共找到 %d 个可能的坐标" % found)

	# 也打印十进制
	print("\n📊 尝试不同的偏移量...")
	for offset_try in [0, 4, 8, 12, 16, 32]:
		if offset_try + 8 < data.size():
			var x = _read_int16(data, offset_try)
			var y = _read_int16(data, offset_try + 2)
			var w = _read_int16(data, offset_try + 4)
			var h = _read_int16(data, offset_try + 6)
			print("  @0x%04x: [%d, %d, %d, %d]" % [offset_try, x, y, w, h])

func _read_int16(data: PackedByteArray, offset: int) -> int:
	if offset + 2 > data.size():
		return 0
	var val = ((data[offset + 1] & 0xFF) << 8) | (data[offset] & 0xFF)
	if val > 32767:
		val -= 65536
	return val

func _is_reasonable(x: int, y: int, w: int, h: int) -> bool:
	return (x >= 0 and x <= 2048 and
			y >= 0 and y <= 2048 and
			w > 50 and w <= 256 and
			h > 50 and h <= 256)
