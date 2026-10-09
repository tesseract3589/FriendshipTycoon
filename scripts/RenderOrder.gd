class_name RenderOrder
extends RefCounted

# Scene depth only. Purchase effects and ButtonData.Type never select a layer.
enum WorldLayer {
	SKY = -100,
	CLOUDS = -90,
	BACKGROUND = -20,
	FOREGROUND = -10,
	OBJECT = 0,
	FRONT_FRAME = 10,
	GROUND = 20,
	BUTTON = 30,
	DESCRIPTION = 40
}

enum ScreenLayer {
	WORLD_DESCRIPTION = 1,
	HUD = 2,
	ERROR = 100
}


static func apply_world_layer(item: CanvasItem, layer: int) -> void:
	item.z_as_relative = false
	item.z_index = layer


static func get_effective_z_index(item: CanvasItem) -> int:
	var result := item.z_index
	var current := item
	while current.z_as_relative and not current.is_set_as_top_level():
		current = current.get_parent() as CanvasItem
		if current == null:
			break
		result += current.z_index
	return result
