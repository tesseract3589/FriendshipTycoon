extends TextureRect


func _ready() -> void:
	name = "UpgradeModeBadge"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	PrestigeManager.shop_changed.connect(_refresh)
	PrestigeManager.upgrade_mode_changed.connect(_refresh)
	get_parent().resized.connect(_position_badge)
	_refresh()


func _refresh() -> void:
	visible = PrestigeManager.get_available_upgrade_modes().size() > 1
	texture = PrestigeManager.get_upgrade_mode_icon()
	_position_badge()


func _position_badge() -> void:
	var button := get_parent() as TextureButton
	# Anchor to the aspect-fitted artwork, including buttons with wide padding.
	var artwork_size := button.texture_normal.get_size()
	artwork_size *= minf(button.size.x / artwork_size.x, button.size.y / artwork_size.y)
	var artwork_position := (button.size - artwork_size) * 0.5
	var width := clampf(artwork_size.x * 0.4, 26.0, 48.0)
	size = Vector2(width, width * 0.75)
	position = artwork_position + Vector2(artwork_size.x, 0.0) - size * 0.5
