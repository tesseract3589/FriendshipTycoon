extends CanvasLayer

const RENDER_ORDER = preload("res://scripts/RenderOrder.gd")
const MOUSE_OFFSET := Vector2(16.0, 20.0)
const VIEWPORT_MARGIN := Vector2(8.0, 8.0)

var _panel: PanelContainer
var _label: Label
var _owner_id: String = ""


func _ready() -> void:
	layer = RENDER_ORDER.ScreenLayer.WORLD_DESCRIPTION
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", _create_panel_style())
	add_child(_panel)

	_label = Label.new()
	_label.custom_minimum_size = Vector2(110.0, 28.0)
	_label.custom_maximum_size = Vector2(280.0, 1000.0)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.12, 1.0))
	_label.add_theme_constant_override("outline_size", 3)
	_panel.add_child(_label)


func _process(_delta: float) -> void:
	if _panel.visible:
		_position_near_pointer()


func show_tooltip(content: String, owner_id: String) -> void:
	if content.is_empty():
		hide_tooltip(owner_id)
		return
	_owner_id = owner_id
	_label.text = content
	_panel.reset_size()
	_panel.size = _panel.get_combined_minimum_size()
	_panel.visible = true
	_position_near_pointer()



func hide_tooltip(owner_id: String = "") -> void:
	if not owner_id.is_empty() and owner_id != _owner_id:
		return
	_panel.visible = false
	_owner_id = ""


func _position_near_pointer() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_size := _panel.size
	var pointer := get_viewport().get_mouse_position()
	var position := pointer + MOUSE_OFFSET
	if position.x + panel_size.x > viewport_size.x - VIEWPORT_MARGIN.x:
		position.x = pointer.x - panel_size.x - MOUSE_OFFSET.x
	if position.y + panel_size.y > viewport_size.y - VIEWPORT_MARGIN.y:
		position.y = pointer.y - panel_size.y - MOUSE_OFFSET.y
	position.x = clampf(
		position.x,
		VIEWPORT_MARGIN.x,
		maxf(VIEWPORT_MARGIN.x, viewport_size.x - panel_size.x - VIEWPORT_MARGIN.x)
	)
	position.y = clampf(
		position.y,
		VIEWPORT_MARGIN.y,
		maxf(VIEWPORT_MARGIN.y, viewport_size.y - panel_size.y - VIEWPORT_MARGIN.y)
	)
	_panel.position = position


func _create_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.1, 0.92)
	style.border_color = Color(0.9, 0.95, 1.0, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 6.0
	style.content_margin_top = 6.0
	style.content_margin_right = 6.0
	style.content_margin_bottom = 6.0
	return style
