extends Node2D

const INCOME_SOURCE_VIEW_SCENE: PackedScene = preload("res://ui/income_source_view.tscn")
const WORLD_PURCHASE_BUTTON_SCENE: PackedScene = preload("res://ui/world_purchase_button.tscn")
const WORLD_CLICK_DIALOGUE_SCENE: PackedScene = preload("res://ui/world_click_dialogue.tscn")
const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")
const CAMERA_MIN_ZOOM: float = 0.4
const CAMERA_MAX_ZOOM: float = 2.5
const CAMERA_ZOOM_STEP: float = 1.1
const GROUND_BOTTOM_SCREEN_MARGIN: float = 24.0

@onready var camera: Camera2D = $Camera2D
@onready var wallpaper: Sprite2D = $World/WallPaper
@onready var ground: Sprite2D = $World/Ground/Ground1
@onready var money_label: Label = $HUD/Panel/VBoxContainer/MoneyLabel
@onready var income_label: Label = $HUD/Panel/VBoxContainer/IncomeLabel
@onready var income_source_views: Node2D = $World/IncomeSourceViews
@onready var world_layout: Node2D = $World/WorldLayout
@onready var developer_tools: DeveloperToolsPanel = $HUD/DeveloperTools

var _dragging_camera: bool = false


func _ready() -> void:
	camera.make_current()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	IncomeManager.source_activation_changed.connect(_on_source_activation_changed)
	EconomyManager.money_changed.connect(_refresh_finances)
	IncomeManager.income_changed.connect(_refresh_finances)
	world_layout.visible = false
	_create_income_source_views()
	_create_world_purchase_buttons()
	_create_world_click_dialogues()
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
				_zoom_camera(mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging_camera:
		var mouse_motion := event as InputEventMouseMotion
		camera.global_position -= mouse_motion.relative / camera.zoom
		_clamp_camera_position()
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_O:
		developer_tools.toggle()
		get_viewport().set_input_as_handled()


func _is_pointer_over_world() -> bool:
	return get_viewport().gui_get_hovered_control() == null and not _is_pointer_over_world_area()


func _is_pointer_over_world_area() -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = get_global_mouse_position()
	query.collide_with_areas = true
	query.collide_with_bodies = false
	return not get_world_2d().direct_space_state.intersect_point(query, 1).is_empty()


func _zoom_camera(zoom_in: bool) -> void:
	var old_zoom := camera.zoom.x
	var new_zoom := clampf(
		old_zoom * CAMERA_ZOOM_STEP if zoom_in else old_zoom / CAMERA_ZOOM_STEP,
		CAMERA_MIN_ZOOM,
		CAMERA_MAX_ZOOM
	)
	if is_equal_approx(old_zoom, new_zoom):
		return

	camera.zoom = Vector2.ONE * new_zoom
	_clamp_camera_position()


func _clamp_camera_position() -> void:
	# Use the max-zoom-out viewport width so horizontal pan limits stay unchanged at every zoom.
	var max_zoom_out_half_width := get_viewport_rect().size.x * 0.5 / CAMERA_MIN_ZOOM
	var horizontal_bounds := _get_unlocked_source_horizontal_bounds()
	camera.global_position.x = clampf(
		camera.global_position.x,
		horizontal_bounds.x - max_zoom_out_half_width,
		horizontal_bounds.y + max_zoom_out_half_width
	)
	# Godot's positive Y axis points down. Let the camera descend far enough to show the
	# ground's top, while keeping the ground's lower edge outside the viewport.
	var viewport_half_height := get_viewport_rect().size.y * 0.5 / camera.zoom.y
	var ground_bottom := ground.global_position.y
	if ground.texture != null:
		ground_bottom += ground.texture.get_size().y * absf(ground.global_scale.y) * 0.5
	var max_camera_y := ground_bottom - viewport_half_height - GROUND_BOTTOM_SCREEN_MARGIN
	camera.global_position.y = minf(camera.global_position.y, max_camera_y)
	if wallpaper.texture != null:
		var wallpaper_top := (
			wallpaper.global_position.y
			- wallpaper.texture.get_size().y * absf(wallpaper.global_scale.y) * 0.5
		)
		var min_camera_y := wallpaper_top + viewport_half_height
		camera.global_position.y = maxf(camera.global_position.y, min_camera_y)


func _get_unlocked_source_horizontal_bounds() -> Vector2:
	var min_x := 0.0
	var max_x := 0.0
	var has_unlocked_source := false
	for source_data in IncomeManager.sources:
		if source_data == null or not IncomeManager.source_active.get(source_data.id, false):
			continue
		var layout_sprite := _get_layout_sprite(source_data.id)
		if layout_sprite == null:
			continue
		var half_width := layout_sprite.texture.get_size().x * absf(layout_sprite.scale.x) * 0.5
		var source_left := layout_sprite.position.x - half_width
		var source_right := layout_sprite.position.x + half_width
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
		var layout_sprite := _get_layout_sprite(source_data.id)
		if layout_sprite == null:
			push_warning("Main: No world layout sprite for income source: " + source_data.id)
			continue
		var source_view := INCOME_SOURCE_VIEW_SCENE.instantiate() as IncomeSourceView
		source_view.setup(source_data, layout_sprite.position, layout_sprite.scale)
		income_source_views.add_child(source_view)


func _create_world_purchase_buttons() -> void:
	for button_data in ButtonManager.buttons:
		if button_data == null or not button_data.show_world_purchase_button:
			continue
		var layout_sprite := _get_layout_sprite(button_data.id)
		if layout_sprite == null:
			push_warning("Main: No world layout sprite for button: " + button_data.id)
			continue
		var world_button := WORLD_PURCHASE_BUTTON_SCENE.instantiate() as WorldPurchaseButton
		world_button.setup(button_data, layout_sprite)
		income_source_views.add_child(world_button)


func _get_layout_sprite(element_id: String) -> Sprite2D:
	return world_layout.get_node_or_null(element_id) as Sprite2D


func _create_world_click_dialogues() -> void:
	for button_data in ButtonManager.buttons:
		if button_data == null or button_data.click_dialogues.is_empty():
			continue
		var layout_sprite := _get_layout_sprite(button_data.id)
		if layout_sprite == null:
			push_warning("Main: No world layout sprite for dialogue button: " + button_data.id)
			continue
		var dialogue_component := WORLD_CLICK_DIALOGUE_SCENE.instantiate() as WorldClickDialogue
		dialogue_component.setup(button_data, layout_sprite)
		income_source_views.add_child(dialogue_component)


func _refresh_finances(_value = null) -> void:
	money_label.text = "자금: %s원" % NUMBER_FORMATTER.format_number(EconomyManager.money)
	income_label.text = "수입: %s원 / 초" % NUMBER_FORMATTER.format_number(IncomeManager.get_total_income_per_second())
