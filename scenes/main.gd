extends Node2D

const INCOME_SOURCE_VIEW_SCENE: PackedScene = preload("res://ui/income_source_view.tscn")
const PURCHASE_BUTTON_SCENE: PackedScene = preload("res://ui/purchase_button.tscn")
const CAMERA_MIN_ZOOM: float = 0.4
const CAMERA_MAX_ZOOM: float = 2.5
const CAMERA_ZOOM_STEP: float = 1.1
const GROUND_BOTTOM_SCREEN_MARGIN: float = 24.0

@onready var camera: Camera2D = $Camera2D
@onready var ground: Sprite2D = $World/Ground/Ground1
@onready var money_label: Label = $HUD/Panel/VBoxContainer/MoneyLabel
@onready var income_label: Label = $HUD/Panel/VBoxContainer/IncomeLabel
@onready var panel: PanelContainer = $HUD/Panel
@onready var purchase_button_scroll: ScrollContainer = $HUD/Panel/VBoxContainer/ScrollContainer
@onready var income_source_views: Node2D = $World/IncomeSourceViews
@onready var purchase_button_list: VBoxContainer = $HUD/Panel/VBoxContainer/ScrollContainer/PurchaseButtonList

var _dragging_camera: bool = false


func _ready() -> void:
	camera.make_current()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	IncomeManager.source_activation_changed.connect(_on_source_activation_changed)
	EconomyManager.money_changed.connect(_refresh_finances)
	IncomeManager.income_changed.connect(_refresh_finances)
	_create_income_source_views()
	_create_purchase_buttons()
	_refresh_finances()
	_clamp_camera_position()


func _on_viewport_size_changed() -> void:
	_clamp_camera_position()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			var was_dragging := _dragging_camera
			_dragging_camera = mouse_button.pressed and _is_pointer_over_world()
			if _dragging_camera or was_dragging:
				get_viewport().set_input_as_handled()
		elif mouse_button.pressed and mouse_button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if _is_pointer_over_world():
				_zoom_camera(mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP, mouse_button.position)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging_camera:
		var mouse_motion := event as InputEventMouseMotion
		camera.global_position -= mouse_motion.relative / camera.zoom
		_clamp_camera_position()
		get_viewport().set_input_as_handled()


func _is_pointer_over_world() -> bool:
	return get_viewport().gui_get_hovered_control() == null


func _zoom_camera(zoom_in: bool, pointer_position: Vector2) -> void:
	var old_zoom := camera.zoom.x
	var new_zoom := clampf(
		old_zoom * CAMERA_ZOOM_STEP if zoom_in else old_zoom / CAMERA_ZOOM_STEP,
		CAMERA_MIN_ZOOM,
		CAMERA_MAX_ZOOM
	)
	if is_equal_approx(old_zoom, new_zoom):
		return

	var viewport_size := get_viewport_rect().size
	var pointer_offset := pointer_position - viewport_size * 0.5
	var world_point := camera.global_position + pointer_offset / old_zoom
	camera.zoom = Vector2.ONE * new_zoom
	camera.global_position = world_point - pointer_offset / new_zoom
	_clamp_camera_position()


func _clamp_camera_position() -> void:
	var viewport_half_width := get_viewport_rect().size.x * 0.5 / camera.zoom.x
	var horizontal_bounds := _get_unlocked_source_horizontal_bounds()
	camera.global_position.x = clampf(
		camera.global_position.x,
		horizontal_bounds.x - viewport_half_width,
		horizontal_bounds.y + viewport_half_width
	)
	# Godot's positive Y axis points down. Let the camera descend far enough to show the
	# ground's top, while keeping the ground's lower edge outside the viewport.
	var viewport_half_height := get_viewport_rect().size.y * 0.5 / camera.zoom.y
	var ground_bottom := ground.global_position.y
	if ground.texture != null:
		ground_bottom += ground.texture.get_size().y * absf(ground.global_scale.y) * 0.5
	var max_camera_y := ground_bottom - viewport_half_height - GROUND_BOTTOM_SCREEN_MARGIN
	camera.global_position.y = minf(camera.global_position.y, max_camera_y)


func _get_unlocked_source_horizontal_bounds() -> Vector2:
	var min_x := 0.0
	var max_x := 0.0
	var has_unlocked_source := false
	for source_data in IncomeManager.sources:
		if source_data == null or not IncomeManager.source_active.get(source_data.id, false):
			continue
		var half_width := 0.0
		if source_data.display_texture != null:
			half_width = source_data.display_texture.get_size().x * absf(source_data.display_scale.x) * 0.5
		var source_left := source_data.display_position.x - half_width
		var source_right := source_data.display_position.x + half_width
		if not has_unlocked_source:
			min_x = source_left
			max_x = source_right
			has_unlocked_source = true
		else:
			min_x = minf(min_x, source_left)
			max_x = maxf(max_x, source_right)
	if not has_unlocked_source:
		return Vector2.ZERO
	return Vector2(min_x, max_x)


func _on_source_activation_changed(_source_id: String, _is_active: bool) -> void:
	_clamp_camera_position()


func _create_income_source_views() -> void:
	for source_data in IncomeManager.sources:
		if source_data == null:
			continue
		var source_view := INCOME_SOURCE_VIEW_SCENE.instantiate() as IncomeSourceView
		source_view.setup(source_data, _get_source_purchase_button(source_data.id))
		income_source_views.add_child(source_view)


func _create_purchase_buttons() -> void:
	for button_data in ButtonManager.buttons:
		if button_data == null or _is_source_purchase_button(button_data):
			continue
		var purchase_button := PURCHASE_BUTTON_SCENE.instantiate() as PurchaseButton
		purchase_button.setup(button_data)
		purchase_button_list.add_child(purchase_button)
	purchase_button_scroll.visible = purchase_button_list.get_child_count() > 0
	panel.offset_bottom = 390.0 if purchase_button_scroll.visible else 160.0


func _get_source_purchase_button(source_id: String) -> ButtonData:
	for button_data in ButtonManager.buttons:
		if _is_source_purchase_button(button_data) and button_data.effect_target == source_id:
			return button_data
	return null


func _is_source_purchase_button(button_data: ButtonData) -> bool:
	return button_data != null and button_data.effect_type == ButtonData.EffectType.ACTIVATE_SOURCE


func _refresh_finances(_value = null) -> void:
	money_label.text = "자금: %s원" % _format_number(EconomyManager.money)
	income_label.text = "수입: %s원 / 초" % _format_number(IncomeManager.get_total_income_per_second())


func _format_number(value: float) -> String:
	if absf(value) >= 1000000000.0:
		return "%.3e" % value
	return "%.2f" % value
