class_name WhisperModelManifest extends RefCounted

# E4-03（#245）：whisper.cpp 模型清单（版本 / 固定 URL / 大小 / SHA-256 / revision / license）。
# 大模型二进制绝不入 Git；仅记录可校验元数据。

const SOURCE_REVISION := "5359861c739e955e79d9a303bcbc70fb988958b1"
const FILENAME_SMALL := "ggml-small.bin"
const SIZE_SMALL := 487601967
const SHA256_SMALL := "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"
const LICENSE_MIT := "mit"
const ID_SMALL := "ggml-small"
## 稳定可读、与 revision/模型绑定；非虚构语义版本号。
const VERSION_SMALL := "ggml-small@5359861c739e955e79d9a303bcbc70fb988958b1"

const URL_SMALL := (
	"https://huggingface.co/ggerganov/whisper.cpp/resolve/"
	+ SOURCE_REVISION
	+ "/"
	+ FILENAME_SMALL
)


## 生产 multilingual small 清单（固定 revision，禁止 main 漂移 URL）。
static func production_small() -> Dictionary:
	return {
		"id": ID_SMALL,
		"version": VERSION_SMALL,
		"url": URL_SMALL,
		"size_bytes": SIZE_SMALL,
		"sha256": SHA256_SMALL,
		"source_revision": SOURCE_REVISION,
		"license": LICENSE_MIT,
		"filename": FILENAME_SMALL,
	}


static func is_valid_manifest(m: Dictionary) -> bool:
	if m.is_empty():
		return false
	if String(m.get("id", "")).is_empty():
		return false
	if String(m.get("version", "")).is_empty():
		return false
	if String(m.get("url", "")).is_empty():
		return false
	if int(m.get("size_bytes", -1)) <= 0:
		return false
	if String(m.get("sha256", "")).length() != 64:
		return false
	if String(m.get("filename", "")).is_empty():
		return false
	return true
