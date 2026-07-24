class_name ProtocolConstants extends RefCounted

# E2-02（#232）协议常量唯一权威源。
# 与 Tile / Wall 实体命名空间契约对齐；其它 protocol 脚本不得再字面量重复定义。

const PROTOCOL_VERSION: int = 1
const MAX_SAFE_INT: int = Tile.MAX_SAFE_INSTANCE_ID
const TILES_PER_HAND: int = Tile.TILES_PER_HAND
const MAX_HAND_SEQ: int = Wall.MAX_HAND_SEQ
