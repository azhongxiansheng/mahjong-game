extends Resource

## Tile3D 的实例级外观资源。
##
## 几何尺寸、圆角与碰撞属于 Tile3D 合同；皮肤只提供可替换的牌面、
## 牌背和胚体材质，避免换肤时重建 mesh 或破坏牌实例身份。

@export var skin_id: StringName = &""
@export var face_background_color: Color = Color.WHITE
@export var face_material_template: StandardMaterial3D
@export var back_material_template: StandardMaterial3D
@export var edge_material: StandardMaterial3D
@export var bevel_material: StandardMaterial3D
@export var side_material: StandardMaterial3D
@export var back_shell_material: StandardMaterial3D
@export var face_textures: Dictionary = {}
